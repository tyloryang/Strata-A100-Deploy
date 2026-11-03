# ⚠️ 待实施：vLLM 部署 Qwen3.8-27B 对照 Strata（步骤清单，未执行）

> **状态：未部署、未验证。** 本文原位于 `docs/vllm部署Qwen3.8-27B_步骤.md`，整理时移到「待实施-其他模型」，内容未改动（仅修正了链接）。
> 测试机已于 2026-11-02 23:40 前后回收，文中"同一台机器"的前提需要换成新机器重新核对。

> 目标：在同一台 2×A100-SXM4-40GB 上另起一个 vLLM 服务加载 Qwen3.8-27B（BF16），与现有 Strata + Qwen3.8-Flash-Next IQ3_XXS 做性能对比。
> **本文只写步骤，一条命令都没有在目标机上执行。** 所有"实测值"都必须到机器上跑出来再填。
> 关联文档：[压测文档](../docs/压测文档.md)（对比口径）、[目标机迁移清单](../docs/目标机迁移清单.md)、[参数详解](../docs/参数详解.md)。

---

## 0. 现在到哪一步了

| 项 | 状态 |
|---|---|
| 模型下载（51.77 GiB / 55.6 GB，18 个分片） | **已完成并校验 32/32 通过**，落在 `F:\models\Qwen3.8-27B`，详见 §2 |
| 校验清单 | `F:\models\Qwen3.8-27B.sha256`（sha256sum 格式，可直接 `-c`） |
| 镜像 | 走**渡渡鸟镜像站**（`swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/vllm/vllm-openai:v0.27.1`），命令在 §5，**未拉取** |
| 目标机部署 | **未执行**（按你的要求） |
| 与 Strata 的对比压测 | **未执行**，方案见 §9 |

---

## 1. 这个模型到底是什么（从 `config.json` 读的，不是猜的）

| 项 | 值 | 影响 |
|---|---|---|
| architecture | `Qwen3_5ForConditionalGeneration` | 是**多模态**模型，vLLM 会连视觉塔一起加载 |
| 层数 | 64 层：**16 层全注意力 + 48 层线性注意力**（`full_attention_interval: 4`） | KV 只算 16 层 → 长上下文比同尺寸稠密模型便宜一半以上 |
| attention | 24 头 / **4 个 KV 头** / `head_dim 256` | TP=2 时每卡 2 个 KV 头，切得开 |
| 上下文 | `max_position_embeddings: 262144` | 你命令里的 262144 是**原生长度**，不是硬撑 |
| 词表 | 248320 | — |
| MTP | `mtp_num_hidden_layers: 1` | **模型自带投机解码草稿头**，可以开 `--speculative-config` |
| RoPE | `partial_rotary_factor 0.25` + `mrope_interleaved` | 不要手动改 rope 参数，镜像会自己解析 |
| 权重 | BF16，**51.77 GiB（55.6 GB）** | 单卡 40 GB 装不下，**必须 TP=2**；每卡约 25.9 GiB |

**推论一**：262144 上下文在 2×40 GB 上**放得下**，账在 §6。
**推论二**：它是 VLM，纯文本压测时视觉塔白占约 1 GiB 显存和一段启动时间 → 加 `--language-model-only` 可以不要它。
**推论三**：模型自带 MTP 头，而 Strata 那边是 `--spec 4` 开着的。**不加 `--speculative-config` 的 vLLM 等于让了对手一个加速器**，对比不公平。

---

## 2. 模型已经下好了（本仓库内完成）

- 位置：`F:\models\Qwen3.8-27B`，33 个文件，51.77 GiB（55.6 GB，18 个 safetensors 分片 + tokenizer/config/chat_template）
- 源：ModelScope `Qwen/Qwen3.8-27B`。HF 直连本机只有 ~1.6 MB/s，ModelScope 4 并发聚合 20–35 MB/s，13.8 分钟拉完
- 校验结果：**32/32 全部通过**（逐文件 sha256 比对，51.77 GiB 读盘 33 s）
- 清单文件：`F:\models\Qwen3.8-27B.sha256`，同时已放进模型目录作为 `SHA256SUMS`
- 双源一致性：ModelScope 与 HF 是**同一份字节** —— 抽查 `config.json` / `merges.txt` / `tokenizer.json` / `chat_template.jinja` 四个文件两边 sha256 完全相同；18 个分片字节尺寸也逐一相同
- 说明：HF 这条 repo 的 API 返回 git blob SHA-1（不是 LFS oid），所以**校验以内容 sha256 为准**，该值已用实际下载字节反证过
- 目录里多一个 `configuration.json`（ModelScope 的仓库描述文件，2 字节级小文件），不影响 transformers / vLLM 加载

要在目标上重放这份校验：

```bash
cd /data/models/Qwen3.8-27B
sha256sum -c SHA256SUMS        # 应输出 32 行 OK
```

### 2.1 传到目标机

55.6 GB，别用 `scp` 整目录（断了就得重来）：

```bash
# 推荐：可续传、可限速
rsync -avP --partial --inplace \
  -e 'ssh -p <SSH端口>' \
  /f/models/Qwen3.8-27B/ root@<公网IP>:/data/models/Qwen3.8-27B/

# 校验清单一起带过去，落地后立刻验
scp -P <SSH端口> /f/models/Qwen3.8-27B.sha256 root@<公网IP>:/data/models/
ssh -p <SSH端口> root@<公网IP> \
  'cd /data/models && sha256sum -c Qwen3.8-27B.sha256'
```

若链路会断：`tar -C /f/models -cf - Qwen3.8-27B | split -b 8G - Qwen38.tar.`，分卷拷过去 `cat Qwen38.tar.* | tar -xf - -C /data/models/`，再校验。

> 注意目标机 `/data` 只剩 ~500 GB：55.6 GB 模型 + 8–11 GB 镜像没问题，但别再顺手下一份 FP8 权重（又是 28 GB）。

---

## 3. 上机器之前：三个硬性冲突

### 3.1 卡被占满 —— 这是最前置的一条

现状：Strata 容器占着 **GPU0 26.6 GiB / GPU1 32.7 GiB**（各 40 GiB）。
vLLM 要 0.92 × 40 × 2 的大部分，**两者不可能同时在线**。

```bash
# 先停 Strata（这一步会中断线上服务，挑低峰做）
cd /data/compose/strata && docker compose down
nvidia-smi --query-gpu=index,memory.used --format=csv   # 应该回到 ~0 MiB
```

对比完成后回滚：`cd /data/compose/strata && docker compose up -d`。

### 3.2 端口

Strata 是 `8800`（平台公网 `13270→8800`）。vLLM 用 `8000` 不冲突，但公网访问要么再开一条映射（例如 `13271→8000`），要么只在内网 `<内网IP>` / 本机 curl。

### 3.3 显存预算只够一套

即使停掉 Strata，两台服务也**不能并存**；所以"对比"是**交替跑**，不是同时跑。压测时两边都要冷启动、同样的预热轮次。

---

## 4. 宿主机检查（逐条过，任何一条不过就别往下走）

```bash
# 4.1 卡与驱动（应为 2×A100-SXM4-40GB，550.78，CUDA 12.4）
nvidia-smi -L
nvidia-smi --query-gpu=name,driver_version,memory.total,compute_cap --format=csv
nvidia-smi topo -m          # 预期 PHB（无 NVLink）

# 4.2 容器运行时
docker version --format '{{.Server.Version}}'
docker info | grep -i 'Runtimes'      # 必须能看到 nvidia
nvidia-ctk --version || dpkg -l | grep nvidia-container-toolkit

# 4.3 磁盘（985 GB 的 /dev/vdb，还要放 52 GB 模型 + 镜像）
df -h /data

# 4.4 内存（vLLM 从 safetensors mmap 加载，page cache 会吃满，靠可回收）
free -g
```

> CentOS 7 / 内核 3.10 + vLLM 官方镜像是可以的：镜像里自带 Ubuntu 22.04 的 glibc，只用宿主驱动。现状 550.78 支持 CUDA 12.x，不需要动驱动。

---

## 5. 镜像（v0.27.1，走渡渡鸟镜像站）

钉 **vLLM v0.27.1**。Docker Hub 在国内直连基本拉不动，走**渡渡鸟镜像同步站**（`docker.aityp.com`），它把镜像同步到华为云 SWR，页面直接给可拉地址。

### 5.1 为什么 0.27.1 能用（核过源码，不是猜的）

| 检查项 | 结论 |
|---|---|
| `Qwen3_5ForConditionalGeneration` 是否注册 | ✓ v0.27.1 的 `models/registry.py` 里有，挂在 `qwen3_5` 模块 |
| MTP 投机解码 | ✓ 同文件里有 `Qwen3_5MTP` / `Qwen3_5MoeMTP` |
| 官方要求的下限 | vLLM ≥ 0.17.0（0.27 高出 10 个小版本，够） |
| transformers 依赖 | `requirements/common.txt` 写 `>= 5.5.3`；模型要 ≥ 5.8.0。5.8.0 在 2026-05-05 已发布，镜像 2026-08-11 构建，实际装到的大概率 ≥5.8（落地仍要复核，见 5.6） |
| CUDA 构建 | 0.27.1 发布的都是 **cu129**（CUDA 12.9），与现有 550.78 驱动靠 minor version compatibility，和 `qwen38` tag 同一处境 |

### 5.2 候选 tag

| tag | 镜像 ID | 解压后体积 | 构建日期 | 用途 |
|---|---|---|---|---|
| **`v0.27.1`** | `sha256:e0cfcfcb9b86…` | 21.42 GB | 2026-08-11 | **用这个**，0.27 线的最新补丁 |
| `v0.27.0` | `sha256:62430ad7c682…` | 21.42 GB | 2026-08-10 | 要精确复现 0.27.0 时用 |
| `qwen38` | `sha256:a0facb04cacc…` | 15.11 GB | 2026-08-11 | 官方 recipe 的专供 tag，同日构建但体积差 6 GB，**不是和 0.27.1 等价的东西**，别混用 |
| `v0.32.0` | `sha256:bd8a5d7a8774…` | 23.40 GB | 2026-10-18 | 想比"更新内核"时的实验项，不是本次基线 |

### 5.3 拉取（一条命令 + retag）

```bash
docker pull swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/vllm/vllm-openai:v0.27.1
docker tag  swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/vllm/vllm-openai:v0.27.1 \
            vllm/vllm-openai:v0.27.1
```

`docker tag` 这步别省：后面 compose / 命令里引的都是短名字，retag 之后换版本只改一行。

拉完对一下：

```bash
docker image inspect vllm/vllm-openai:v0.27.1 --format '{{.Id}}  {{.Size}}  {{.Architecture}}'
# 期望：ID 以 e0cfcfcb9b86 开头、约 2.1e10 字节、amd64
# 多架构清单下 Id 是 amd64 的实际 config digest，不一定逐字符等于上面的 ID，以体积 + 架构为准
```

### 5.4 镜像站找不到 tag 时

镜像站**按需同步**：页面有「添加镜像」，提交 `docker.io/vllm/vllm-openai:<tag>` 后等它同步。查 tag 在不在：

```
https://docker.aityp.com/image/docker.io/vllm/vllm-openai:<tag>
```

返回 200 就是有；没有就走 5.5 的离线路线，别在前端干等。

### 5.5 离线导入（目标机完全不联网时）

```bash
# 有网机器
docker pull swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/vllm/vllm-openai:v0.27.1
docker save -o vllm-0271.tar \
  swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/vllm/vllm-openai:v0.27.1
sha256sum vllm-0271.tar > vllm-0271.tar.sha256

# 目标机
sha256sum -c vllm-0271.tar.sha256
docker load -i vllm-0271.tar
docker tag  swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/vllm/vllm-openai:v0.27.1 \
            vllm/vllm-openai:v0.27.1
```

`/data` 要留够：镜像解压 21.4 GB + 模型 55.6 GB。

### 5.6 拉完先验三件事（30 秒，别等加载完 55.6 GB 才发现问题）

```bash
docker run --rm --gpus '"device=0,1"' vllm/vllm-openai:v0.27.1 bash -lc '
  nvidia-smi --query-gpu=name,driver_version --format=csv
  python -c "import torch;print(\"cuda\", torch.cuda.is_available(), torch.version.cuda)"
  python -c "import vllm, transformers;print(\"vllm\", vllm.__version__, \"| transformers\", transformers.__version__)"
  python -c "from vllm.model_executor.models.registry import ModelRegistry as R; \
print(\"qwen3_5 registered:\", \"Qwen3_5ForConditionalGeneration\" in str(R.get_supported_archs()))"
'
```

四条都要过：

1. **驱动**：`cuda True`；报驱动过旧就换更早的 cu 构建，或评估升驱动（会牵动现有 Strata 容器，别顺手升）
2. **版本**：`vllm 0.27.1`
3. **transformers ≥ 5.8.0**：低了就在容器里补 `pip install -U "transformers>=5.8.0"`（0.27 只要求 ≥5.5.3，理论不冲突；纯文本服务加 `--language-model-only` 会绕开 Qwen3-VL 的 processor，这条依赖就没那么硬）
4. **`qwen3_5 registered: True`**：打印 False 说明拿到的不是这个镜像，回 5.2 换 tag

### 5.7 拉取常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| `401 Unauthorized` | 个别 namespace 要求登录 | 站内注册后 `docker login swr.cn-north-4.myhuaweicloud.com`；或 `docker login docker.aityp.com` 后按页面命令拉 |
| `manifest unknown` / `not found` | 该 tag 没同步 | 提交「添加镜像」，或退 `v0.27.0` |
| 拉到一半卡死 | SWR 限速 | 重试，`docker pull` 会续传；别中途 `docker system prune` |
| 拉完看不到短名字 | 只有 SWR 长名 | 就是没做 retag，按 5.3 补一条 |

---

## 6. 显存账本（2×A100-40G，bf16 权重 + fp8 KV）

```
每卡预算   0.92 × 40 GiB                        = 36.8 GiB
权重       51.77 GiB（55.6 GB）÷ 2 ≈ 25.9 GiB   → 剩 10.9 GiB
视觉塔     ~1.0 GiB（--language-model-only 可省）
MTP 头     ~0.4 GiB
激活+CUDA graph  ~1.5 GiB（--enforce-eager 时 ~0.6）
线性注意力 state 48 层 × 48 头 × 128 × 128 × 4B ≈ 151 MB / 每条序列
KV        16 层 × 2(K,V) × 4 头 × 256 维
          fp8_e4m3  → 32 KiB/token → 262144 token = 8.0 GiB（每卡 4.0）
          bf16      → 64 KiB/token → 262144 token = 16.0 GiB（每卡 8.0）
```

**结论**：

| 配置 | 每卡占用 | 判定 |
|---|---|---|
| fp8 KV + 262144 + `--language-model-only` | 25.9 + 0.4 + 1.5 + 4.0 ≈ 31.8 GiB | ✓ 余 ~5 GiB，稳 |
| fp8 KV + 262144（带视觉塔） | ≈ 32.8 GiB | △ 余 ~4 GiB，勉强；CUDA graph + MTP 容易顶边 |
| **bf16 KV（auto）+ 262144** | 25.9 + 1.0 + 1.5 + 8.0 ≈ 36.4 GiB | ✗ **顶到 36.8 的线，基本必失败** |

也就是说：**`fp8_e4m3` 在这台机器上不是"省着玩"，是 262144 能不能开起来的前提**。fp8 起不来时，`auto` 必须同时把 `--max-model-len` 降到 131072（KV 降到 8 GiB）才成立 —— 别以为"退 auto 就完事"。

KV 池是按 token 总量分配的，不是每条序列预扣 8 GiB。启动日志会打 `GPU KV cache size: N tokens`，**这个 N 是并发天花板，必须记下来**；按上表推算，fp8 + 262144 时 N 约 26–29 万 token。

池子偏小时的三个加杠杆（按代价排序）：`--gpu-memory-utilization 0.95`（+1.2 GiB/卡）→ `--language-model-only`（+1 GiB）→ 降 `--max-model-len`。

---

## 7. 启动命令（三选一，都还没执行）

### A. 保真版：完全照你给的原命令

```bash
export VLLM_API_KEY='<你的 key>'
vllm serve /data/models/Qwen3.8-27B \
  --served-model-name Qwen3.8-27B-BF16-FP8KV \
  --tensor-parallel-size 2 \
  --max-model-len 262144 \
  --gpu-memory-utilization 0.92 \
  --max-num-seqs 1 \
  --kv-cache-dtype fp8_e4m3 \
  --enforce-eager \
  --host 0.0.0.0 --port 8000 \
  --api-key "$VLLM_API_KEY"
```

这条能跑起来就是"复现你的配置"，但它的数字**不能代表 vLLM 的水平**，原因见下面三个坑。

### B. 对比版：和 Strata 同口径，才谈得上"哪个性能更好"

```bash
export VLLM_API_KEY='<你的 key>'
export VLLM_USE_RUST_FRONTEND=1
vllm serve /data/models/Qwen3.8-27B \
  --served-model-name Qwen3.8-27B-BF16-FP8KV \
  --tensor-parallel-size 2 \
  --max-model-len 262144 \
  --gpu-memory-utilization 0.92 \
  --max-num-seqs 32 \
  --max-num-batched-tokens 8192 \
  --kv-cache-dtype fp8_e4m3 \
  --language-model-only \
  --reasoning-parser qwen3 \
  --speculative-config '{"method":"mtp","num_speculative_tokens":3}' \
  --host 0.0.0.0 --port 8000 \
  --api-key "$VLLM_API_KEY"
```

改动逐条：`--max-num-seqs 32`（才谈得上并发吞吐）、去掉 `--enforce-eager`（CUDA graph 打开）、`--language-model-only`（纯文本，省视觉塔）、`--reasoning-parser qwen3`（否则 think 内容会塞进 `content`）、`--speculative-config`（用上模型自带的 MTP，对上 Strata 的 `--spec 4`）。

### C. 量化版：如果要比"同等显存下的最优解"

```bash
vllm serve /data/models/Qwen3.8-27B-FP8 \
  --served-model-name Qwen3.8-27B-FP8 \
  --tensor-parallel-size 2 \
  --max-model-len 262144 \
  --kv-cache-dtype fp8 \
  --speculative-config '{"method":"mtp","num_speculative_tokens":3}' \
  --reasoning-parser qwen3 \
  --host 0.0.0.0 --port 8000 --api-key "$VLLM_API_KEY"
```

（`Qwen/Qwen3.8-27B-FP8` 是官方 FP8 通道，约 28 GB，需要另外下 28 GB。**现在没下**，要不要下一句话的事。）

---

## 8. 三个坑（都是会直接影响结论的）

### 8.1 `--max-num-seqs 1` —— 和 Strata 的 `parallel=1` 是同一个方法学错误

`max-num-seqs` 是**同时在跑的序列数上限**，设 1 就是单流串行服务器：客户端并发 2/4/8 全部排队，聚合吞吐恒等于单流吞吐。你们今天那批 Strata 压测已经吃过一次这个亏：62 个用例里所有"并发"档位都卡在 ~50–110 tok/s，因为服务端只有一个槽位。要让 vLLM 展示真实吞吐，这条必须给到 16–64。

### 8.2 `--enforce-eager` 关掉了 CUDA graph

decode 阶段每个 token 都要重新下发一遍 kernel，典型代价 **10–25% 解码吞吐**。它在 1×5090 那种显存紧的卡上是"救命"参数（CUDA graph 捕获会 OOM），在 2×40 GB + bf16 权重下没有这个必要。

**做法**：保真版跑一次拿到"带 eager"的数，对比版跑一次拿到"正常"的数，报告里两个都写，并注明差异来自 CUDA graph，而不是引擎本身。

### 8.3 `--kv-cache-dtype fp8_e4m3` 在 A100 上是"软路径"，能起但未必划算

A100 是 SM80，而 vLLM 的 FP8 原生快速路径是 SM89+（源码里 `platforms/cuda.py::supports_fp8()` 就是 `has_device_capability(89)`）。官方文档对 `fp8_e4m3` 的说法是"Supported on CUDA 11.8+"，也就是说 SM80 上走的是注意力后端的反量化路径：**大概率起得来，但每个 token 多一次反量化**。

所以这里不是"能不能起"的问题，而是"省下的显存值不值这个算力"：fp8 把每 token 的 KV 从 64 KiB 压到 32 KiB，直接决定 KV 池大小（进而决定并发档位），代价是 decode 多一步反量化。**必须 A/B，不能拍脑袋。**

验证与兜底：

```bash
# 起了就记下这一行的数字
docker logs vllm 2>&1 | grep -E 'KV cache size|kv_cache_dtype|fp8'

# 起不来 → 换 auto（bf16 KV）时必须同时把 --max-model-len 降到 131072，见 §6
... --kv-cache-dtype auto ...
```

如果 fp8 起得来：**顺手做一次 `auto` 的 A/B**。32 KiB/token vs 64 KiB/token 直接决定 KV 池大小，进而决定并发档位，是这次对比里变量最大的一个开关。

---

## 9. 起服务后的验收（10 分钟）

```bash
KEY='<你的 key>'; H=http://127.0.0.1:8000

# 9.1 存活 + 鉴权
curl -s $H/health
curl -s -o /dev/null -w 'no-key  %{http_code}\n' $H/v1/models            # 401
curl -s -o /dev/null -w 'key     %{http_code}\n' -H "Authorization: Bearer $KEY" $H/v1/models  # 200

# 9.2 冒烟（注意 reasoning 内容是否已从 content 分离）
curl -s $H/v1/chat/completions -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{
  "model":"Qwen3.8-27B-BF16-FP8KV",
  "messages":[{"role":"user","content":"用一句话说明你是什么模型"}],
  "max_tokens":128,
  "chat_template_kwargs":{"enable_thinking":false}
}' | python -m json.tool

# 9.3 上限边界（应该 200 而不是截断）
python - <<'PY'
import json,urllib.request,os
key=os.environ['KEY']; n=200000
body=json.dumps({"model":"Qwen3.8-27B-BF16-FP8KV","prompt":"x "*n,"max_tokens":8}).encode()
r=urllib.request.Request("http://127.0.0.1:8000/v1/completions",body,{"Content-Type":"application/json","Authorization":"Bearer "+key})
print(urllib.request.urlopen(r,timeout=600).status)
PY

# 9.4 资源与指标
nvidia-smi --query-gpu=index,memory.used,utilization.gpu --format=csv
curl -s $H/metrics | grep -E 'vllm:(num_requests_running|gpu_cache_usage_perc|spec_decode_num_(accepted|draft)_tokens_total)'
```

记录四件事：**启动日志的 `GPU KV cache size` 数字**、双卡显存占用、模型加载耗时、`spec_decode` 是否非零（非零才说明 MTP 真的在工作）。

---

## 10. 对比压测方案（同口径，否则数字没意义）

### 10.1 铁律：换自然语料

现有 62 个用例全是 `--dataset random`，随机 token 下 MTP 接受率只有 2–5%、前缀缓存恒 0。**vLLM 这边同样不能喂 random**，否则测的是"两个引擎在随机 token 上谁更差"，两边都没有参考价值。

准备 ≥32 条 500–2000 字中文运维问答，`--dataset custom --dataset-path prompts_zh.jsonl`。

### 10.2 三个形态 × 并发梯度

| 形态 | input | output | 并发 |
|---|---|---|---|
| 短问答 | 512 | 256 | 1 / 2 / 4 / 8 |
| 典型运维（对齐你们原来的口径） | 2000 | 100 | 1 / 2 / 4 / 8 |
| 长文阅读 | 8192 | 256 | 1 / 2 / 4 |

每组 ≥3 次取中位；`--stream` 必开，否则拿不到 TTFT/TPOT。

### 10.3 指标对齐

| 类别 | 字段 | 备注 |
|---|---|---|
| 延迟 | TTFT / TPOT / ITL / E2EL 的 p50、p95、p99 | 两边同一定义 |
| 吞吐 | 输出 tok/s、总 tok/s、req/s、Goodput | 成本看输出 tok/s |
| 投机 | `Spec. Accept Rate`、`Avg Decoded Tok/Iter` | vLLM 侧读 `spec_decode` 计数反算 |
| 缓存 | KV/前缀命中率 | 两边都靠多轮 prompt 触发 |
| 资源 | 双卡显存、`MemAvailable`、KV 池 token 数 | vLLM 的池子是一次性分配，不随负载变 |

### 10.4 跑法（重启次数最少）

1. **Strata 基线**：现状配置 + 自然语料，三形态 × 并发梯度 —— 这一步必须先做，因为现在的"基线"是 random 跑出来的，不能直接拿来对比
2. **vLLM 保真版**（§7 A）：同样矩阵，拿到"带 eager、单槽"的数
3. **vLLM 对比版**（§7 B）：同样矩阵，拿到 vLLM 的真实水平
4. **fp8 KV vs auto** 各跑一轮（如果 fp8 能起）
5. 需要第三点时再加 §7 C 的 FP8 权重

### 10.5 预期与解读（先写在前面，避免事后找理由）

- **单流解码**：Strata 90–160 tok/s（IQ3_XXS 3-bit + CPU 专家缓存）对 vLLM bf16 + MTP，vLLM 大概率**更快**（A100 上 27B bf16 TP2 单流通常 40–70 tok/s，但有 MTP 会拉高；IQ3_XXS 那边专家在 CPU 上），谁赢取决于 MTP 接受率 —— 这正好是这次要测的
- **长上下文（200K）**：vLLM 的 prefill 是纯 GPU，Strata 是 5.1k tok/s。vLLM 应该明显更快，这是它最可能拉开差距的地方
- **聚合吞吐**：vLLM 开了批处理才比得动；单槽的 vLLM 一定输给任何多槽配置
- **口径差异必须写进结论**：Strata 是 3-bit 量化 + 专家缓存，vLLM 是 bf16 全显存。这不是"引擎 A vs 引擎 B"，是"方案 A vs 方案 B"。要纯引擎对比，得让 vLLM 也上量化（§7 C）

---

## 11. 风险与回滚

| 风险 | 触发信号 | 处置 |
|---|---|---|
| 架构不支持 | 启动即报 `Qwen3_5ForConditionalGeneration is not supported` | 回 §5 核对拿到的是不是 `v0.27.1`；0.27 已有该架构，报这个错基本就是拉错镜像 |
| fp8 KV 起不来 | `kv_cache_dtype` 相关报错 / 启动中断 | 退 `--kv-cache-dtype auto` **并把 `--max-model-len` 降到 131072** |
| CUDA graph OOM | 启动末段 `torch.OutOfMemoryError` in graph capture | 加 `--enforce-eager`，或 `--language-model-only`，或降 `--gpu-memory-utilization` 到 0.88 |
| 加载太慢 / 内存压力 | 加载 5 分钟以上，`MemAvailable` 掉到 1–2 GB | 属正常（mmap + page cache 可回收），但别同时压测；必要时 `--load-format safetensors` |
| 端口暴露 | 8000 绑 0.0.0.0 且平台做了公网映射 | 至少 iptables 限源网段；key 不要出现在 `ps` 里（用环境变量文件） |
| 对比期间线上服务中断 | 停 Strata 之后 | 低峰期执行；压测完 `docker compose up -d` 复原 |
| 结论被 random 语料污染 | 报告里出现 random 数据集出的 tok/s | 禁止入报告 |

---

---

## 12. 这份文档里没做的事

- 没有连目标机、没有执行任何 `docker`/`vllm` 命令
- 没有下 `Qwen/Qwen3.8-27B-FP8`（28 GB，需要时再说）
- 没有把模型传到目标机（`/data/models/Qwen3.8-27B` 还是空的）

要开工时按 §3 → §4 → §5 → §7 的顺序走，每步的验收点都在对应小节里。

---

## 附录 A：你给的那条命令，逐参数过一遍

| 参数 | 作用 | 在这台机器上 | 判断 |
|---|---|---|---|
| `<MODEL_PATH>` | 权重目录 | `/data/models/Qwen3.8-27B` | ✓ 换成绝对路径，别用容器外路径 |
| `--served-model-name` | API 里的 `model` 字段 | 任意 | ✓ 建议保留，压测脚本里按这个名调 |
| `--tensor-parallel-size 2` | 权重切两卡 | BF16 51.77 GiB，单卡 40 GB 装不下 | ✓ 必须 2；4 个 KV 头能均分 |
| `--max-model-len 262144` | 上下文上限 | 模型原生就是这个长度 | ✓ 成立，账见 §6 |
| `--gpu-memory-utilization 0.92` | 每卡预留比例 | 36.8 GiB/卡 | ✓ 合理；CUDA graph OOM 时可降到 0.88 |
| `--max-num-seqs 1` | 并发序列上限 | — | ✗ **这是给单流延迟测试用的**，做吞吐对比会失真（§8.1） |
| `--kv-cache-dtype fp8_e4m3` | KV 压到 fp8 | SM80 走反量化路径 | △ 能起，但要做 fp8 vs auto 的 A/B（§8.3） |
| `--enforce-eager` | 关 CUDA graph | 显存充足，不需要 | ✗ decode 白掉 10–25%（§8.2） |
| `--host 0.0.0.0` | 监听地址 | 平台怎么映射端口决定暴露面 | △ 只在内网用就绑内网 IP；要公网就加一条端口映射 |
| `--port 8000` | 端口 | 与 Strata 的 8800 不冲突 | ✓ |
| `--api-key "$VLLM_API_KEY"` | 鉴权 | 变量没 export 的话会传成空串 | △ 先 `export`；空 key 会让鉴权形同虚设 |

一句话：**这条命令跑起来是"单流、无图、无投机"的 vLLM**，拿它去和开了 `--spec 4` 的 Strata 比吞吐，vLLM 会输得很冤。

---

## 附录 B：常见启动失败对照

| 日志关键字 | 原因 | 处理 |
|---|---|---|
| `Qwen3_5ForConditionalGeneration is not supported` | 拿到的镜像不对（0.27.1 是支持的） | 按 §5.6 第 4 条验证，换回 `vllm/vllm-openai:v0.27.1` |
| `transformers version ... is too old` / processor 报错 | transformers < 5.8.0 | 换镜像，别手动 pip 升级 |
| `No available memory for the cache blocks` | KV 池为 0 | 降 `--max-model-len`，或 `--kv-cache-dtype auto`，或降 `--max-num-seqs` |
| `torch.OutOfMemoryError` 出现在 `capture` 阶段 | CUDA graph 捕获溢出 | 加 `--enforce-eager` / `--language-model-only` |
| `driver version ... is insufficient` | cu129 镜像 + 550 驱动 | 换 cu124/cu126 tag，或评估升驱动 |
| NCCL / `/dev/shm` 报错 | 容器 shm 太小 | `--shm-size 16g` 或 `--ipc=host` |
| 请求返回里全是 think 内容 | 没开 reasoning parser | 加 `--reasoning-parser qwen3`，客户端传 `chat_template_kwargs.enable_thinking=false` |

---

## 附录 C：docker 起法（等价于上面 A/B/C 任一命令）

```bash
docker run -d --name vllm-0271 \
  --gpus '"device=0,1"' --ipc=host --shm-size 16g \
  -p 8000:8000 \
  -v /data/models/Qwen3.8-27B:/models/Qwen3.8-27B:ro \
  -e VLLM_USE_RUST_FRONTEND=1 \
  vllm/vllm-openai:v0.27.1 \
  --model /models/Qwen3.8-27B \
  --served-model-name Qwen3.8-27B-BF16-FP8KV \
  --tensor-parallel-size 2 \
  --max-model-len 262144 \
  --gpu-memory-utilization 0.92 \
  --max-num-seqs 32 \
  --kv-cache-dtype fp8_e4m3 \
  --language-model-only \
  --reasoning-parser qwen3 \
  --speculative-config '{"method":"mtp","num_speculative_tokens":3}' \
  --host 0.0.0.0 --port 8000 \
  --api-key "$VLLM_API_KEY"

# 日志（KV 池那行在这里）
docker logs -f vllm-0271
```

权重目录挂 `:ro`，避免容器里误写。

---

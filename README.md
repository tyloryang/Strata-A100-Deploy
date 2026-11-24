# Strata + Qwen3.8-Flash-Next IQ3_XXS · 2×A100 离线部署

在无外网的 2 × A100-40GB 机器上部署 Strata 和 Qwen3.8-Flash-Next IQ3_XXS，提供 OpenAI / Anthropic 兼容 API、API Key 鉴权和 Web 聊天页。新部署从 **[Strata 0.2.20 离线迁移部署](docs/离线迁移部署-0.2.20.md)** 开始。

## Strata 0.2.20 离线部署

**0.2.20** 是发布版本，Linux CUDA 12 引擎和 Control 均为 **0.1.66**。官方预编译引擎包含 A100 的 `sm_80`，Control 自带 Python。部署步骤已在双 A100 SXM4 测试机跑通，内网目标机仍待验收。[官方发布说明](https://github.com/Niko1221/Strata/releases/tag/v0.2.20) · [本机升级实测](docs/Strata-0.2.20升级实测-2026-11-23.md)

1. 在可联网的机器准备官方 Control 与 CUDA 12 引擎包，校验 SHA-256。另备源机导出的 Docker 镜像、`/data/Strata-data` 模型数据、配置模板和驱动自检脚本。[离线材料与校验清单](docs/离线迁移部署-0.2.20.md#1-要准备的东西)
2. 在离线机导入镜像，分别将 Control 和引擎解压到 `/data/Strata-0.2.20` 和它的 `engine-cuda12` 子目录。随包 CUDA 12.9 的标注最低驱动为 575.51，测试机的 550.78 已跑通，535 驱动仍需在目标机验证。启动前运行探针并确认输出 `CUDA-PROBE-OK`。[解压步骤](docs/离线迁移部署-0.2.20.md#51-校验并解压) · [驱动自检](scripts/cuda_probe_0220.py)
3. 从模板生成启动 JSON 并设置新 API Key，按新版手册发布宿主机端口 `8800`。用 `/health`、带密钥的真实问答和启动日志，确认引擎为 **0.1.66**、**8 槽**、最大上下文 **229376**、**24,576 个专家全驻留**。[JSON 模板](deploy/strata-iq3_xxs.0.2.20.example.json) · [启动与验收](docs/离线迁移部署-0.2.20.md#6-启动)

本仓库也保留 **0.1.45** 的历史部署与调优记录。2026-11-14 的双 A100 PCIe 实测中，32K 无缓存单并发 8 次平均 TTFT 为 **8.149 秒**，相同前缀缓存命中的 **0.092 秒**单独列示。[PCIe 实测报告](docs/最新压测结果-2026-11-14.md)

### 0.2.20 启动 JSON（8 槽层拆分）

文件是 [`deploy/strata-iq3_xxs.0.2.20.example.json`](deploy/strata-iq3_xxs.0.2.20.example.json)，部署时放到 `/data/Strata-0.2.20/strata-iq3_xxs.json`。测试机 2026-11-23 的升级实测用的就是这一份，只有 `api_key` 换成了占位符。

```json
{
  "exe": "/data/Strata-0.2.20/engine-cuda12/strata",
  "args": [
    "--pack", "/data/Strata-data/packs/iq3_xxs",
    "--native", "/data/Strata-data/models/IQ3_XXS/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf",
    "--ple-gguf", "/data/Strata-data/models/IQ3_XXS/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00002-of-00002.gguf",
    "--expert-profile", "/data/Strata-0.2.20/data/expert-profile.bin",
    "--expert-cache", "auto",
    "--prefill", "auto:12288",
    "--prefill-pipe", "1",
    "--prompt-cache-every", "16384",
    "--short-read", "256",
    "--ple-io", "mmap",
    "--spec", "4",
    "--spec-min-p", "0.5",
    "--suffix-draft", "3",
    "--mtp", "/data/Strata-data/mtp/rt",
    "--mtp-window", "8192",
    "--max-context", "229376",
    "--kv-resident", "32768",
    "--kv", "k8v4",
    "--conversation-cache-mib", "16384",
    "--conversation-cache-slots", "64",
    "--conversation-cache-min-tokens", "4096",
    "--conversation-cache-park-gain", "256",
    "--batch", "8",
    "--resident-experts",
    "--vram-reserve-mib", "9216",
    "--vram-reserve-later-mib", "8192",
    "--trim-stage-weights",
    "--conversation-cache-min-free-mib", "12288"
  ],
  "env": {
    "STRATA_ROUTE_TAIL_SKIP": "0",
    "STRATA_PF_FUSED": "1",
    "MALLOC_MMAP_THRESHOLD_": "16777216",
    "STRATA_RESIDENT_HEADROOM_GIB": "12",
    "STRATA_SLOT_COPY_DIRECT": "1",
    "STRATA_SLOT_COPY_BATCHSYNC": "1"
  },
  "reasoning_effort": "none",
  "reasoning_budget_tokens": 4096,
  "reasoning_close_retry": true,
  "fit_max_tokens": true,
  "sampling": { "temperature": 1, "top_p": 0.95, "top_k": 20, "experimental_speed_projection": true },
  "cwd": "/data/Strata-0.2.20",
  "tokenizer": "/data/Strata-data/packs/iq3_xxs/tokenizer",
  "model_name": "qwen3.8-flash-next-iq3_xxs",
  "log": "/data/Strata-0.2.20/strata-iq3_xxs.log",
  "api_key": "<YOUR_API_KEY>",
  "parallel": 8,
  "lib_dirs": ["/data/Strata-0.2.20/engine-cuda12"],
  "port": 8080,
  "cuda": 12,
  "gpu": [0, 1],
  "gpus_asked": true,
  "layer_split": "26",
  "host": "0.0.0.0"
}
```

上面为了好读把 `args` 的参数名和值写在了同一行，内容与仓库里的文件一致。

**顶层字段**

| 字段 | 值 | 作用 |
|---|---|---|
| `exe` / `cwd` / `log` | `/data/Strata-0.2.20/...` | 引擎二进制、工作目录、引擎日志。都是容器内路径 |
| `lib_dirs` | `/data/Strata-0.2.20/engine-cuda12` | 用引擎包自带的 CUDA 12.9 cudart / cuBLAS，不用镜像里的 12.4 |
| `parallel` | `8` | 槽位数，由 `server.py` 翻译成 `--batch`（上限 8），**必须和 `args` 里的 `--batch 8` 一致** |
| `layer_split` | `"26"` | 双卡层拆分：CUDA0 跑第 0–25 层，CUDA1 跑其余层。写成具体数字 `--trim-stage-weights` 才能用 |
| `gpu` / `cuda` | `[0, 1]` / `12` | 用两张卡、CUDA 12 引擎 |
| `host` / `port` | `0.0.0.0` / `8080` | 容器内监听地址，宿主机经 `-p 8800:8080` 发布 |
| `api_key` | `<YOUR_API_KEY>` | 占位符，部署时换成新 Key 并 `chmod 600`，见[离线迁移 §5.2](docs/离线迁移部署-0.2.20.md#52-换-api_key) |
| `model_name` / `tokenizer` | `qwen3.8-flash-next-iq3_xxs` | 接口里的模型名、分词器目录 |
| `reasoning_effort` / `reasoning_budget_tokens` / `reasoning_close_retry` | `none` / `4096` / `true` | 默认不思考；请求里打开思考时预算 4096 token |
| `fit_max_tokens` | `true` | `max_tokens` 超出剩余上下文时自动缩短；提示本身超长仍返回 400 |
| `sampling` | `1 / 0.95 / 20` | 默认 temperature / top_p / top_k，请求里可覆盖 |
| `sampling.experimental_speed_projection` | `true` | ESP 默认**开**（0.1.45 推荐配置是关）。它是拒答方向投影，不是提速功能，见[参数详解 §2.7](docs/参数详解.md#27-esp-控制向量先读这一节) |
| `gpus_asked` | `true` | setup 的标记，对运行没有影响 |

**引擎参数（`args`）**

| 参数 | 值 | 作用 |
|---|---|---|
| `--pack` / `--native` / `--ple-gguf` / `--mtp` | `/data/Strata-data/...` | 模型包、主权重、PLE 表、MTP 草稿层，只读挂载 |
| `--expert-profile` | `/data/Strata-0.2.20/data/expert-profile.bin` | 专家热度排序。必须指向新目录，新容器不挂 `/data/Strata` |
| `--expert-cache` / `--resident-experts` | `auto` / 启用 | 显存放得下多少专家就放多少（本机 24576 个全放下）；内存里只留借给预填的那部分副本 |
| `--vram-reserve-mib` / `--vram-reserve-later-mib` | `9216` / `8192` | 算专家缓存时预留的显存 |
| `--trim-stage-weights` | 启用 | 每张卡只加载自己那几层的稠密权重 |
| `--max-context` | `229376` | 单请求最大上下文 |
| `--kv-resident` / `--kv` | `32768` / `k8v4` | 每个注意力层只在显存留 32768 格，完整 KV 放锁页内存；KV 量化格式 k8v4。`--kv-resident` 实测不能去掉 |
| `--batch` | `8` | 8 个槽位，层拆分下分成 2 组 × 4 槽 |
| `--prefill` | `auto:12288` | 预填块大小。**层拆分下实际生效的是 8192**（日志 `prompt chunk auto: 8192`），见[升级实测 §6.2](docs/Strata-0.2.20升级实测-2026-11-23.md#62-strata_nv_chunk0-无效) |
| `--ple-io` | `mmap` | PLE 表走页缓存，不锁内存；和 `ram` 性能无差异 |
| `--spec` / `--spec-min-p` / `--suffix-draft` / `--mtp-window` | `4` / `0.5` / `3` / `8192` | MTP 投机解码。只在单请求独占时生效，进入 batch 槽位后不生效 |
| `--conversation-cache-mib` / `-slots` / `-min-tokens` / `-park-gain` / `-min-free-mib` | `16384` / `64` / `4096` / `256` / `12288` | 会话缓存：最多 16 GiB、64 份；≥ 4096 token 的会话才存；比已存副本前进 256 token 才重存；空闲内存低于 12 GiB 时不存 |
| `--prefill-pipe` / `--prompt-cache-every` / `--short-read` | `1` / `16384` / `256` | 沿用测试机实测配置。逐项含义见[参数详解](docs/参数详解.md)，没收录的以 `strata --help` 为准 |

**环境变量（`env`）**

| 变量 | 值 | 作用 |
|---|---|---|
| `STRATA_RESIDENT_HEADROOM_GIB` | `12` | `--resident-experts` 给系统留的空闲**内存**（GiB）。测试机 A/B 实际用的就是 12 |
| `MALLOC_MMAP_THRESHOLD_` | `16777216` | glibc 分配 ≥ 16 MiB 时直接用 mmap，释放后立刻还给系统 |
| `STRATA_ROUTE_TAIL_SKIP` | `0` | 专家全在显存时不起作用，保留无害 |
| `STRATA_PF_FUSED` / `STRATA_SLOT_COPY_DIRECT` / `STRATA_SLOT_COPY_BATCHSYNC` | `1` | 预填融合、预填结果复制进槽位的方式。沿用测试机配置，单项收益没有单独测过 |

同一套配置的 0.1.45 目录布局版本见 [`deploy/strata-iq3_xxs.0.1.45-8slot-split26.json`](deploy/strata-iq3_xxs.0.1.45-8slot-split26.json)，两者差异见 [deploy/README](deploy/README.md#0145-与-0220-版-8-槽配置的差异)。

### 0.2.20 压测结果

用上面这份配置（引擎 0.1.66，8 槽层拆分）测的。每路约 32K 上下文，生成 256 token。"首轮"是新会话第一次提问，要预填完整 prompt；"续聊"是同一会话接着问，前缀命中会话缓存。

| 并发 | 阶段 | TTFT P95 | 单路解码中位数 | 整组解码吞吐 |
|---|---|---|---|---|
| 2 | 首轮 | 12.39 秒 | 50.2 tok/s | 53.0 tok/s |
| 2 | 续聊 | **1.19 秒** | **68.1 tok/s** | 123.0 tok/s |
| 4 | 首轮 | 25.22 秒 | 18.6 tok/s | 43.1 tok/s |
| 4 | 续聊 | **2.47 秒** | 42.9 tok/s | 148.8 tok/s |
| 8 | 首轮 | 53.47 秒 | 8.7 tok/s | 39.7 tok/s |
| 8 | 续聊 | **4.96 秒** | 25.8 tok/s | 170.6 tok/s |

- **首轮 TTFT 随并发线性增长**，大约是并发数 × 6.2 ~ 6.7 秒。原因是新 prompt 的预填串行接纳，排在后面的请求要等前面的预填完，见[升级实测 §7](docs/Strata-0.2.20升级实测-2026-11-23.md#7-为什么并发时首轮-ttft-下不来)。并发 ≥ 2 时首轮达不到 ≤ 8 秒的目标。
- **续聊 TTFT 在 5 秒以内**，8 路也只要 4.96 秒，说明会话缓存起作用了。
- 单路解码只有 2 路续聊（68.1 tok/s）达到 ≥ 60 tok/s。并发越高单路越慢，整组吞吐越高：续聊从 123.0 涨到 170.6 tok/s。

---

## 我想……

| 我想 | 看这里 |
|---|---|
| 在离线机器部署 Strata 0.2.20 | **[离线迁移部署](docs/离线迁移部署-0.2.20.md)** · [新版 JSON 模板](deploy/strata-iq3_xxs.0.2.20.example.json) |
| 看 0.2.20 升级与性能实测 | [双 A100 SXM4 升级实测](docs/Strata-0.2.20升级实测-2026-11-23.md) |
| 看 0.1.45 的 A100 PCIe 调优 | [2026-11-14 实测报告](docs/最新压测结果-2026-11-14.md) · [原始证据](benchmarks/2026-11-14-a100-pcie40g/README.md) |
| 复现 0.1.45 历史部署 | [快速开始](#快速开始) · [历史部署文档](docs/部署文档.md) |
| 知道某个参数是什么意思、在本机有没有用 | [参数详解](docs/参数详解.md) |
| 直接拿配置文件 | [`deploy/`](deploy/README.md) |
| 看性能数据、复现压测 | [压测文档](docs/压测文档.md)，14 个版本的总表在[部署文档 §12](docs/部署文档.md#12-参数演化与实测汇总历史存档) |
| 值班、排障 | [运维卡片](docs/运维卡片.md) |
| 迁到麒麟 V10 等内网机器 | [0.2.20 离线迁移](docs/离线迁移部署-0.2.20.md) · [目标机系统差异](docs/目标机迁移清单.md) |
| 了解脚本怎么用 | [`scripts/README.md`](scripts/README.md) |
| 部署 IQ3_S、Coder 或 vLLM 27B | [待实施-其他模型](待实施-其他模型/README.md)（**都未部署、未验证**） |

---

## 历史 SXM4 结果（2026-11-02）

| 项 | 实测 |
|---|---|
| 部署耗时 | 传输完成到服务就绪 **8 分钟**；`setup.sh` 断网 49 秒，零网络请求 |
| 显存 | 层拆分 CUDA0 跑第 0–23 层、CUDA1 跑第 24–47 层；**全部 24576 个专家都在显存** |
| 单请求解码 | **105–111 tok/s**（TPOT 约 9 ms） |
| 长提示并发（in=2000，4 槽，并发 8） | 聚合 **59.5 tok/s**，TPOT 45.9 ms |
| 短提示并发（in≈800，8 槽，并发 8） | 聚合 **89.3 tok/s**，TPOT 71.4 ms |
| 长上下文 | 200K 提示 TTFT 39 秒，预填约 5100 tok/s；超长请求返回 400，从不截断 |
| 停启 | `stop` 13 秒释放显存，`up -d` 65 秒 healthy |

**结论**：没有免费扩容。并发越高，单个请求越慢；4 槽在长提示下全面最优，8 槽只在短提示、高并发时聚合更高。

---

## 历史 SXM4 推荐配置

2026-11-14 PCIe 机器按 32K TTFT 目标选中的配置另存为 [`deploy/strata-iq3_xxs.a100-pcie40g-20261114.measured.json`](deploy/strata-iq3_xxs.a100-pcie40g-20261114.measured.json)。新旧部署路径与实测口径分别见[最新报告](docs/最新压测结果-2026-11-14.md)。以下两份仍对应旧 SXM4 环境。

| 场景 | 文件 | 对应实测版本 |
|---|---|---|
| 长提示 / 文档分析（**默认**） | [`deploy/strata-iq3_xxs.recommended.json`](deploy/strata-iq3_xxs.recommended.json) | v6，4 槽 |
| 短提示 / 高并发问答 | [`deploy/strata-iq3_xxs.recommended-8slot.json`](deploy/strata-iq3_xxs.recommended-8slot.json) | v5，8 槽 |

两份只差 `parallel`、`--batch`、`--conversation-cache-slots` 三处。

核心取舍：

| 参数 | 取值 | 为什么 |
|---|---|---|
| `--kv-resident` | 32768 | **必留**。去掉后显存被推到 99%，并发 8 吞吐崩 35% |
| `--ple-io` | `mmap` | 和 `ram` 性能相同，但不会锁死 26.8 GiB 内存 |
| `--resident-experts` | 开 | 引擎内存占用 61.7 → 39.3 GiB，显存不变 |
| `--batch-mtp` | 不加 | 双卡层拆分下会被引擎关掉；强制串行实测慢 16–20% |

> **ESP（实验性速度投影）可选，默认关闭。** 向量照常加载，但请求默认不用它，输出和原模型逐 token 一致。需要时可以按单个请求或在 Web 聊天页按对话打开。注意它**不是提速功能**：官方说明它是**拒答方向投影**，开启后模型拒答大幅减少，等于去掉一层安全行为，每 token 还会慢 0.2–0.4%。上面的 v6/v5 数据是在 ESP 开启时测的。详见[参数详解 §2.7](docs/参数详解.md#27-esp-控制向量先读这一节)。

---

## 快速开始

以下命令用于复现 **Strata 0.1.45** 的历史部署。新版的镜像、程序包和启动路径见 [Strata 0.2.20 离线迁移部署](docs/离线迁移部署-0.2.20.md)。

**前置条件**：2 × A100（sm80）、驱动 ≥ 525、docker + nvidia runtime、compose v2 二进制（离线机要提前放好）、内存 ≥ 94 GB、`/data` ≥ 400 GB。

```bash
# 1. 校验离线包（约 1 分钟）
cd /data && sha256sum -c SHA256SUMS-tars.txt

# 2. 解包、导入镜像
B=/data/qwen-strata
mkdir -p $B/Strata-data/models/IQ3_XXS
tar -xf strata-src.tar -C $B && tar -xf tools.tar -C $B
tar -xf data-packs.tar -C $B/Strata-data && tar -xf data-mtp.tar -C $B/Strata-data
tar -xf Qwen3.8-*-00002-of-00002.tar -C $B/Strata-data/models/IQ3_XXS
tar -xf gguf_done.tar -C $B/Strata-data/models/IQ3_XXS
docker load -i strata-qwen38-cuda12-1.0.tar

# 3. 生成 API Key（存文件，不进命令行和日志）
install -d -m 700 /etc/strata
openssl rand -hex 24 > /etc/strata/api_key && chmod 600 /etc/strata/api_key

# 4. 断网跑 setup，生成启动脚本和基础配置
#    脚本里的 BASE / 镜像名按实际改；不要加 --calibrate（见下方"踩坑"第 4 条）
bash scripts/setup_offline.sh

# 5. 换成推荐配置并填入 Key
cp deploy/strata-iq3_xxs.recommended.json $B/Strata/strata-iq3_xxs.json
python3 - <<'EOF'
import json; p = '/data/qwen-strata/Strata/strata-iq3_xxs.json'
c = json.load(open(p)); c['api_key'] = open('/etc/strata/api_key').read().strip()
json.dump(c, open(p, 'w'), ensure_ascii=False, indent=2)
EOF
chmod 600 $B/Strata/strata-iq3_xxs.json

# 6. 用 compose 启动（约 65 秒到 healthy）
mkdir -p /data/compose/strata
cp deploy/docker-compose.yml /data/compose/strata/
cp deploy/.env.example /data/compose/strata/.env
cd /data/compose/strata && docker-compose up -d && docker-compose ps

# 7. 验收
bash scripts/accept.sh
```

**验收标准**：
- `/health` 返回 `loaded: true`；
- 不带 Key 访问返回 401，带 Key 返回 200；
- 引擎日志里有 `100% of the experts resident`。

分阶段的门禁和失败退路见[部署文档](docs/部署文档.md)。

---

## 访问方式

以下公网端口映射来自历史 SXM4 测试环境。新版部署的宿主机端口默认为 `8800`，公网端口以平台的转发表为准。[新版启动命令](docs/离线迁移部署-0.2.20.md#6-启动)

```
公网 13270  →  宿主机 8800  →  容器 8080
 平台转发       compose 发布      server 监听 0.0.0.0:8080
```

| 用途 | 地址 |
|---|---|
| Web 聊天页 | `http://<公网IP>:13270/` |
| OpenAI 兼容 | `http://<公网IP>:13270/v1/chat/completions` |
| Anthropic 兼容 | `http://<公网IP>:13270/v1/messages` |
| 健康检查 | `http://<公网IP>:13270/health` |

请求头都要带 `Authorization: Bearer <Key>`，`model` 字段随便填。`/v1` 只是 API 前缀，浏览器直接打开会 404，网页在 `/`。

平台只转发 `13270–13275 → 8800–8805`，**宿主机发布端口必须是这 6 个之一**，否则公网不通。仓库里的 `<公网IP>` 等都是占位符，不记录真实地址。

---

## 踩坑

1. **不要对运行中的容器 `docker rm -f`。** 引擎占着两张卡的 CUDA 上下文，强杀后进程卡在不可中断状态，容器停在中间态（`is zombie` / `did not receive an exit event`）。`init: true` 也解决不了。正确做法：`docker-compose stop` → `down` → `up -d`。
2. **日志里的 `127.0.0.1:8080` 和 `172.x.x.x:8080` 不是访问地址**，只能走上面那条端口链。
3. **发布端口不在平台转发列表里**时，本机一切正常，公网永远不通。
4. **离线机上不要跑 `setup.sh --calibrate`。** 它会删掉 `.venv` 再联网重装，离线装不回来。`/data/strata-src.tar` 是唯一一份完整 venv 的副本，不能删。
5. **压测别用 `max_tokens=100` 又开着思考。** 思考预算是 4096，100 个 token 全被思考占满，回答是空的。压测时在请求里带 `reasoning_effort: "none"`。

---

## 历史 SXM4 测试环境（Strata 0.1.45）

| 项 | 值 |
|---|---|
| 平台 | KVM 虚机（PCI 直通），CentOS 7.9 / 内核 3.10 |
| GPU | 2 × A100-SXM4-40GB（sm80，NVLink 不可用，卡间走 PCIe） |
| 驱动 / 引擎 | 550.78 / CUDA 12.4；Strata 0.1.45（`engine-cuda12`） |
| CPU / 内存 | 32 vCPU Xeon 8368Q / 94 GiB |
| 磁盘 | `/data` 1 TB ext4，约 1.4 GB/s |
| 容器 | Docker 20.10.17 + nvidia runtime，compose v2.29.7 |

---

## 仓库结构

```
├── README.md                   本文件
├── 整理说明.md                  2026-11-03 整理改了什么、更正了哪些说法
├── deploy/                     0.2.20 JSON 模板、0.1.45 历史配置和 Compose 示例
├── docs/                       IQ3_XXS 文档（索引见 docs/README.md）
│   ├── 参数详解.md              每个参数：含义、本机值、是否生效、来源
│   ├── 离线迁移部署-0.2.20.md    官方程序包、镜像、模型数据、驱动自检与验收
│   ├── Strata-0.2.20升级实测-2026-11-23.md  双 A100 上的升级记录
│   ├── 部署文档.md              完整部署流程；§12 是 14 个版本的实测汇总
│   ├── 压测文档.md              方法学、全部实测、缺陷、执行手册、实验计划
│   ├── 运维卡片.md              单页速查
│   ├── 目标机迁移清单.md         换机计划（未执行）
│   ├── 执行时间线.md            逐阶段原始记录
│   ├── 知识库摘要.md            参考资料
│   └── 归档/                   已被取代的早期文档
├── scripts/                    部署、验收、压测、运维脚本（说明见 scripts/README.md）
├── tools/                      tar_peek.py（读 tar 头）、rexec.py（远程批量执行）
└── 待实施-其他模型/              ⚠️ 未部署、未验证，和上面的内容隔离
    ├── IQ3_S.md                已下载，缺 pack
    ├── Coder-IQ1_M.md          已下载，缺 pack
    └── vLLM-Qwen3.8-27B.md     步骤清单，一条命令都没执行
```

**仓库不含**：离线包和模型权重（约 137 GB，走对象存储或内网分发）；任何密钥、SSH 凭据、云账号（配置里的 `api_key` 都是占位符）。

---

## 许可与来源

Strata 引擎（MIT）与 Qwen3.8-Flash-Next 权重（Qwen Community License 1.0）分别遵循各自的上游许可。本仓库只含部署实践与脚本。参数解释引用了 [Strata 官方仓库](https://github.com/Niko1221/Strata)的文档与源码，具体出处见[参数详解 §10](docs/参数详解.md#10-来源)。

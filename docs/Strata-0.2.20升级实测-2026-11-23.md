# Strata 0.1.45 → 0.2.20 升级实测（2026-11-23）

> **状态：已在测试机执行并实测。** 本文所有数字来自 2026-11-23 23:52 ~ 11-24 00:05（机器本地时间）的实跑日志，原始结果在测试机 `/data/Strata-0.2.20/ab-runs/` 下。
> 机器：2 × NVIDIA A100-SXM4-40GB（`nvidia-smi` 报告），驱动 **550.78**（CUDA 12.4），94 GiB 内存。
> 模型：Qwen3.8-Flash-Next GSQ-RCO IQ3_XXS，配置为 8 槽层拆分（`--layer-split 26`、`--batch 8`）。
> 本文取代 [`../待实施-其他模型/引擎升级-0.1.45到0.2.10.md`](../待实施-其他模型/引擎升级-0.1.45到0.2.10.md)（那份按自编译路线写，未执行）。

---

## 0. 结论先行

| 项 | 0.1.45（armA） | 0.2.20（armC） | 说明 |
|---|---|---|---|
| 单次 32K 预填 | 5.97 ~ 6.01 s（5290 ~ 5330 tok/s） | 5.24 ~ 5.43 s（5860 ~ 6070 tok/s） | **快约 10%** |
| 单路 32K 首轮 TTFT | 6.01 / 6.06 s | 5.28 / 5.44 s | 跟随预填 |
| 4 路并发 32K，最后一个请求 TTFT | 24.98 s | 22.41 s | **结构没变**：prompt 仍串行接纳，TTFT ≈ 排队序号 × 单次预填 |
| 单路解码（短提示，512 token） | 约 105 ~ 111 tok/s（历史值） | 112.8 ~ 113.0 tok/s | 达标（≥ 60） |
| 4 路解码，每路 | — | 58.5 tok/s（聚合 226.5） | 略低于 60 |
| 8 路解码，每路 | — | 38.5 tok/s（聚合 293.6） | |
| 质量 | — | 6 题中 5 题通过；32K 大海捞针通过 | 未通过的那题是检查条件写错，见 §6.3 |

- **升级可以用，值得保留**：官方预编译包免编译，在 550 驱动上能跑，预填快约 10%，解码与质量正常。
- **它没有解决"并发时首轮 TTFT 长"的问题。** 4 路 32K 同时到达时，第 4 个请求要等前 3 个预填完，TTFT 22 秒，离 ≤ 8 秒的目标还远。原因和 0.1.45 相同，见 §7。
- `STRATA_NV_CHUNK=0` 对层拆分路径**无效**（§6.2）。

---

## 1. 用的是哪个包

官方 Release：<https://github.com/Niko1221/Strata/releases/tag/v0.2.20>（发布于 2026-11-22T22:51:04Z，MIT 许可）。

0.2.20 是桌面应用的版本号，Linux 服务端用的是其中两个组件，版本都是 **0.1.66**：

| 文件 | 字节数 | sha256 |
|---|---|---|
| `strata-control-0.1.66-linux-x86_64.tar.gz` | 94663788 | `5bd662d293ab4dc8b71156daafbb42995bddbb765dbeac48c5fd74165dfb2d0d` |
| `strata-engine-0.1.66-linux-x86_64-cuda-cuda12.tar.gz` | 782739940 | `74980aebedc70fb2cfcd96b3c15874cb3e7e517700ecdf8ed811247a9a577f30` |

- **control**：自带 Python 3.12.15 和全部依赖（`BUNDLE.json` 里 `acquires_at_runtime: false`），离线可用，不需要镜像里的 venv。包含 `serve/server.py`、`strata_control/`、`strata_cli/`、`data/expert-profile.bin` 等。
- **engine（cuda12）**：`strata` 引擎二进制 + `strata-vision` + 自带的 `libcudart.so.12`、`libcublas.so.12`、`libcublasLt.so.12`。`BUILD.json`：
  ```
  {"version": "0.1.66", "archs": "60;61;70;75;80;86;120;89", "cuda": "12.9", "portable": true}
  ```
  **包含 sm_80（A100）**，不用自己编译。旧方案里"sm_80 要自编"指的是全卡切分引擎，和这里的层拆分引擎无关。

这两个文件也作为附件放在本仓库的 GitHub Release `strata-0.2.20-a100` 里，sha256 与官方一致。

---

## 2. 驱动兼容性：550 驱动跑 CUDA 12.9 运行库

`engine-component.json` 写的是 `"min_driver": {"nvidia": "575.51"}`，本机驱动是 550.78（CUDA 12.4）。**实测能跑**，依靠的是 CUDA 12.x 的小版本兼容（同一大版本内，新运行库可以在旧驱动上运行，前提是不调用新驱动才有的 API）。

上线前先用 [`scripts/cuda_probe_0220.py`](../scripts/cuda_probe_0220.py) 自检，它用 ctypes 直接加载包里的 cudart/cublas，打印运行库与驱动版本，在每张卡上建上下文并跑一次 SGEMM：

```bash
cp scripts/cuda_probe_0220.py /data/Strata-0.2.20/   # 先把脚本放进挂载目录
docker run --rm --gpus '"device=0,1"' -v /data/Strata-0.2.20:/data/Strata-0.2.20 \
  --entrypoint /opt/nvidia/nvidia_entrypoint.sh strata-qwen38:0.1.45-cuda12 \
  /data/Strata-0.2.20/python/bin/python3 /data/Strata-0.2.20/cuda_probe_0220.py
```

最后一行是 `CUDA-PROBE-OK` 才继续。任何一步 rc 不为 0 就停下：说明这个驱动跑不了 12.9 运行库，需要先升级驱动（官方标注的最低版本是 575.51），不要硬上。

> 注意：小版本兼容不是官方对这个组合的承诺。驱动 535（目标机）**没有测过**。

---

## 3. 安装

两个 tar 包的文件都在包的根层（没有顶层目录），所以要分别解到不同位置：

```bash
NEW=/data/Strata-0.2.20
mkdir -p $NEW/dl $NEW/engine-cuda12
# 上传两个包到 $NEW/dl/ 后先校验
cd $NEW/dl && sha256sum strata-control-0.1.66-linux-x86_64.tar.gz strata-engine-0.1.66-linux-x86_64-cuda-cuda12.tar.gz
# 对照 §1 的 sha256

tar xzf $NEW/dl/strata-control-0.1.66-linux-x86_64.tar.gz -C $NEW
tar xzf $NEW/dl/strata-engine-0.1.66-linux-x86_64-cuda-cuda12.tar.gz -C $NEW/engine-cuda12
cat $NEW/VERSION                     # 0.1.66
cat $NEW/engine-cuda12/BUILD.json    # archs 里有 80
```

解压后约 2.4 GB。旧目录 `/data/Strata` 和模型目录 `/data/Strata-data` 都不动；新容器只读挂载 `/data/Strata-data`。

---

## 4. 配置：只改 5 处

用 [`scripts/mkcfg_0220.py`](../scripts/mkcfg_0220.py) 从旧配置 `/data/Strata/strata-iq3_xxs.json` 生成新配置（目标已存在时拒绝覆盖，会打印差异）。再用 `start_0220.sh` 里的 sed 修正 expert-profile 路径。合起来改动是：

| 字段 | 旧 | 新 |
|---|---|---|
| `exe` | `/data/Strata/engine-cuda12/strata` | `/data/Strata-0.2.20/engine-cuda12/strata` |
| `cwd` | `/data/Strata` | `/data/Strata-0.2.20` |
| `log` | `/data/Strata/strata-iq3_xxs.log` | `/data/Strata-0.2.20/strata-iq3_xxs.log` |
| `lib_dirs` | 旧引擎目录 | `["/data/Strata-0.2.20/engine-cuda12"]`（用包里自带的 cuBLAS/cudart） |
| `args` 里的 `--expert-profile` | `/data/Strata/data/expert-profile.bin` | `/data/Strata-0.2.20/data/expert-profile.bin`（新旧文件 sha256 相同；新容器不挂 `/data/Strata`，所以必须改） |

**引擎参数、env、采样、槽位一律不变**，保证 A/B 只差引擎版本。完整配置见 [`deploy/strata-iq3_xxs.0.2.20.example.json`](../deploy/strata-iq3_xxs.0.2.20.example.json)（`api_key` 是占位符）。

新 `server.py` 的启动参数与旧版兼容（`--engine` / `--config` / `--host` / `--port`），`/health` 里仍有 `loaded` 字段，健康检查不用改。

---

## 5. 启动新容器

[`scripts/start_0220.sh`](../scripts/start_0220.sh) 做四件事：修正 expert-profile 路径（先备份成 `.orig`）、`docker inspect strata` 存档旧容器配置、`docker stop -t 120 strata`（**只停不删**，便于回滚）、起新容器：

```bash
docker run -d --name strata-0220 \
  --gpus '"device=0,1"' -p 8800:8080 \
  --shm-size 2g --ulimit memlock=-1:-1 --restart no \
  -v /data/Strata-data:/data/Strata-data:ro \
  -v /data/Strata-0.2.20:/data/Strata-0.2.20 \
  --health-cmd "$HC" --health-interval 20s --health-timeout 8s --health-start-period 300s --health-retries 3 \
  --entrypoint /opt/nvidia/nvidia_entrypoint.sh \
  strata-qwen38:0.1.45-cuda12 \
  /data/Strata-0.2.20/python/bin/python3 /data/Strata-0.2.20/serve/server.py \
    --engine strata --config /data/Strata-0.2.20/strata-iq3_xxs.json --host 0.0.0.0 --port 8080
```

- 镜像沿用 `strata-qwen38:0.1.45-cuda12`，只用它的 NVIDIA 运行时入口；Python 用 control 包自带的那份。
- `--restart no` 是 A/B 期间的选择。确认长期使用后改成 `unless-stopped`，或者并入 compose。
- 重启到 healthy 约 **40 秒**。

### 5.1 启动日志验收点

在 `/data/Strata-0.2.20/strata-iq3_xxs.log` 里逐条确认（以下是本机实际输出）：

| 看什么 | 本机实际 |
|---|---|
| 引擎版本 | `session is up (engine 0.1.66)` |
| 层拆分 | `layer split across 2 GPUs: CUDA0, then CUDA1 (split 26)` |
| 卡型号 | `GPU 0: NVIDIA A100-SXM4-40GB, compute capability 8.0` |
| 槽位分组 | `--batch-groups auto: 2 groups of 4 slots` |
| 专家全在显存 | `every expert is in the GPU caches (24576 of 24576)`；CUDA0 `13312 slots, 19.29 GiB`，CUDA1 `11264 slots (20.68 GiB)` |
| profile 路径正确 | `profile /data/Strata-0.2.20/data/expert-profile.bin: 24576 ranked pairs` |
| KV | `32768 of 229376 cells per QSA layer in VRAM` |
| 预填块 | `prompt chunk auto: 8192 tokens, a 96-slot ring`（注意不是参数里的 12288，见 §6.2） |
| PCIe 探测 | 两卡都是 25.x GB/s |

---

## 6. 实测

### 6.1 A/B：32K 预填与首轮 TTFT

脚本 [`scripts/ab_0220.sh`](../scripts/ab_0220.sh)，与 0.1.45 的 armA 用**同一份** bench.py（只改了读 api_key 的路径），每组之间重启容器。脚本有 `trap restore`，结束或中断都会自动还原配置并重启。

口径：约 31823 token 的提示，`max_tokens` 很小，只看 TTFT 和引擎日志里的预填时间。armC/armD 额外打开 `STRATA_TRACE` / `STRATA_PREFILL_TIMING` / `STRATA_SPLIT_TIMING` 计时（armA 也开了，口径一致）。

| 组 | 单路 TTFT（两次） | 4 路 TTFT（按完成顺序） | 引擎日志单次 32K 预填 |
|---|---|---|---|
| armA：0.1.45 | 6.013 / 6.057 s | 6.71 / 12.75 / 18.87 / 24.98 s | 5968 ~ 6014 ms（5292 ~ 5332 tok/s） |
| armC：0.2.20 | 5.279 / 5.443 s | 6.02 / 11.46 / 16.93 / 22.41 s | 5240 ~ 5413 ms（5879 ~ 6074 tok/s） |
| armD：0.2.20 + `STRATA_NV_CHUNK=0` | 5.303 / 5.439 s | 6.08 / 11.54 / 17.01 / 22.50 s | 5263 ~ 5427 ms（5864 ~ 6047 tok/s） |

4 路的 TTFT 间隔约 5.4 秒，正好是一次 32K 预填的时间：**prompt 是一个接一个预填的**。

### 6.2 `STRATA_NV_CHUNK=0` 无效

armD 本想让 prompt chunk 退回 0.2.11 之前的行为（按 `--prefill auto:12288`）。结果 armD 日志仍是 `prompt chunk auto: 8192 tokens, a 96-slot ring`，数字与 armC 在误差内。

只读调查（`supp_0220.sh` 前半段）：

- 引擎二进制里与 chunk 相关的环境变量名有 `STRATA_NV_CHUNK`、`STRATA_SPLIT_CHUNK16K`、`STRATA_GDN_CHUNK*`、`STRATA_BATCH_YIELD_CHUNKS` 等；
- control 侧 Python 不引用 `NV_CHUNK` / `SPLIT_CHUNK16K`；
- 运行中引擎进程的 env 与配置一致，`--prefill auto:12288` 确实传进去了。

推断：层拆分路径的 serve chunk 不由 `--prefill` 和 `NV_CHUNK` 决定。下一个候选是 `STRATA_SPLIT_CHUNK16K=1`，**未测**。

### 6.3 补测：解码与质量（只读，不改配置、不重启）

脚本 [`scripts/supp_0220.sh`](../scripts/supp_0220.sh)，调用 [`decode_bench_0220.py`](../scripts/decode_bench_0220.py)（流式、`temperature 0`、`include_usage`，中文长文写作提示，`max_tokens 512`）和 [`quality_0220.py`](../scripts/quality_0220.py)。

| 并发 | 每路解码 tok/s（均值） | 聚合 tok/s（含预填） | TTFT 范围 |
|---|---|---|---|
| 1（三次） | 112.8 / 113.0 / 113.0 | 111.7 ~ 111.9 | 0.053 s |
| 2 | 82.9 | 161.7 | 0.055 ~ 0.264 s |
| 4 | 58.5 | 226.5 | 0.081 ~ 0.531 s |
| 8 | 38.5 | 293.6 | 0.059 ~ 1.336 s |

- 单路时 MTP 草稿生效，日志 `drafts accepted 239 of 412`；进入 batch 槽位后草稿不生效，所以并发时每路速度明显下降。
- 8 路时 `nvidia-smi dmon` 显示 GPU0 SM 约 98%、GPU1 约 93%。
- 这一组是**短提示**。32K 上下文下的解码速度**还没测**。

质量（`temperature 0` 固定题）：

| 题 | 结果 |
|---|---|
| math（37 × 43） | 通过 |
| code（is_palindrome） | 通过 |
| explain（KV cache 三句话） | 通过 |
| translate | 译文 "We will discuss the project progress in the conference room at 3:00 PM this afternoon." 正确，但脚本要求出现 `three`，所以判为未通过。**是检查条件写错，不是模型问题** |
| facts（四个直辖市） | 通过 |
| needle32k（31851 token 里找密码 73914） | 通过，5.36 s，预填 6036 tok/s |

没有乱码、截断或重复（`uniq10` 全部 ≥ 0.86）。

---

## 7. 为什么并发时首轮 TTFT 下不来

- 层拆分 + `--batch 8` 是 2 组 × 4 槽的流水线。**新 prompt 的预填是串行接纳的**：一个 32K 预填完、复制进槽位，下一个才开始。
- 所以 N 个 32K 请求同时到达，第 N 个的 TTFT ≈ N × 单次预填（本机约 5.4 秒）。4 路时约 22 秒。
- 0.2.20 把单次预填缩短了约 10%，但没有改变串行结构。要满足"并发下首轮 TTFT ≤ 8 秒"，同时到达的 32K 请求不能超过 1 个，或者需要真正并行预填的方案。

后续可以测的方向（都**未测**）：`STRATA_SPLIT_CHUNK16K=1`；32K 上下文下的解码速度。

---

## 8. 回滚

旧容器 `strata` 只是停止，没删；旧目录 `/data/Strata` 没动。回滚：

```bash
docker stop -t 120 strata-0220      # 先释放 8800 端口和两张卡
docker start strata
docker inspect -f '{{.State.Health.Status}}' strata   # 等到 healthy
```

旧容器的完整配置存档在 `/data/Strata-0.2.20/strata-old-inspect.json`。新配置的备份：`strata-iq3_xxs.json.orig`（改 expert-profile 之前）和 `strata-iq3_xxs.json.bak-20261123-235232`（A/B 之前）。

**不要用 `docker rm -f`**。

---

## 9. 脚本清单

都在 [`scripts/`](../scripts/README.md)，平铺，后缀 `_0220`：

| 脚本 | 在哪跑 | 做什么 | 只读？ |
|---|---|---|---|
| `cuda_probe_0220.py` | 容器内（用包里自带的 python） | 驱动/运行库版本、每卡建上下文、SGEMM | 是 |
| `mkcfg_0220.py` | 宿主机 | 从旧配置生成新配置，只改 exe/cwd/log/lib_dirs，打印差异；目标已存在时拒绝覆盖 | 否（写新配置） |
| `start_0220.sh` | 宿主机 | 修正 expert-profile 路径，存档并停旧容器，起 `strata-0220` | 否（停旧容器） |
| `ab_0220.sh` | 宿主机 | armC/armD A/B，`trap` 自动还原配置 | 否（重启容器） |
| `supp_0220.sh` | 宿主机 | NV_CHUNK 只读调查 + 解码并发梯度 + 质量 | 是（会发请求） |
| `decode_bench_0220.py` | 容器内 | `N MAX_TOKENS TAG OUTDIR`，流式并发解码计时 | 是 |
| `quality_0220.py` | 容器内 | `OUTDIR TAG`，6 道固定题 + 32K 大海捞针 | 是 |

`ab_0220.sh` 依赖 0.1.45 那一轮的 `bench.py`（`/data/Strata/ab-runs/20261123-232328/bench.py`），没有放进仓库。所有脚本从配置 JSON 读 api_key，不在命令行或日志里出现。

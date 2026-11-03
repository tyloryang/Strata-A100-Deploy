# Qwen3.8-Flash-Next 本地部署文档（vLLM + W4A16-FP8PLE）

2026-11-03 · **状态：未验证**。文中带"估算"的数字均按官方 RTX 3090 实测数据推算，未在本机跑过。

## 概览

本机用单卡 runtime `qwen38-flash-next-3090` 跑 `albucino/Qwen3.8-Flash-Next-W4A16-FP8PLE`，需要把默认约 23.4 GB 的显存占用压到 20 GB 以内。该 runtime 只在 RTX 3090 上验证过，3080 20GB 同为 SM86 架构，属于社区实验配置。

| 项目 | 本机 | 官方测试机（单卡） | 影响 |
| --- | --- | --- | --- |
| GPU | 魔改 RTX 3080 20GB | RTX 3090 24GB | 需降低热专家数和上下文 |
| CPU | Xeon E5-2678 v3，12 核 Haswell，支持 AVX2 | 32 核新平台 | 冷专家计算慢，解码受限 |
| 内存 | 16GB×8 = 128GB，DDR4 四通道 | 64GB | 全部冷专家可常驻内存，这是优势 |
| PCIe | 3.0 x16（X99） | 4.0 | prefill 传输带宽减半 |

预期性能（估算，未实测）：解码约 15–25 tok/s，131K 提示 prefill 约 800–1200 tok/s，单请求排队服务，最大上下文 64K。

工作原理：GPU 存放注意力、稠密层、每层最常用的若干专家和 INT8 KV cache；其余专家常驻内存，解码时由 CPU 计算；prefill 时所有专家流式经过 GPU。51.2 GB 的 FP8 PLE 表直接从 NVMe 文件读取。

## 前置准备

软件要求：Linux（不支持 Windows，WSL2 未测试）、NVIDIA 驱动 580 或更新、Docker、NVIDIA Container Toolkit。磁盘需要一块 NVMe，剩余空间约 130 GB，服务过程中也会持续读取 checkpoint。

1. 安装驱动并确认版本：

```bash
nvidia-smi   # Driver Version 需 >= 580，确认显存显示为 20480MiB
```

2. 安装 Docker 和 NVIDIA Container Toolkit，然后验证容器能看到 GPU：

```bash
curl -fsSL https://get.docker.com | sh
# 按 NVIDIA 官方文档添加 nvidia-container-toolkit 源后：
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi
```

3. 硬件自检（结果决定后面的参数）：

```bash
lscpu | grep -E "Model name|NUMA|Flags" | grep -oE "Model name.*|NUMA.*|avx2|fma|f16c" | sort -u
sudo dmidecode -t memory | grep -i "configured memory speed" | sort | uniq -c
lspci -vv | grep -A20 VGA | grep -i "LnkSta:"     # 应为 Speed 8GT/s, Width x16
nvme list                                          # 确认有 NVMe 盘
```

- CPU 必须同时有 avx2、fma、f16c，E5-2678 v3 满足。
- 如果 NUMA 节点数为 2（双路主板），记下 GPU 所在节点，"调参与排错"一节会用到。
- 如果显卡链路不是 x16，先换插槽，否则 prefill 会更慢。

4. 启动前整理内存碎片，让专家区拿到透明大页（每次长时间开机后都建议做一次）：

```bash
cat /sys/kernel/mm/transparent_hugepage/enabled   # 应包含 [madvise] 或 [always]
sync; echo 1 | sudo tee /proc/sys/vm/compact_memory
```

5. 如果 3080 同时接着显示器，建议关掉桌面或改用核显输出。桌面通常会占用 0.3–1.5 GB 显存，而 20 GB 的预算本来就很紧。

## 下载模型

checkpoint 约 129 GB，包含主模型和 INT4 MTP 草稿模型，必须放在 NVMe 上。下载时要固定 revision，与 runtime 验证过的版本保持一致。

```bash
pip install -U huggingface_hub
export HF_ENDPOINT=https://hf-mirror.com      # 国内镜像，能直连 HF 可省略
export HF_HUB_ENABLE_HF_TRANSFER=1             # 可选，需 pip install hf_transfer

hf download albucino/Qwen3.8-Flash-Next-W4A16-FP8PLE \
  --revision ef554143369a706525336f6b42a09094835dc077 \
  --local-dir /models/qwen38-flash-next
```

下载完成后检查：

```bash
du -sh /models/qwen38-flash-next                 # 约 120 GiB
ls /models/qwen38-flash-next/runtime/mtp-int4-g32  # MTP 草稿必须存在
```

镜像站中断后重新执行同一条命令即可续传。如果镜像没有这个 revision，去掉 `HF_ENDPOINT` 改用代理直连。

## 获取 runtime 并配置 .env

核心思路：把热专家从 32 个降到 4 个、上下文降到 64K，用来抵掉超出的约 4 GB 显存，先保证能启动，再逐步往回加。

```bash
git clone https://github.com/DominikBucko/qwen38-flash-next-3090.git
cd qwen38-flash-next-3090
cp .env.example .env
```

在 `.env` 末尾追加：

```bash
MODEL_DIR=/models/qwen38-flash-next

# --- 显存：压到 20GB 内 ---
QWEN38_HOT_ONLY=4                  # 默认32；每个约116MiB，先保守起步
MAX_MODEL_LEN=65536                # 默认135168
KV_CACHE_MEMORY_BYTES=2300000000   # 约0.75GB节省，够64K
# MAX_NUM_BATCHED_TOKENS 保持默认8192：PCIe 3.0下chunk越小prefill越慢

# --- CPU：E5-2678 v3，12核单L3 ---
QWEN38_CPU_EXPERTS_CPUS=2-11       # 专家池10个物理核，留0-1给服务进程
QWEN38_PLE_THREADS=2               # 默认4，核少时别抢
QWEN38_GPU_SHARE_FRAC=0.3          # 默认0.22；CPU弱，多让GPU分担

# --- 观测 ---
QWEN38_CPU_EXPERTS_STATS=64
```

显存预算估算（按官方 3090 实测拆分推算）：

| 组成 | 默认 3090 配置 | 本机起步配置 |
| --- | --- | --- |
| 注意力、循环层、稠密权重 | 9.8 GB | 9.8 GB |
| 热专家 | 32 个 / 3.9 GB | 4 个 / 约 0.5 GB |
| INT8 KV cache | 3.05 GB（141K token） | 2.3 GB（约 64K token） |
| MTP 草稿、激活、运行开销 | 约 6.6 GB | 约 6.6 GB |
| 峰值合计 | 23.4 GB | 约 19.2 GB |

启动成功后按 4 → 8 → 12 逐步提高 `QWEN38_HOT_ONLY`，峰值接近 19.5 GB 就停。热专家越多，CPU 负担越轻，解码越快。

内存不用改：`MEMORY_LIMIT=auto` 会取 128 GB 减 8 GiB，全部冷专家都能常驻内存。

## 启动与验证

`make serve` 会先运行 `scripts/preflight.sh` 检查 GPU、内存、CPU、驱动和磁盘。首次启动要编译内核，比较慢；之后热启动约 3–4 分钟。服务监听在 `http://127.0.0.1:8000/v1`。

```bash
make build-image     # 或直接用发布镜像，跳过构建：
# IMAGE=ghcr.io/dominikbucko/qwen38-flash-next-3090@sha256:7f176605b59c462af21b1b62fd854f9f3cca96e3d11a295581297483d45490a3 make serve
make serve
```

如果 preflight 因显存不足 24 GB 而拒绝启动，打开 `scripts/preflight.sh` 找到显存检查那一项，放宽或跳过。这是 20 GB 卡预期会遇到的情况。

启动日志里重点看这几行：

- `Expert store: ... huge pages X GiB`：大页数量应接近专家区的大小。
- `GPU KV cache size`：容量要不小于 `MAX_MODEL_LEN` 的 1.05 倍，也就是约 68,800 token。
- `CPU expert pool: N threads on CPUs ...`：确认用上了 2–11 号核。

功能验证与测速：

```bash
python3 scripts/smoke_test.py   # 推理、工具调用、代码三项
make bench                      # 4K / 32K / 131K / 8K 提示测速
# 上下文已改为64K，131K 那项会失败属正常，看其余几项

curl http://127.0.0.1:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "Qwen3.8-Flash-Next",
  "messages": [{"role": "user", "content": "用三句话解释 MoE 模型"}]
}'
```

任何 OpenAI 兼容客户端都可以接入，例如 Cherry Studio、Cline。base URL 填 `http://127.0.0.1:8000/v1`，模型名填 `Qwen3.8-Flash-Next`。tool call 解析器为 `qwen3_coder`，推理内容通过 `reasoning_content` 字段返回。如果要对局域网开放，在 `.env` 里设置 `VLLM_API_KEY`。

## 调参与排错

每次只改一个参数，改完都用 `make bench` 对比。解码调优主要看日志里每 64 步打印一次的 `cpu_moe decode` 行。

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 启动或首个长提示报 CUDA OOM | 显存超出 | 依次尝试：`QWEN38_HOT_ONLY` 再降低；`QWEN38_STREAM_GROUP=40`（默认 80，组越大越占显存）；`MAX_NUM_BATCHED_TOKENS=4096`；把 `MAX_MODEL_LEN` 降到 49152，并设 `KV_CACHE_MEMORY_BYTES=2000000000` |
| 容器在 `Expert store` 阶段被杀 | 内存限制大于实际空闲内存 | 关掉其他程序，或设 `MEMORY_LIMIT=110g` |
| 日志里 `cpu` 时间远大于 `between layers` | CPU 是瓶颈 | `QWEN38_GPU_SHARE_FRAC` 每次加 0.05，最高试到 0.45 |
| `between layers` 时间超过 `cpu` | GPU 和 PCIe 是瓶颈 | `QWEN38_GPU_SHARE_FRAC` 往回调低 |
| `of which tail` 数值很大 | 专家从 NVMe 读取 | 确认 checkpoint 在 NVMe 上，`QWEN38_EXPERT_ARENA_SLOTS` 保持 auto |
| 解码低于 15 tok/s | 内存降频或带宽被占用 | 用 dmidecode 确认频率；在 BIOS 里把内存锁到 2133；关掉其他高负载程序 |
| `Illegal instruction` | CPU 缺 AVX2/FMA/F16C | E5-2678 v3 不会出现；双路洋垃圾主板要检查 BIOS 是否屏蔽了 AVX |
| 新长提示后前 64 步特别慢 | 专家区正在适应 | 属于正常现象 |

双路主板（`lscpu` 显示 2 个 NUMA 节点）：把容器限制在 GPU 所在节点的核上，避免跨节点访问内存。

```bash
nvidia-smi topo -m                 # 看 NUMA Affinity / CPU Affinity 列
lscpu | grep "NUMA node"           # 查看该节点的 CPU 范围
# .env 中：
CPUSET=0-11                          # 替换为 GPU 所在节点的核
```

解码速度上限主要取决于内存带宽。E5-2678 v3 是四通道 DDR4-2133，理论约 68 GB/s。8 根条子是每通道插 2 根，部分主板会因此降到 1866；即便如此也保留 128 GB，因为让全部冷专家常驻内存比多那一点频率更重要。

## 方案二：租用 2× A100 40GB

用双卡 runtime `qwen38-flash-next-2x3090` 的 64 GB 内存 profile。96 GB 内存装不下 128 GB profile（那个 profile 需要约 60 GB 专家加 51.2 GB PLE 表常驻内存）。每卡比 3090 多 16 GB 显存，可以把热专家缓存大幅调高，减少对 CPU 的依赖。

租用前逐项确认：

- [ ] 实例能运行 Docker 和 NVIDIA Container Toolkit。AutoDL 一类容器实例通常不行，需要选裸机或 VM。
- [ ] 有本地 NVMe，剩余空间 ≥ 150 GB。网络盘和共享盘不行，服务过程中要读 checkpoint。
- [ ] 驱动版本 ≥ 580。
- [ ] 确认是 SXM 还是 PCIe 版，以及 `nvidia-smi topo -p2p r` 显示 P2P 是否可用。
- [ ] CPU 至少 16 核，内存是多通道（冷专家仍由 CPU 计算）。

部署步骤：

```bash
hf download albucino/Qwen3.8-Flash-Next-W4A16-FP8PLE \
  --revision ef554143369a706525336f6b42a09094835dc077 --local-dir /models/qwen38-flash-next
git clone https://github.com/DominikBucko/qwen38-flash-next-2x3090.git && cd qwen38-flash-next-2x3090
cp .env.example .env               # 设置 MODEL_DIR
cat configs/2x3090-64gb.env >> .env
make preflight && make serve
```

调优方向：先用默认配置跑通，再逐步调高每卡的热专家数。2x 仓库用的变量名是 `VLLM_WNA16_STATIC_HOT_CACHE_SIZE`，64 GB profile 的具体变量名以 `configs/2x3090-64gb.env` 为准；每个槽位约 116 MiB/GPU。如果 P2P 两个方向都可用，可以试 `DISABLE_CUSTOM_ALL_REDUCE=0`。

风险：维护者只验证过 SM86（RTX 3090），A100 是 SM80，内核能否运行需要实测。建议按小时租，先跑 `make preflight` 和一个短提示，确认没问题再跑长上下文测试。

## 参考链接

- [albucino/Qwen3.8-Flash-Next-W4A16-FP8PLE 模型卡](https://huggingface.co/albucino/Qwen3.8-Flash-Next-W4A16-FP8PLE)
- [qwen38-flash-next-3090 单卡 runtime README](https://github.com/DominikBucko/qwen38-flash-next-3090)
- [单卡调参与排错 tuning.md](https://github.com/DominikBucko/qwen38-flash-next-3090/blob/main/docs/tuning.md)
- [单卡 FAQ](https://github.com/DominikBucko/qwen38-flash-next-3090/blob/main/docs/faq.md)
- [双卡 runtime 硬件说明 hardware.md](https://github.com/DominikBucko/qwen38-flash-next-2x3090/blob/main/docs/hardware.md)
- [原帖：linux.do qwen3.8 flash 本地部署飞起](https://linux.do/t/topic/2920414)

跑完 `make bench` 后，把实测结果补进"概览"一节，再把本文从 `未验证/` 移出。

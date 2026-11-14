# 2026-11-14 双 A100 PCIe 40GB 原始压测证据

结果解读与条件见[最新压测报告](../../docs/最新压测结果-2026-11-14.md)。本目录对应 Strata **0.1.45**，服务模型 `qwen3.8-flash-next-iq3_xxs`。

## 快速对照

| case | 实跑规模 | 实际启动 JSON | 服务 / 引擎 argv 与真实 vLLM argv | 历史 vLLM 命令 | 原始结果 / usage |
|---|---|---|---|---|---|
| general-check-32k-c1 | 32K / c1 / n8 | [JSON](launches/general-check-32k-c1.redacted.json) | [证据](launches/general-check-32k-c1.evidence.json) | [命令](launches/general-check-32k-c1.vllm-command.sh) | [结果](results/general-check-32k-c1.json) / [usage](results/general-check-32k-c1-usage.jsonl) |
| general-check-32k-c4 | 32K / c4 / n4 | [JSON](launches/general-check-32k-c4.redacted.json) | [证据](launches/general-check-32k-c4.evidence.json) | [命令](launches/general-check-32k-c4.vllm-command.sh) | [结果](results/general-check-32k-c4.json) / [usage](results/general-check-32k-c4-usage.jsonl) |
| general-check-64k-c1 | 64K / c1 / n1 | [JSON](launches/general-check-64k-c1.redacted.json) | [证据](launches/general-check-64k-c1.evidence.json) | [命令](launches/general-check-64k-c1.vllm-command.sh) | [结果](results/general-check-64k-c1.json) / [usage](results/general-check-64k-c1-usage.jsonl) |
| general-check-128k-c1 | 128K / c1 / n1 | [JSON](launches/general-check-128k-c1.redacted.json) | [证据](launches/general-check-128k-c1.evidence.json) | [命令](launches/general-check-128k-c1.vllm-command.sh) | [结果](results/general-check-128k-c1.json) / [usage](results/general-check-128k-c1-usage.jsonl) |
| identical-prefix-pair-32k-c1 | 共享前缀 / c1 / n2 | [JSON](launches/identical-prefix-pair-32k-c1.redacted.json) | [证据](launches/identical-prefix-pair-32k-c1.evidence.json) | [命令](launches/identical-prefix-pair-32k-c1.vllm-command.sh) | [结果](results/identical-prefix-pair-32k-c1.json) / [usage](results/identical-prefix-pair-32k-c1-usage.jsonl) |

历史 shell 文件保留实际执行时的端口和结果文件名，直接重放会复用原位置。日常复现请用[四组复现脚本](../../scripts/benchmark_latest_a100.sh)，它生成新目录。API Key 只在运行时从本机私有配置读取，仓库没有有效 Key。

## 文件说明

- [comparison.csv](comparison.csv) / [comparison.json](comparison.json)：四个匹配场景的两轮对照，分列客户端输出与服务端 completion token 数。
- [round1-matrix.csv](round1-matrix.csv)：第一轮完整 18 组、207 请求矩阵；不是第二轮的覆盖范围。
- [round1-config.redacted.json](round1-config.redacted.json)：第一轮最终配置快照。
- [round2-all-cases.csv](round2-all-cases.csv)：第二轮 32 个实际 benchmark case，含诊断与共享前缀实验；不能把 32 行全部作为独立候选或无缓存验证。
- [screening-summary.json](screening-summary.json)：两阶段筛选接受结果、40K 容量试验与共享前缀原始控制器字段。
- [validation.json](validation.json)：构建版本/hash、容器配额、鉴权与小规模功能验收，机器登录标识已省略。
- [gpu-live.csv](gpu-live.csv)：总时长 15 秒、间隔 1 秒的两卡采样。
- [SHA256SUMS](SHA256SUMS)：本目录产物的内容校验；在此目录运行 `sha256sum -c SHA256SUMS`。

usage JSONL 首行是短预热，正式分析排除。原结果的 `input_lens` 是客户端标称长度，服务端实际输入与缓存值看 usage。共享前缀组 `valid=false` 是无缓存口径拒绝缓存命中，两个请求本身成功。

`launches/*.redacted.json` 只对凭证字段做脱敏。`*.evidence.json` 中的 `redacted_config_file`、`vllm_command_file` 保留本地采集时的文件名；本目录采用去除 `placement-` 前缀的文件名，按上表定位，字段本身没有改写成另一次运行。

客户端源码、适配说明与上游许可证在 [tools/vllm-benchmark-client](../../tools/vllm-benchmark-client/README.md)。

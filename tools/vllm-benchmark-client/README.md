# 本轮实用的 vLLM 独立客户端

`benchmark_serving.py` 与 `backend_request_func.py` 是 **vLLM v0.6.6** 的独立压测客户端适配副本，已用于 2026-11-14 两轮测试。推理服务为 Strata 0.1.45，没有用 vLLM 加载模型。

上游来源：[benchmark_serving.py](https://github.com/vllm-project/vllm/blob/v0.6.6/benchmarks/benchmark_serving.py)、[backend_request_func.py](https://github.com/vllm-project/vllm/blob/v0.6.6/benchmarks/backend_request_func.py)，遵循随附 [Apache-2.0 LICENSE](LICENSE)。本地适配包括：

- 缺少 vllm Python 包时兼容 tokenizer 和 ArgumentParser，仍需客户端依赖。
- chat 请求显式发送 `temperature=0`、`reasoning_effort=none`、`stream=true`、输出上限和 `ignore_eos=false`。
- 忽略 SSE 注释心跳，识别流内错误与缺失的正常结束事件。
- 预热改为独立短请求，记录服务端 usage / timings 到 `BENCH_USAGE_FILE`。

原始客户端内容 SHA-256：

```text
e167002d8588a424a5e6203d4e9edb5a9ac0512470ce37ee53728dfce388c201  benchmark_serving.py
8afccf11c33fd549449e408acf5b5308727ed9d7699ea060819dd7da9aa7ce4c  backend_request_func.py
```

客户端环境需要 `aiohttp`、`datasets`、`huggingface_hub`、`numpy`、`Pillow`、`tqdm`、`transformers`；本仓库不附带 Python 环境、HF tokenizer 或模型权重。原测试环境使用 `/root/vllm-bench-venv/bin/python` 与 `/data/vllm-benchmark/qwen-tokenizer`。这里没有声称在另一个新环境中重新安装验证。

`bench_tune.py` 是历史运行的外层 wrapper，内部仍指向原服务器 `/data/vllm-benchmark/benchmarks-strata/`，用于理解实际证据。仓库复现入口 [benchmark_latest_a100.sh](../../scripts/benchmark_latest_a100.sh) 直接使用本目录的客户端，并从指定私有 JSON 读取 Key 和模型名。

名义随机长度、实际服务端 usage、客户端输出重分词计数分别保留。首个 usage 记录属于短预热；不能把随机文本吞吐当自然业务基准，或把 `1 / mean TPOT` 当整场吞吐。

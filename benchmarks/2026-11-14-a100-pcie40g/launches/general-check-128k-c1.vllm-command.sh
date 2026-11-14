#!/usr/bin/env bash
# Historical actual command: original test port and result names.
# Credentials are read at runtime from the original private JSON.
set -euo pipefail
export OPENAI_API_KEY="$(/root/vllm-bench-venv/bin/python -c 'import json,sys; print(json.load(open(sys.argv[1]))["api_key"])' /data/vllm-benchmark/tuning-20261114-124051/general-validation.private.json)"
export BENCH_USAGE_FILE=/data/vllm-benchmark/tuning-20261114-124051/general-check-128k-c1-usage.jsonl
exec /root/vllm-bench-venv/bin/python /data/vllm-benchmark/benchmarks-strata/benchmark_serving.py --backend openai-chat --base-url http://127.0.0.1:8081 --endpoint /v1/chat/completions --model qwen3.8-flash-next-iq3_xxs --tokenizer /data/vllm-benchmark/qwen-tokenizer --dataset-name random --random-input-len 131072 --random-output-len 64 --random-range-ratio 1 --num-prompts 1 --max-concurrency 1 --seed 29128 --save-result --result-dir /data/vllm-benchmark/tuning-20261114-124051 --result-filename general-check-128k-c1.json --disable-tqdm

#!/usr/bin/env bash
set -euo pipefail

BENCH_REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BENCH_PY=${BENCH_PY:-/root/vllm-bench-venv/bin/python}
BENCH_CONFIG=${BENCH_CONFIG:-/data/Strata/strata-iq3_xxs-intranet-a100-40g.json}
BENCH_TOKENIZER=${BENCH_TOKENIZER:-/data/vllm-benchmark/qwen-tokenizer}
BENCH_BASE_URL=${BENCH_BASE_URL:-http://127.0.0.1:8080}
BENCH_OUTPUT=${BENCH_OUTPUT:-/data/vllm-benchmark/github-replay-$(date +%Y%m%d-%H%M%S)}
BENCH_SEED_OFFSET=${BENCH_SEED_OFFSET:-0}
BENCH_CLIENT="$BENCH_REPO/tools/vllm-benchmark-client/benchmark_serving.py"

if [[ -e "$BENCH_OUTPUT" ]]; then
  printf 'Result directory already exists: %s\n' "$BENCH_OUTPUT" >&2
  exit 1
fi
mkdir -p -- "$BENCH_OUTPUT"
export OPENAI_API_KEY
OPENAI_API_KEY=$("$BENCH_PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["api_key"])' "$BENCH_CONFIG")
BENCH_MODEL=$("$BENCH_PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["model_name"])' "$BENCH_CONFIG")
trap 'unset OPENAI_API_KEY BENCH_USAGE_FILE' EXIT

run_case() {
  local name=$1 input=$2 concurrency=$3 count=$4 seed=$5
  export BENCH_USAGE_FILE="$BENCH_OUTPUT/${name}-usage.jsonl"
  "$BENCH_PY" "$BENCH_CLIENT" \
    --backend openai-chat --base-url "$BENCH_BASE_URL" \
    --endpoint /v1/chat/completions --model "$BENCH_MODEL" \
    --tokenizer "$BENCH_TOKENIZER" --dataset-name random \
    --random-input-len "$input" --random-output-len 64 --random-range-ratio 1 \
    --num-prompts "$count" --max-concurrency "$concurrency" \
    --seed "$((seed + BENCH_SEED_OFFSET))" --save-result \
    --result-dir "$BENCH_OUTPUT" --result-filename "${name}.json" --disable-tqdm \
    > "$BENCH_OUTPUT/${name}.log" 2>&1
  "$BENCH_PY" - "$BENCH_OUTPUT/${name}.json" "$BENCH_USAGE_FILE" "$count" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
usage = [json.loads(line) for line in open(sys.argv[2]) if line.strip()][1:]
expected = int(sys.argv[3])
if result.get('completed') != expected or any(result.get('errors', [])) or len(usage) != expected:
    raise SystemExit('Incomplete or failed requests; inspect the result and log')
cache_counts = [row.get('usage', {}).get('prompt_tokens_details', {}).get('cached_tokens') for row in usage]
if any(type(value) is not int or value < 0 for value in cache_counts):
    raise SystemExit('Missing or invalid cached_tokens: fresh-input status cannot be verified')
if any(cache_counts):
    raise SystemExit('Cached input detected: this is not a fresh-input result; use a fresh service or new BENCH_SEED_OFFSET')
print({k: result.get(k) for k in ('completed', 'mean_ttft_ms', 'mean_tpot_ms', 'output_throughput')})
PY
}

# The historical final validation used these seeds and sample sizes on port 8081.
# This replay uses the configured service and a new result directory.
run_case general-check-32k-c1 32768 1 8 29001
run_case general-check-32k-c4 32768 4 4 29004
run_case general-check-64k-c1 65536 1 1 29064
run_case general-check-128k-c1 131072 1 1 29128
printf 'Results: %s\n' "$BENCH_OUTPUT"

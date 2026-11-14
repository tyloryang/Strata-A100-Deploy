"""Run the adapted upstream vLLM serving client; credentials stay in config/env."""
import argparse
import json
import os
from pathlib import Path
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--config', required=True)
p.add_argument('--output', required=True)
p.add_argument('--name', required=True)
p.add_argument('--input', type=int, required=True)
p.add_argument('--concurrency', type=int, required=True)
p.add_argument('--requests', type=int, required=True)
p.add_argument('--seed', type=int, default=7001)
p.add_argument('--port', type=int, default=8081)
p.add_argument('--output-tokens', type=int, default=64)
a = p.parse_args()
out = Path(a.output)
out.mkdir(parents=True, exist_ok=True)
cfg = json.loads(Path(a.config).read_text())
env = os.environ.copy()
env['OPENAI_API_KEY'] = cfg['api_key']
env['BENCH_USAGE_FILE'] = str(out / (a.name + '-usage.jsonl'))
command = ['/root/vllm-bench-venv/bin/python',
           '/data/vllm-benchmark/benchmarks-strata/benchmark_serving.py',
           '--backend', 'openai-chat', '--base-url', f'http://127.0.0.1:{a.port}',
           '--endpoint', '/v1/chat/completions', '--model', cfg['model_name'],
           '--tokenizer', '/data/vllm-benchmark/qwen-tokenizer',
           '--dataset-name', 'random', '--random-input-len', str(a.input),
           '--random-output-len', str(a.output_tokens), '--random-range-ratio', '1',
           '--num-prompts', str(a.requests), '--max-concurrency', str(a.concurrency),
           '--seed', str(a.seed), '--save-result', '--result-dir', str(out),
           '--result-filename', a.name + '.json', '--disable-tqdm']
print('COMMAND', json.dumps(command), flush=True)
raise SystemExit(subprocess.call(command, env=env))

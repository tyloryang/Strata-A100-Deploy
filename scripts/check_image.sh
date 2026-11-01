#!/bin/bash
# 镜像与源码自检：解释器、依赖、setup 参数、现有配置
set -u
B=/data/qwen-strata
I=strata-qwen38:cuda12-1.0

echo "==== $(date '+%F %T') 镜像自检"

echo "-- 容器内 venv 解释器"
docker run --rm -v "$B:/data" "$I" /data/Strata/.venv/bin/python -c 'import sys; print(sys.version); print(sys.executable)'

echo "-- 关键依赖"
docker run --rm -v "$B:/data" "$I" /data/Strata/.venv/bin/python -c '
import importlib.metadata as m
for n in ["torch","transformers","fastapi","uvicorn","numpy","pydantic","tiktoken","safetensors","requests"]:
    try:
        print(f"{n:14s} {m.version(n)}")
    except Exception as e:
        print(f"{n:14s} MISSING ({type(e).__name__})")
'

echo "-- torch 能否看到两张卡"
docker run --rm --gpus all -v "$B:/data" "$I" /data/Strata/.venv/bin/python -c '
import torch
print("torch", torch.__version__, "cuda", torch.version.cuda, "avail", torch.cuda.is_available(), "count", torch.cuda.device_count())
for i in range(torch.cuda.device_count()):
    p = torch.cuda.get_device_properties(i)
    print(i, p.name, round(p.total_memory/1024**3, 1), "GiB")
'

echo "-- setup.sh 支持的参数"
docker run --rm -v "$B:/data" "$I" bash -c 'cd /data/Strata && ./setup.sh --help 2>&1 | head -60'

echo "-- 现有配置（api_key 打码）"
docker run --rm -v "$B:/data" "$I" bash -c 'sed "s/\"api_key\": *\"[^\"]*\"/\"api_key\": \"<hidden>\"/" /data/Strata/strata-iq3_xxs.json'

echo "==== 自检结束 $(date '+%F %T')"

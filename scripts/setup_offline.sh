#!/bin/bash
# 阶段 D：用离线镜像生成双卡配置。API Key 从 /etc/strata/api_key 读入，
# 不出现在命令行、不出现在本文件、不出现在日志里。
set -u
BASE=/data/qwen-strata
IMG=strata-qwen38:cuda12-1.0
LOG=/root/offline_check/setup-offline.log

if [ ! -s /etc/strata/api_key ]; then
  echo "missing /etc/strata/api_key" >&2
  exit 1
fi

docker run --rm --gpus '"device=0,1"' \
  -e KEY="$(cat /etc/strata/api_key)" \
  --security-opt label=disable --ulimit memlock=-1:-1 \
  -v "$BASE:/data" "$IMG" \
  bash -c 'cd /data/Strata && ./setup.sh --setup --no-start --yes --cuda 12 --model IQ3_XXS --gpus 0,1 --vision no --context 262144 --no-browser --host 0.0.0.0 --api-key "$KEY" --data-dir /data/Strata-data --models-dir /data/Strata-data/models' \
  2>&1 | tee "$LOG"
echo "setup exit=${PIPESTATUS[0]}"

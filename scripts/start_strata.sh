#!/bin/bash
# 阶段 E：启动 strata 容器（双卡、绑定内网 IP、API Key 在配置 JSON 里）
set -u
BASE=/data/qwen-strata
IMG=strata-qwen38:cuda12-1.0
BIND_IP=${BIND_IP:-0.0.0.0}

docker rm -f strata >/dev/null 2>&1
docker run -d --name strata --restart unless-stopped \
  --gpus '"device=0,1"' --ulimit memlock=-1:-1 --shm-size 2g \
  --stop-timeout 120 --security-opt label=disable \
  -p "${BIND_IP}:8080:8080" -v "$BASE:/data" "$IMG" \
  /data/Strata/run-iq3_xxs.sh
echo "started: $(docker ps --filter name=strata --format '{{.Names}} {{.Status}} {{.Ports}}')"

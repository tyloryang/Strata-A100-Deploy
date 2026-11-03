#!/bin/bash
# 阶段 E（兜底）：compose 不可用时用 docker run 启动 strata 容器
# 双卡、API Key 在配置 JSON 里；端口与 compose 一致：宿主 ${BIND_IP}:${PORT} -> 容器 8080
# 平台只转发 8800~8805，PORT 必须落在其中
set -u
BASE=/data/qwen-strata
IMG=strata-qwen38:cuda12-1.0
BIND_IP=${BIND_IP:-0.0.0.0}
PORT=${PORT:-8800}

# 已有同名容器时先正常停止再删除；不要对运行中的容器 docker rm -f（见部署文档 §9.1）
docker stop -t 120 strata >/dev/null 2>&1 || true
docker rm strata >/dev/null 2>&1 || true
docker run -d --name strata --restart unless-stopped --init \
  --gpus '"device=0,1"' --ulimit memlock=-1:-1 --shm-size 2g \
  --stop-timeout 120 --security-opt label=disable \
  -p "${BIND_IP}:${PORT}:8080" -v "$BASE:/data" "$IMG" \
  /data/Strata/run-iq3_xxs.sh
echo "started: $(docker ps --filter name=strata --format '{{.Names}} {{.Status}} {{.Ports}}')"

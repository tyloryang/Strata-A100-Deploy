#!/bin/bash
# 恢复服务：清理残留容器后用 compose 重新拉起
set -u
LOG=/root/offline_check/recover.log
IP=${IP:-127.0.0.1}
cd /data/compose/strata || exit 1
exec > >(tee -a "$LOG") 2>&1

echo "==== $(date '+%F %T') 恢复服务"
docker ps -a --format '{{.Names}} | {{.Status}}'
docker rm -f strata 2>&1 || true

t0=$(date +%s)
docker-compose up -d
for i in $(seq 1 40); do
  sleep 5
  st=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' strata 2>/dev/null)
  if [ "$st" = "healthy" ]; then
    echo "healthy after $(( $(date +%s) - t0 ))s"
    break
  fi
done
docker-compose ps
curl -s --max-time 10 "http://$IP:8080/health"; echo
nvidia-smi --query-gpu=index,memory.used --format=csv,noheader
echo "==== $(date '+%F %T') 结束"

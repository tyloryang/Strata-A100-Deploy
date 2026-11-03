#!/bin/bash
# 恢复服务：先尝试正常停止，再清理残留容器，最后用 compose 重新拉起
# 如果容器已经卡在 zombie / did not receive an exit event 状态，先等它变 Exited (137)（约 5 分钟）或 systemctl restart docker
set -u
LOG=/root/offline_check/recover.log
mkdir -p "$(dirname "$LOG")"
IP=${IP:-127.0.0.1}
PORT=${PORT:-8800}   # 宿主机发布端口（compose: 8800 -> 容器 8080）
cd /data/compose/strata || exit 1
exec > >(tee -a "$LOG") 2>&1

echo "==== $(date '+%F %T') 恢复服务"
docker ps -a --format '{{.Names}} | {{.Status}}'
docker-compose stop 2>&1 || true
docker-compose down 2>&1 || true
# 只有 down 之后还残留（已停止）的容器才用 rm -f
docker ps -a --format '{{.Names}}' | grep -qx strata && docker rm -f strata 2>&1 || true

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
curl -s --max-time 10 "http://$IP:$PORT/health"; echo
nvidia-smi --query-gpu=index,memory.used --format=csv,noheader
echo "==== $(date '+%F %T') 结束"

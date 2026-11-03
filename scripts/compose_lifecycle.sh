#!/bin/bash
# compose 生命周期验证：restart / stop / start / down / up / rm -f
set -u
LOG=/root/offline_check/compose_lifecycle.log
mkdir -p "$(dirname "$LOG")"
IP=${IP:-127.0.0.1}
PORT=${PORT:-8800}   # 宿主机发布端口（compose: 8800 -> 容器 8080）
cd /data/compose/strata || exit 1
exec > >(tee -a "$LOG") 2>&1

wait_healthy() {
  local t0=$1
  for i in $(seq 1 40); do
    sleep 5
    st=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' strata 2>/dev/null)
    if [ "$st" = "healthy" ]; then echo "  healthy after $(( $(date +%s) - t0 ))s"; return 0; fi
  done
  echo "  NOT healthy after $(( $(date +%s) - t0 ))s"; return 1
}

echo "==== $(date '+%F %T') compose 生命周期"

echo "-- 1) restart"
t0=$(date +%s); docker-compose restart; wait_healthy "$t0"
curl -s --max-time 5 "http://$IP:$PORT/health" | head -c 120; echo

echo "-- 2) stop（应释放显存）"
t0=$(date +%s); docker-compose stop; echo "  stop $(( $(date +%s) - t0 ))s"
nvidia-smi --query-gpu=index,memory.used --format=csv,noheader
ss -ltnp | grep -c ":$PORT"

echo "-- 3) start"
t0=$(date +%s); docker-compose start; wait_healthy "$t0"
nvidia-smi --query-gpu=index,memory.used --format=csv,noheader

echo "-- 4) down（应删除容器，不碰 /data）"
t0=$(date +%s); docker-compose down; echo "  down $(( $(date +%s) - t0 ))s"
docker ps -a --format '{{.Names}} | {{.Status}}' | grep -c strata || true
df -h /data | tail -1

echo "-- 5) up -d 恢复"
t0=$(date +%s); docker-compose up -d; wait_healthy "$t0"
docker-compose ps

echo "-- 6) down 后再 rm -f 残留（容器已被 down 删除，这一步应立即返回；不要对运行中的容器 rm -f）"
docker-compose down
t0=$(date +%s); docker rm -f strata 2>&1; echo "  rm -f $(( $(date +%s) - t0 ))s rc=$?"
docker ps -a --format '{{.Names}}' | grep -c strata || echo "  已无 strata 容器"

echo "-- 7) 最终恢复服务"
t0=$(date +%s); docker-compose up -d; wait_healthy "$t0"
curl -s --max-time 10 "http://$IP:$PORT/health"; echo
echo "==== $(date '+%F %T') 结束"

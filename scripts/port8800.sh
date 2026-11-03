#!/bin/bash
# 把宿主发布端口改到 8800（平台已转发 外网13270 -> 内网8800），重建并本地验证（一次性迁移脚本，测试机上已执行完毕）
set -u
LOG=/root/offline_check/port8800.log
mkdir -p "$(dirname "$LOG")"
cd /data/compose/strata || exit 1
exec > >(tee -a "$LOG") 2>&1

echo "==== $(date '+%F %T') 切到 8800 -> 8080"
echo "-- 8800 占用检查"
ss -ltnp | grep -E ':(8800|8801|8802)\b' || echo "8800-8802 空闲"
echo "-- .env"; cat .env
echo "-- 解析后的 ports"; docker-compose config | sed -n '/ports:/,/restart:/p'

echo "-- down"
t0=$(date +%s); docker-compose down; echo "down $(( $(date +%s) - t0 ))s"

echo "-- up -d"
t1=$(date +%s); docker-compose up -d
for i in $(seq 1 40); do
  sleep 5
  st=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' strata 2>/dev/null)
  if [ "$st" = "healthy" ]; then echo "healthy after $(( $(date +%s) - t1 ))s"; break; fi
done

echo "-- 运行态"
docker port strata
ss -ltnp | grep 8800

echo "-- 本地探活"
for u in "http://127.0.0.1:8800/health" "http://127.0.0.1:8800/health" "http://127.0.0.1:8800/"; do
  printf '%-38s -> ' "$u"; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 "$u"
done
echo "-- 8080 现在应无监听"
ss -ltnp | grep -c ':8080' || echo "8080 无监听"
echo "==== $(date '+%F %T') 完成"

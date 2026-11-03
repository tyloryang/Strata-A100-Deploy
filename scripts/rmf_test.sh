#!/bin/bash
# ⚠️ 危险：复现"运行中 docker rm -f 卡死"的问题，会中断线上服务，容器可能卡住约 5 分钟。
# 测试机实测结论：init:true 不能解决，运行中 rm -f 仍然 did not receive an exit event。
# 结论已有，一般不需要再跑；确实要复现时设置 I_KNOW_THIS_BREAKS_SERVICE=1。
set -u
if [ "${I_KNOW_THIS_BREAKS_SERVICE:-0}" != 1 ]; then
  echo "拒绝执行：这个脚本会中断服务。确需复现请设置 I_KNOW_THIS_BREAKS_SERVICE=1" >&2
  exit 1
fi
LOG=/root/offline_check/rmf_test.log
mkdir -p "$(dirname "$LOG")"
cd /data/compose/strata || exit 1
exec > >(tee -a "$LOG") 2>&1

echo "==== $(date '+%F %T') 运行中 rm -f 测试"
docker inspect strata -f 'init={{.HostConfig.Init}} state={{.State.Status}} pid={{.State.Pid}}'

t0=$(date +%s)
docker rm -f strata
echo "rm -f 返回：$(( $(date +%s) - t0 ))s"
docker ps -a --format '{{.Names}} | {{.Status}}' | grep strata || echo "已无 strata 容器"
nvidia-smi --query-gpu=index,memory.used --format=csv,noheader

echo "-- 重新 up -d"
t1=$(date +%s)
docker-compose up -d
for i in $(seq 1 40); do
  sleep 5
  st=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' strata 2>/dev/null)
  if [ "$st" = "healthy" ]; then
    echo "healthy after $(( $(date +%s) - t1 ))s"
    break
  fi
done
curl -s --max-time 10 http://127.0.0.1:8800/health; echo
echo "==== $(date '+%F %T') 结束"

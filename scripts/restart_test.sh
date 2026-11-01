#!/bin/bash
# 验证 docker stop 释放显存、docker start 能再次就绪
LOG=/root/offline_check/restart.log
IP=192.168.122.4
exec > >(tee -a "$LOG") 2>&1

echo "==== $(date '+%F %T') 停止容器"
t0=$(date +%s)
docker stop strata
echo "stop elapsed=$(( $(date +%s) - t0 ))s"
sleep 3
echo "-- 停止后显存"
nvidia-smi --query-gpu=index,memory.used --format=csv,noheader
echo "-- 停止后进程"
ps -ef | grep -c '[e]ngine-cuda12/strata'

echo "==== $(date '+%F %T') 重新启动"
t1=$(date +%s)
docker start strata
for i in $(seq 1 60); do
  sleep 5
  if curl -s --max-time 3 "http://$IP:8080/health" 2>/dev/null | grep -q '"loaded": true'; then
    echo "ready after $(( $(date +%s) - t1 ))s"
    break
  fi
  echo "  waiting $(( $(date +%s) - t1 ))s"
done
echo "-- health"
curl -s --max-time 10 "http://$IP:8080/health"; echo
echo "-- 显存"
nvidia-smi --query-gpu=index,memory.used --format=csv,noheader
echo "==== $(date '+%F %T') 结束"

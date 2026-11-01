#!/bin/bash
# 运行中强制删除容器：验证 init:true 解决僵尸进程导致 rm -f 卡住的问题
set -u
LOG=/root/offline_check/rmf_test.log
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
curl -s --max-time 10 http://192.168.122.4:8080/health; echo
echo "==== $(date '+%F %T') 结束"

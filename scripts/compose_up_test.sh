#!/bin/bash
# 把现有 docker run 容器切换到 docker-compose 管理，并计时
set -u
LOG=/root/offline_check/compose.log
IP=192.168.122.4
cd /data/compose/strata || exit 1
exec > >(tee -a "$LOG") 2>&1

echo "==== $(date '+%F %T') 切换到 compose 管理"
echo "-- 现有容器"
docker ps -a --format '{{.Names}} | {{.Status}} | {{.Ports}}'

echo "-- 删除 docker run 起的同名容器"
docker rm -f strata

t0=$(date +%s)
echo "-- docker-compose up -d"
docker-compose up -d
echo "up -d 返回：$(( $(date +%s) - t0 ))s"

echo "-- 等待 healthy（健康检查 start_period 300s）"
for i in $(seq 1 60); do
  sleep 5
  st=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' strata 2>/dev/null)
  echo "  $(( $(date +%s) - t0 ))s health=$st"
  [ "$st" = "healthy" ] && break
done

echo "-- compose ps（总耗时 $(( $(date +%s) - t0 ))s）"
docker-compose ps

echo "-- health 端点"
curl -s --max-time 10 "http://$IP:8080/health"; echo

echo "-- 监听"
ss -ltnp | grep 8080

echo "-- 容器配置要点"
docker inspect strata -f 'restart={{.HostConfig.RestartPolicy.Name}} shm={{.HostConfig.ShmSize}} memlock={{.HostConfig.Ulimits}} devices={{range .HostConfig.DeviceRequests}}{{.Count}}/{{.DeviceIDs}}{{end}}'
docker inspect strata -f 'mounts={{range .Mounts}}{{.Source}}->{{.Destination}} {{end}}'

echo "-- GPU 占用"
nvidia-smi --query-gpu=index,memory.used --format=csv,noheader

echo "-- 推理冒烟"
KEY=$(cat /etc/strata/api_key)
curl -s --max-time 120 "http://$IP:8080/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"x","messages":[{"role":"user","content":"用一句话说明 compose 和 docker run 的区别。"}],"max_tokens":120,"temperature":0,"reasoning_effort":"none"}' \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("finish:", d["choices"][0]["finish_reason"], "| tok/s:", round(d["timings"]["predicted_per_second"],1)); print(d["choices"][0]["message"]["content"][:100])'

echo "==== $(date '+%F %T') 切换完成"

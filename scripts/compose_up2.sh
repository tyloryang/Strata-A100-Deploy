#!/bin/bash
# 清理残留容器后用 compose 启动并计时
set -u
LOG=/root/offline_check/compose.log
IP=${IP:-127.0.0.1}
cd /data/compose/strata || exit 1
exec > >(tee -a "$LOG") 2>&1

echo "==== $(date '+%F %T') compose 启动（init: true）"
docker ps -a --format '{{.Names}} | {{.Status}}'
echo "-- 删除残留容器"
docker rm -f strata 2>&1 || docker rm strata 2>&1 || true
docker ps -a --format '{{.Names}} | {{.Status}}'

t0=$(date +%s)
echo "-- docker-compose up -d"
docker-compose up -d
echo "up -d 返回：$(( $(date +%s) - t0 ))s"

echo "-- 等待 healthy"
for i in $(seq 1 40); do
  sleep 5
  st=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' strata 2>/dev/null)
  el=$(( $(date +%s) - t0 ))
  echo "  ${el}s health=$st"
  [ "$st" = "healthy" ] && break
done

echo "-- compose ps（总耗时 $(( $(date +%s) - t0 ))s）"
docker-compose ps

echo "-- 健康检查的最近一次输出"
docker inspect -f '{{range .State.Health.Log}}{{.ExitCode}} | {{.Output}}{{end}}' strata 2>/dev/null | tail -c 600

echo "-- health 端点"
curl -s --max-time 10 "http://$IP:8080/health"; echo

echo "-- 监听与 GPU"
ss -ltnp | grep 8080
nvidia-smi --query-gpu=index,memory.used --format=csv,noheader

echo "-- 推理冒烟"
KEY=$(cat /etc/strata/api_key)
curl -s --max-time 180 "http://$IP:8080/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"x","messages":[{"role":"user","content":"用一句话说明 compose 和 docker run 的区别。"}],"max_tokens":120,"temperature":0,"reasoning_effort":"none"}' \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("finish:", d["choices"][0]["finish_reason"], "| decode tok/s:", round(d["timings"]["predicted_per_second"],1)); print(d["choices"][0]["message"]["content"][:100])'

echo "==== $(date '+%F %T') 完成"

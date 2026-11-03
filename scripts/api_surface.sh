#!/bin/bash
# 额外验证：Anthropic 兼容端点 + 两个并发请求的处理方式
# parallel=1 时第二个请求排队；parallel>=2 时两个请求进 batch 槽位一起解码
KEY=$(cat /etc/strata/api_key)
IP=${IP:-127.0.0.1}
PORT=${PORT:-8800}   # 宿主机发布端口（compose: 8800 -> 容器 8080）
LOG=/root/offline_check/api_surface.log
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date '+%F %T') 接口面验证"

echo "-- Anthropic /v1/messages"
curl -s --max-time 120 "http://$IP:$PORT/v1/messages" \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -H 'anthropic-version: 2023-06-01' \
  -d '{"model":"x","max_tokens":120,"messages":[{"role":"user","content":"用一句话解释什么是 ARP 协议。"}]}' | head -c 800
echo

echo "-- 无 Key 访问 /v1/messages（期望 401）"
curl -s -o /dev/null -w '%{http_code}\n' --max-time 20 "http://$IP:$PORT/v1/messages" \
  -H 'Content-Type: application/json' -d '{"model":"x","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}'

echo "-- 两个并发请求（parallel=1 时应串行，第二个等待）"
for i in 1 2; do
  ( t0=$(date +%s.%N)
    r=$(curl -s --max-time 120 "http://$IP:$PORT/v1/chat/completions" \
      -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
      -d '{"model":"x","messages":[{"role":"user","content":"说三个 Linux 常用命令及其用途。"}],"max_tokens":80,"temperature":0,"reasoning_effort":"none"}')
    t1=$(date +%s.%N)
    echo "req$i wall=$(echo "$t1 - $t0" | bc)s tokens=$(echo "$r" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["usage"]["completion_tokens"])' 2>/dev/null)" ) &
done
wait

echo "-- 请求后资源"
curl -s --max-time 10 -H "Authorization: Bearer $KEY" "http://$IP:$PORT/slots"; echo
free -h | head -2
nvidia-smi --query-gpu=index,memory.used,utilization.gpu --format=csv,noheader
echo "==== $(date '+%F %T') 结束"

#!/bin/bash
# 阶段 F：验收。所有输出同时写入 /root/offline_check/accept.log
set -u
BASE=/data/qwen-strata
LOG=/root/offline_check/accept.log
mkdir -p "$(dirname "$LOG")"
IP=${BIND_IP:-127.0.0.1}
KEY=$(cat /etc/strata/api_key)

exec > >(tee -a "$LOG") 2>&1
echo "==== $(date '+%F %T') 验收 start"

echo "-- 1. health (127.0.0.1)"
curl -s --max-time 20 http://127.0.0.1:8800/health; echo

echo "-- 2. /v1/models 无 Key（期望 401）"
curl -s -o /dev/null -w '%{http_code}\n' --max-time 20 "http://$IP:8800/v1/models"

echo "-- 3. /v1/models 有 Key（期望 200）"
curl -s -o /dev/null -w '%{http_code}\n' --max-time 20 -H "Authorization: Bearer $KEY" "http://$IP:8800/v1/models"

echo "-- 4. 模型列表条目数"
curl -s --max-time 20 -H "Authorization: Bearer $KEY" "http://$IP:8800/v1/models" | head -c 400; echo

echo "-- 5. chat 推理（期望通顺中文，finish_reason=stop）"
curl -s --max-time 300 "http://$IP:8800/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"x","messages":[{"role":"user","content":"用一句话说明什么是TCP三次握手。"}],"max_tokens":200,"temperature":0,"reasoning_effort":"none"}'
echo

echo "-- 6. slots"
curl -s --max-time 20 -H "Authorization: Bearer $KEY" http://127.0.0.1:8800/slots | head -c 600; echo

echo "-- 7. nvidia-smi"
nvidia-smi

echo "-- 8. 内存"
free -h

echo "==== $(date '+%F %T') 验收 end"

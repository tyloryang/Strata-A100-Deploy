#!/bin/bash
# 速度与内存观测：短提示 400 token、同提示复测（缓存）、长提示 2000 token 预填
KEY=$(cat /etc/strata/api_key)
IP=${IP:-127.0.0.1}
URL="http://$IP:8080/v1/chat/completions"

call() {
  local label="$1" prompt="$2" maxtok="$3"
  local t0=$(date +%s.%N)
  local resp
  resp=$(curl -s --max-time 600 "$URL" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    -d "{\"model\":\"x\",\"messages\":[{\"role\":\"user\",\"content\":\"$prompt\"}],\"max_tokens\":$maxtok,\"temperature\":0,\"reasoning_effort\":\"none\"}")
  local t1=$(date +%s.%N)
  echo "==== $label  wall=$(echo "$t1 - $t0" | bc)s"
  echo "$resp" | python3 -c '
import json,sys
d=json.load(sys.stdin)
t=d.get("timings",{})
u=d.get("usage",{})
print("prompt_tokens", u.get("prompt_tokens"), "completion_tokens", u.get("completion_tokens"), "finish", d["choices"][0].get("finish_reason"))
print("prefill  %s tok/s (%.0f ms)" % (round(t.get("prompt_per_second",0),1), t.get("prompt_ms",0)))
print("decode   %s tok/s (%.1f ms/token)" % (round(t.get("predicted_per_second",0),1), t.get("predicted_per_token_ms",0)))
print("draft    %s/%s accepted" % (t.get("draft_n_accepted"), t.get("draft_n")))
print("text", d["choices"][0]["message"]["content"][:80].replace("\n"," "))
' 2>&1 | head -8
}

call "A 短提示 400token" "请用中文写一段 300 字左右的说明，介绍服务器运维中常见的五个故障类型及其排查顺序。" 400
call "B 同提示复测(缓存)" "请用中文写一段 300 字左右的说明，介绍服务器运维中常见的五个故障类型及其排查顺序。" 400

LONG=$(python3 -c 'print("服务器运维手册包括部署、监控、备份、故障排查和安全加固等内容。"*90)')
call "C 长提示预填" "$LONG 请用一句话说明上面重复了什么。" 64

echo "==== 内存与显存"
free -h
nvidia-smi --query-gpu=index,memory.used,utilization.gpu,temperature.gpu,power.draw --format=csv,noheader

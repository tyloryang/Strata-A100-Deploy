#!/bin/bash
# 验证 262144 上下文：发一个约 20 万 token 的中文长提示，记录预填耗时
LOG=/root/offline_check/longctx.log
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
IP=${IP:-127.0.0.1}
PORT=${PORT:-8800}   # 宿主机发布端口（compose: 8800 -> 容器 8080）
KEY=$(cat /etc/strata/api_key)
echo "==== $(date '+%F %T') 长上下文测试"

python3 - "$IP" "$KEY" "$PORT" <<'PY'
import json, os, sys, time, urllib.request

ip, key, port = sys.argv[1], sys.argv[2], sys.argv[3]
N = 9000
text = "服务器运维手册包括部署、监控、备份、故障排查和安全加固等内容。" * N
body = {
    "model": "x",
    "messages": [{"role": "user", "content": "请阅读下面的文字，用一句话说明它重复了什么。" + text}],
    "max_tokens": 64,
    "temperature": 0,
    "reasoning_effort": "none",
}
data = json.dumps(body).encode()
print(f"prompt chars={len(text):,}  body bytes={len(data):,}")
req = urllib.request.Request(
    f"http://{ip}:{port}/v1/chat/completions",
    data=data,
    headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
)
t0 = time.time()
try:
    with urllib.request.urlopen(req, timeout=1800) as r:
        raw = r.read()
    dt = time.time() - t0
    j = json.loads(raw)
    print(f"HTTP 200 in {dt:.1f}s")
    print("usage:", j.get("usage"))
    t = j.get("timings", {})
    print("prefill: %s tok/s, %.1f s" % (round(t.get("prompt_per_second", 0), 1), t.get("prompt_ms", 0) / 1000))
    print("decode : %s tok/s" % round(t.get("predicted_per_second", 0), 1))
    print("text   :", j["choices"][0]["message"]["content"][:120].replace("\n", " "))
except urllib.error.HTTPError as e:
    print(f"HTTP {e.code} in {time.time()-t0:.1f}s")
    print(e.read()[:500].decode("utf-8", "replace"))
except Exception as e:
    print(f"ERROR after {time.time()-t0:.1f}s: {type(e).__name__}: {e}")
PY

echo "-- 之后的状态"
curl -s --max-time 10 "http://$IP:$PORT/health"; echo
free -h | head -2
nvidia-smi --query-gpu=index,memory.used --format=csv,noheader
echo "==== $(date '+%F %T') 结束"

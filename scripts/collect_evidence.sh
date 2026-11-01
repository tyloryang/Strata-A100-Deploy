#!/bin/bash
# 证据收集：把验收需要的系统状态与日志落到 /root/offline_check/evidence/<时间戳>/
set -u
BASE=/data/qwen-strata
OUT=/root/offline_check/evidence/$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"

nvidia-smi > "$OUT/nvidia-smi.txt" 2>&1
nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,temperature.gpu,power.draw --format=csv > "$OUT/gpu-query.csv" 2>&1
free -h > "$OUT/free.txt" 2>&1
df -h > "$OUT/df.txt" 2>&1
docker ps -a > "$OUT/docker-ps.txt" 2>&1
docker images > "$OUT/docker-images.txt" 2>&1
docker logs strata > "$OUT/strata.log" 2>&1
ss -ltnp > "$OUT/listen.txt" 2>&1
uname -a > "$OUT/uname.txt" 2>&1
cat /proc/driver/nvidia/version > "$OUT/nvidia-version.txt" 2>&1
ls -l "$BASE" "$BASE/Strata-data" "$BASE/Strata-data/models/IQ3_XXS" > "$OUT/tree.txt" 2>&1
if [ -f "$BASE/Strata/strata-iq3_xxs.json" ]; then
  sed 's/"api_key": *"[^"]*"/"api_key": "<hidden>"/' "$BASE/Strata/strata-iq3_xxs.json" > "$OUT/strata-config.redacted.json"
fi
echo "evidence -> $OUT"
ls -l "$OUT"

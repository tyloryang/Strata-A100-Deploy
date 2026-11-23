#!/bin/bash
# 0.2.20 补测：只读，不改配置、不重启容器
set -u
C=strata-0220
NEW=/data/Strata-0.2.20
LOG=$NEW/strata-iq3_xxs.log
TS=$(date +%Y%m%d-%H%M%S)
OUT=$NEW/ab-runs/supp-$TS
mkdir -p "$OUT"
cp /tmp/strata-0220-decode_bench.py "$OUT/decode_bench.py"
cp /tmp/strata-0220-quality.py "$OUT/quality.py"
echo "out=$OUT health=$(docker inspect -f '{{.State.Health.Status}}' $C)"

echo "== NV_CHUNK 调查（只读）"
echo "-- 引擎二进制里与 chunk 相关的环境变量名"
grep -a -o -E 'STRATA_[A-Z0-9_]*CHUNK[A-Z0-9_]*' $NEW/engine-cuda12/strata | sort | uniq -c
echo "-- 'prompt chunk auto' 附近的字符串"
grep -a -o -E '.{0,160}prompt chunk auto.{0,240}' $NEW/engine-cuda12/strata | head -5
echo "-- control 侧 python 是否引用"
grep -rn -E 'NV_CHUNK|SPLIT_CHUNK16K' $NEW/serve $NEW/strata_control $NEW/strata_cli 2>/dev/null | head -20
echo "-- 当前容器内引擎进程的 env（只看 STRATA_）"
P=$(docker exec $C pgrep -f engine-cuda12/strata | head -1)
[ -n "$P" ] && docker exec $C sh -c "tr '\0' '\n' < /proc/$P/environ | grep -E '^STRATA_' | sort"
echo "-- 当前引擎参数里的 --prefill"
[ -n "$P" ] && docker exec $C sh -c "tr '\0' ' ' < /proc/$P/cmdline" | grep -o -E -- '--prefill [^ ]+'

l0=$(wc -l < "$LOG")
b() { echo "== decode $3 n=$1 max_tokens=$2 ($(date +%T))"; docker exec -i $C python3 - "$1" "$2" "$3" "$OUT" < "$OUT/decode_bench.py" | tee "$OUT/$3.txt"; }
b 1 64 warm
b 1 512 c1a
b 1 512 c1b
b 1 512 c1c
b 2 512 c2
b 4 512 c4
nvidia-smi dmon -s ut -d 1 -c 40 > "$OUT/c8-dmon.txt" 2>&1 &
D=$!
b 8 512 c8
wait $D 2>/dev/null

echo "== quality ($(date +%T))"
docker exec -i $C python3 - "$OUT" q < "$OUT/quality.py" | tee "$OUT/quality.txt"

sed -n "$((l0+1)),\$p" "$LOG" > "$OUT/engine-log.txt"
echo "== engine log: generated lines"
grep -E 'generated in' "$OUT/engine-log.txt" | sed -E 's/^.*strata serve: //' | tail -40
echo "== c8 dmon (head)"; head -25 "$OUT/c8-dmon.txt"
echo "health=$(docker inspect -f '{{.State.Health.Status}}' $C)"
echo SUPP-DONE

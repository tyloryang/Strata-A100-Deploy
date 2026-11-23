#!/bin/bash
# 0.2.20 A/B：口径与 /tmp/strata-ab.sh 的 armA（0.1.45）一致
#   armC = 0.2.20 原配置 + 与 armA 相同的计时 env（STRATA_TRACE / PREFILL_TIMING / SPLIT_TIMING）
#   armD = armC + STRATA_NV_CHUNK=0（退回 0.2.11 之前的 prompt chunk 行为，对应旧的 auto:12288）
set -u
C=strata-0220
CFG=/data/Strata-0.2.20/strata-iq3_xxs.json
LOG=/data/Strata-0.2.20/strata-iq3_xxs.log
TS=$(date +%Y%m%d-%H%M%S)
OUT=/data/Strata-0.2.20/ab-runs/$TS
mkdir -p "$OUT"
BAK=$CFG.bak-$TS
cp -p "$CFG" "$BAK" || exit 1
echo "out=$OUT bak=$BAK"

# 同一份 bench.py，只把读 api_key 的路径换成新配置（新容器没挂 /data/Strata）
sed 's#/data/Strata/strata-iq3_xxs.json#/data/Strata-0.2.20/strata-iq3_xxs.json#' \
  /data/Strata/ab-runs/20261123-232328/bench.py > "$OUT/bench.py" || exit 1
diff /data/Strata/ab-runs/20261123-232328/bench.py "$OUT/bench.py"

docker exec -i $C python3 - "$BAK" "$OUT" <<'PY' || exit 1
import json, sys
bak, out = sys.argv[1], sys.argv[2]
c = json.load(open(bak))
a = dict(c); a["env"] = dict(c.get("env", {}), STRATA_TRACE="1", STRATA_PREFILL_TIMING="1", STRATA_SPLIT_TIMING="1")
b = dict(a); b["env"] = dict(a["env"], STRATA_NV_CHUNK="0")
for name, x in (("armC", a), ("armD", b)):
    json.dump(x, open(out + "/" + name + ".json", "w"), indent=2, ensure_ascii=False)
print("variants ok")
PY

wait_healthy() {
  local t0=$(date +%s) s=""
  sleep 10
  while true; do
    s=$(docker inspect -f '{{.State.Health.Status}}' $C 2>/dev/null)
    if [ "$s" = "healthy" ]; then echo "$1: healthy after $(( $(date +%s) - t0 ))s"; return 0; fi
    if [ "$(docker inspect -f '{{.State.Running}}' $C)" = "false" ]; then echo "$1: CONTAINER EXITED"; return 1; fi
    if [ $(( $(date +%s) - t0 )) -gt 1200 ]; then echo "$1: TIMEOUT status=$s"; return 1; fi
    sleep 5
  done
}
restore() {
  trap - EXIT INT TERM
  echo "== restore ($(date +%T))"
  cp -p "$BAK" "$CFG"
  docker restart $C >/dev/null
  wait_healthy restore
  cmp -s "$BAK" "$CFG" && echo "config restored = $BAK"
  echo "ALL DONE ($(date +%T))"
}
trap restore EXIT
trap 'exit 130' INT TERM

run_arm() {
  local name=$1 file=$2
  echo "== arm $name ($(date +%T))"
  cp -p "$file" "$CFG"
  local l0=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  docker restart $C >/dev/null
  wait_healthy "$name" || return 1
  docker exec -i $C python3 - 1 20 < "$OUT/bench.py" > "$OUT/$name-warm.txt" 2>&1
  nvidia-smi dmon -s ut -d 1 -c 20 > "$OUT/$name-dmon.txt" 2>&1 &
  local d=$!
  sleep 1
  docker exec -i $C python3 - 1 5300 < "$OUT/bench.py" > "$OUT/$name-c1a.txt" 2>&1
  wait $d
  docker exec -i $C python3 - 1 5300 < "$OUT/bench.py" > "$OUT/$name-c1b.txt" 2>&1
  docker exec -i $C python3 - 4 5300 < "$OUT/bench.py" > "$OUT/$name-c4.txt" 2>&1
  local l1=$(wc -l < "$LOG")
  if [ "$l1" -gt "$l0" ]; then sed -n "$((l0+1)),\$p" "$LOG" > "$OUT/$name-log.txt"; else cp "$LOG" "$OUT/$name-log.txt"; fi
  echo "-- $name results"; cat "$OUT/$name-warm.txt" "$OUT/$name-c1a.txt" "$OUT/$name-c1b.txt" "$OUT/$name-c4.txt"
  grep -E 'prompt chunk auto|engine 0\.1\.' "$OUT/$name-log.txt" | head -4
  grep -E 'prompt [0-9]+ tokens' "$OUT/$name-log.txt" | tail -8
}
run_arm armC "$OUT/armC.json"
run_arm armD "$OUT/armD.json"

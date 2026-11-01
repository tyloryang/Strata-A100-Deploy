#!/bin/bash
# Passive upload watcher: logs /data contents every 60s, writes STATUS markers.
# Never computes hashes (that would compete with the upload bandwidth).
LOG=/root/offline_check/upload_watch.log
STATUS=/root/offline_check/status.txt
mkdir -p /root/offline_check
: > "$LOG"

declare -A EXPECT=(
  [data-mtp.tar]="6927687680"
  [data-packs.tar]="44460963840"
  [gguf_done.tar]="286"
  [Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00002-of-00002.tar]="75840001024"
  [SHA256SUMS-tars.txt]="412"
  [strata-qwen38-cuda12-1.0.tar]="7630861312"
  [strata-src.tar]="932792320"
  [tools.tar]="1217095680"
)

prev=""
stable=0
while true; do
  ts=$(date '+%F %T')
  parts=$(ls /data/*.filepart 2>/dev/null | wc -l)
  nfiles=$(find /data -maxdepth 1 -type f | wc -l)
  bytes=$(du -sb --apparent-size /data 2>/dev/null | cut -f1)
  cur=$(find /data -maxdepth 1 -type f -printf '%f %s\n' 2>/dev/null | sort | md5sum | cut -d' ' -f1)
  echo "$ts files=$nfiles parts=$parts bytes=$bytes" >> "$LOG"

  ready=1
  detail=""
  for name in "${!EXPECT[@]}"; do
    p="/data/$name"
    if [ -f "$p" ]; then
      sz=$(stat -c %s "$p")
      if [ "$sz" -eq "${EXPECT[$name]}" ]; then
        detail+="OK $name $sz"$'\n'
      else
        detail+="PARTIAL $name $sz/${EXPECT[$name]}"$'\n'
        ready=0
      fi
    else
      detail+="MISSING $name"$'\n'
      ready=0
    fi
  done

  if [ "$parts" -eq 0 ] && [ "$cur" = "$prev" ]; then
    stable=$((stable + 1))
  else
    stable=0
  fi
  prev="$cur"

  state="uploading"
  if [ "$ready" -eq 1 ] && [ "$parts" -eq 0 ] && [ "$stable" -ge 2 ]; then
    state="COMPLETE"
  elif [ "$parts" -eq 0 ] && [ "$stable" -ge 5 ]; then
    state="IDLE_INCOMPLETE"
  fi

  {
    echo "state=$state ts=$ts parts=$parts stable=$stable bytes=$bytes"
    printf '%s' "$detail"
  } > "$STATUS"

  if [ "$state" = "COMPLETE" ]; then
    echo "$ts COMPLETE" >> "$LOG"
    exit 0
  fi
  sleep 60
done

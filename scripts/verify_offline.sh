#!/bin/bash
# 阶段 A：校验离线包。只读操作，可重复执行。
set -u
PK=/data
LOG=/root/offline_check/checksum.log
cd "$PK" || exit 1

t0=$(date +%s)
{
  echo "==================== $(date '+%F %T') tar checksums"
  sha256sum -c SHA256SUMS-tars.txt
  rc=$?
  echo "sha256sum -c exit=$rc elapsed=$(( $(date +%s) - t0 ))s"
} 2>&1 | tee -a "$LOG"

GG="$PK/qwen-strata/Strata-data/models/IQ3_XXS"
if compgen -G "$GG/*.gguf" > /dev/null; then
  t1=$(date +%s)
  {
    echo "==================== $(date '+%F %T') model checksums"
    sha256sum "$GG"/*.gguf
    echo "gguf elapsed=$(( $(date +%s) - t1 ))s"
    echo "expect part1 219ea929900dfa9ef091f3aa473fdba6874b65fcb36526d7d851ac9e95856d15"
    echo "expect part2 316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113"
  } 2>&1 | tee -a "$LOG"
else
  echo "$(date '+%F %T') gguf not extracted yet" | tee -a "$LOG"
fi

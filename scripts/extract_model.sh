#!/bin/bash
# 解包模型 tar 并校验两片 GGUF（与上传并行，只占本地磁盘 I/O）
set -u
SRC=/data/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00002-of-00002.tar
DST=/data/qwen-strata/Strata-data/models/IQ3_XXS
LOG=/root/offline_check/extract_model.log
mkdir -p "$DST"

echo "==== $(date '+%F %T') extract start, src=$(stat -c %s "$SRC") bytes" >> "$LOG"
t0=$(date +%s)
tar -xvf "$SRC" -C "$DST" >> "$LOG" 2>&1
rc=$?
echo "tar exit=$rc elapsed=$(( $(date +%s) - t0 ))s at $(date '+%F %T')" >> "$LOG"
ls -l "$DST" >> "$LOG" 2>&1

echo "==== $(date '+%F %T') sha256" >> "$LOG"
t1=$(date +%s)
sha256sum "$DST"/*.gguf >> "$LOG" 2>&1
echo "hash elapsed=$(( $(date +%s) - t1 ))s" >> "$LOG"
echo "EXPECT 00001 219ea929900dfa9ef091f3aa473fdba6874b65fcb36526d7d851ac9e95856d15" >> "$LOG"
echo "EXPECT 00002 316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113" >> "$LOG"
echo "==== $(date '+%F %T') done" >> "$LOG"

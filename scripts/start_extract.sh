#!/bin/bash
# 启动解包脚本（后台，pid 记录），避免命令行里出现脚本名导致 pkill 误杀
cd /root/offline_check || exit 1
if [ -f extract.pid ] && kill -0 "$(cat extract.pid)" 2>/dev/null; then
  echo "already running pid=$(cat extract.pid)"
  exit 0
fi
setsid nohup ./extract_model.sh >/dev/null 2>&1 &
echo $! > extract.pid
sleep 1
echo "started pid=$(cat extract.pid)"

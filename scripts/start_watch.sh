#!/bin/bash
cd /root/offline_check || exit 1
if [ -f watch.pid ] && kill -0 "$(cat watch.pid)" 2>/dev/null; then
  echo "already running pid=$(cat watch.pid)"
  exit 0
fi
setsid nohup ./watch_upload.sh >/dev/null 2>&1 &
echo $! > watch.pid
sleep 1
echo "started pid=$(cat watch.pid)"

#!/bin/bash
# 0.2.20 A/B：修正配置里唯一残留的旧目录引用，停旧容器（不删），起新容器 strata-0220
set -euo pipefail
CFG=/data/Strata-0.2.20/strata-iq3_xxs.json
NEW=/data/Strata-0.2.20

# expert-profile.bin 新旧 sha256 相同（8f59b4aa...），新容器不挂 /data/Strata，所以改指新目录里的同一份文件
test -e $CFG.orig || cp -a $CFG $CFG.orig
sed -i 's#/data/Strata/data/expert-profile.bin#/data/Strata-0.2.20/data/expert-profile.bin#' $CFG
python3 -m json.tool $CFG >/dev/null && echo json-ok
if grep -q '"/data/Strata/' $CFG; then echo 'LEFTOVER old-dir reference'; exit 1; fi
echo '== diff orig -> new'; diff $CFG.orig $CFG || true

# 记录旧容器完整配置，便于回滚核对
docker inspect strata > $NEW/strata-old-inspect.json
echo '== stopping old container strata (kept, not removed)'
docker stop -t 120 strata
docker ps -a --format '{{.Names}} {{.Status}}' | grep -E '^strata ' || true

HC='python3 -c '"'"'import json,urllib.request; assert json.load(urllib.request.urlopen("http://127.0.0.1:8080/health", timeout=5)).get("loaded") is True'"'"''

docker run -d --name strata-0220 \
  --gpus '"device=0,1"' \
  -p 8800:8080 \
  --shm-size 2g \
  --ulimit memlock=-1:-1 \
  --restart no \
  -v /data/Strata-data:/data/Strata-data:ro \
  -v $NEW:$NEW \
  --health-cmd "$HC" \
  --health-interval 20s --health-timeout 8s --health-start-period 300s --health-retries 3 \
  --entrypoint /opt/nvidia/nvidia_entrypoint.sh \
  strata-qwen38:0.1.45-cuda12 \
  $NEW/python/bin/python3 $NEW/serve/server.py --engine strata --config $CFG --host 0.0.0.0 --port 8080

sleep 10
docker ps -a --format '{{.Names}} {{.Status}} {{.Ports}}'
echo '== container log tail'
docker logs --tail 40 strata-0220 2>&1 || true
echo START-0220-DONE

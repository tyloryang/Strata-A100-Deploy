#!/bin/bash
# 部署前检查，输出追加到 /root/offline_check/preflight.log
L=/root/offline_check/preflight.log
exec > >(tee -a "$L") 2>&1
echo "==== $(date '+%F %T') 部署前检查"
echo "-- 端口 8080/1309"
ss -ltnp 2>/dev/null | grep -E ':8080|:1309' || echo "8080/1309 空闲"
echo "-- 运行中的容器"
docker ps --format '{{.Names}} | {{.Image}} | {{.Ports}}' || true
echo "-- 内存"
free -h
echo "-- SELinux"
getenforce 2>/dev/null || echo "n/a"
echo "-- 磁盘类型(ROTA 1=机械/虚拟)"
lsblk -d -o NAME,ROTA,SIZE
echo "-- /data 容量"
df -h /data
echo "-- GPU 占用"
nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader
echo "-- docker 版本/runtime"
docker --version
docker info 2>/dev/null | grep -E 'Runtimes|Default Runtime'

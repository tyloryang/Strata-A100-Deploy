#!/bin/bash
# compose 端口/IP 取证：配置意图 vs 运行态
echo "== 时间 $(date '+%F %T')"
echo
echo "== 容器列表"
docker ps -a --format '{{.Names}} | {{.Status}} | {{.Ports}} | {{.CreatedAt}}'
echo
echo "== compose 文件修改时间"
cd /data/compose/strata || exit 1
ls -l --time-style=full-iso .env docker-compose.yml
echo
echo "== .env 内容"
cat .env
echo
echo "== docker-compose config 的 ports 段"
docker-compose config | sed -n '/ports:/,/restart:/p'
echo
echo "== 运行态：docker port"
docker port strata
echo
echo "== 运行态：PortBindings"
docker inspect strata -f '{{json .HostConfig.PortBindings}}'
echo
echo "== 容器创建时间 vs 现在"
docker inspect strata -f '{{.Created}}'
echo
echo "== 宿主机所有监听端口"
ss -ltnp
echo
echo "== 探活"
for u in "http://127.0.0.1:8800/health" "http://192.168.122.4:8800/health" "http://127.0.0.1:8080/health" "http://192.168.122.4:8080/health"; do
  printf '%-42s -> ' "$u"
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 "$u" || echo "fail"
done
echo
echo "== 容器内监听（读 /proc/net/tcp，十六进制端口）"
docker exec strata sh -c 'cat /proc/net/tcp | awk "NR>1 {split(\$2,a,\":\"); print \$4, a[2]}" | sort -u' 2>&1 | head -10
echo
echo "== 容器内 config 的 port/host"
grep -E '"port"|"host"' /data/qwen-strata/Strata/strata-iq3_xxs.json

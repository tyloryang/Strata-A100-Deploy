#!/bin/bash
# Web 页面可用性：页面 + 关键静态资源 + 一次真实对话
IP=127.0.0.1
echo "== 页面"
curl -s -o /dev/null -w 'GET /            %{http_code} %{content_type} %{size_download}B\n' --max-time 10 "http://$IP:8800/"
echo "== 静态资源"
for p in /web/tokens.css /web/app.js /web/favicon.svg; do
  curl -s -o /dev/null -w "GET $p -> %{http_code} %{content_type}\n" --max-time 10 "http://$IP:8800$p"
done
echo "== 页面里引用的资源清单"
curl -s --max-time 10 "http://$IP:8800/" | grep -oE '(href|src)="[^"]+"' | sort -u | head -12
echo "== 用页面同一入口对话（带 Key）"
KEY=$(cat /etc/strata/api_key)
curl -s --max-time 120 "http://$IP:8800/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"x","messages":[{"role":"user","content":"一句话说明这个 Web 页面怎么用。"}],"max_tokens":80,"temperature":0,"reasoning_effort":"none"}' \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("finish:",d["choices"][0]["finish_reason"],"tok/s:",round(d["timings"]["predicted_per_second"],1)); print(d["choices"][0]["message"]["content"][:90])'

import json, sys, threading, time, urllib.request

# 用法: decode_bench.py N MAX_TOKENS TAG OUTDIR
n = int(sys.argv[1]); max_tokens = int(sys.argv[2]); tag = sys.argv[3]; outdir = sys.argv[4]
key = json.load(open("/data/Strata-0.2.20/strata-iq3_xxs.json")).get("api_key", "")
TOPICS = ["长江流域的地理、历史和经济", "宋代的科举制度", "光合作用的过程", "TCP 拥塞控制的原理",
          "蒸汽机对工业革命的影响", "中国古代的四大发明", "城市地铁系统的规划", "海洋酸化的成因和影响"]
res = {}
T0 = time.time()


def one(i):
    topic = TOPICS[i % len(TOPICS)]
    body = {"model": "qwen3.8-flash-next-iq3_xxs", "max_tokens": max_tokens, "stream": True, "temperature": 0,
            "stream_options": {"include_usage": True},
            "messages": [{"role": "user", "content": f"请用中文写一篇关于{topic}的介绍，分几个小节，不少于 1500 字。"}]}
    req = urllib.request.Request("http://127.0.0.1:8080/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    t0 = time.time(); first = None; last = None; chunks = 0; text = []; usage = None
    try:
        with urllib.request.urlopen(req, timeout=900) as r:
            for line in r:
                s = line.decode("utf-8", "ignore").strip()
                if not s.startswith("data:") or "[DONE]" in s:
                    continue
                try:
                    d = json.loads(s[5:])
                except Exception:
                    continue
                if d.get("usage"):
                    usage = d["usage"]
                de = ((d.get("choices") or [{}])[0].get("delta") or {})
                piece = (de.get("content") or "") + (de.get("reasoning_content") or "")
                if piece:
                    now = time.time()
                    if first is None:
                        first = now
                    last = now
                    chunks += 1
                    text.append(piece)
        ct = (usage or {}).get("completion_tokens")
        span = (last - first) if (first and last) else 0
        res[i] = {"i": i, "ttft_s": None if first is None else round(first - t0, 3),
                  "total_s": round(time.time() - t0, 3), "completion_tokens": ct, "chunks": chunks,
                  "decode_tok_s": round((ct - 1) / span, 1) if ct and span > 0 else None,
                  "chunk_rate": round((chunks - 1) / span, 1) if span > 0 else None,
                  "end_abs": (last or time.time()) - T0}
        with open(f"{outdir}/{tag}-{i}.txt", "w", encoding="utf-8") as fh:
            fh.write("".join(text))
    except Exception as e:
        res[i] = {"i": i, "error": repr(e)}


ts = [threading.Thread(target=one, args=(i,)) for i in range(n)]
for t in ts: t.start()
for t in ts: t.join()
for i in sorted(res):
    r = dict(res[i]); r.pop("end_abs", None)
    print(json.dumps(r, ensure_ascii=False))
ok = [r for r in res.values() if r.get("completion_tokens")]
if ok:
    tot = sum(r["completion_tokens"] for r in ok)
    wall = max(r["end_abs"] for r in ok)
    print(json.dumps({"tag": tag, "n": n, "sum_completion_tokens": tot, "wall_s": round(wall, 2),
                      "aggregate_tok_s_incl_prefill": round(tot / wall, 1),
                      "mean_per_request_decode_tok_s": round(sum(r["decode_tok_s"] or 0 for r in ok) / len(ok), 1)},
                     ensure_ascii=False))

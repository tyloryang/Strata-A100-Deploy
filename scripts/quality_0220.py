import json, random, sys, time, urllib.request

# 用法: quality.py OUTDIR TAG   —— temperature 0 的固定题，检查乱码/截断/重复和长上下文检索
outdir = sys.argv[1]; tag = sys.argv[2]
key = json.load(open("/data/Strata-0.2.20/strata-iq3_xxs.json")).get("api_key", "")

rnd = random.Random(20261123)
nums = [str(rnd.randint(10000, 99999)) for _ in range(5300)]
nums.insert(2650, "（备注：本次实验的密码是 73914。）")
needle = "下面是一串随机数字，中间夹着一句备注。\n" + " ".join(nums) + "\n\n上面的文字里提到的密码是多少？只回答这个数字。"

P = [
    ("math", "计算 37 × 43，写出步骤，最后单独一行给出结果。", 300, ["1591"]),
    ("code", "写一个 Python 函数 is_palindrome(s)，判断字符串是否是回文，忽略大小写和非字母数字字符，并给出两个测试例子。", 500, ["def is_palindrome"]),
    ("explain", "用三句话解释什么是大模型推理里的 KV cache。", 300, []),
    ("translate", "把下面这句话翻译成英文，只输出译文：今天下午三点我们在会议室讨论项目进度。", 100, ["three", "meeting"]),
    ("facts", "列出中国的四个直辖市，用顿号分隔，不要解释。", 60, ["北京", "上海", "天津", "重庆"]),
    ("needle32k", needle, 32, ["73914"]),
]


def ask(content, mt):
    body = {"model": "qwen3.8-flash-next-iq3_xxs", "max_tokens": mt, "temperature": 0, "stream": False,
            "messages": [{"role": "user", "content": content}]}
    req = urllib.request.Request("http://127.0.0.1:8080/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=900) as r:
        d = json.load(r)
    ch = (d.get("choices") or [{}])[0]
    msg = ch.get("message") or {}
    return (msg.get("content") or ""), (msg.get("reasoning_content") or ""), d.get("usage"), ch.get("finish_reason"), time.time() - t0


def uniq10(s):
    sh = [s[k:k + 10] for k in range(max(0, len(s) - 9))]
    return round(len(set(sh)) / len(sh), 3) if sh else None


out = []
for name, content, mt, must in P:
    try:
        c, rc, usage, fin, secs = ask(content, mt)
        text = c + rc
        r = {"name": name, "secs": round(secs, 2), "finish": fin, "usage": usage,
             "checks_ok": all(m in text for m in must), "uniq10": uniq10(text), "content": c, "reasoning": rc}
    except Exception as e:
        r = {"name": name, "error": repr(e)}
    out.append(r)
    show = {k: v for k, v in r.items() if k not in ("content", "reasoning")}
    show["head"] = (r.get("content") or "")[:220].replace("\n", " / ")
    print(json.dumps(show, ensure_ascii=False))

json.dump(out, open(f"{outdir}/{tag}-quality.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("QUALITY-DONE", sum(1 for r in out if r.get("checks_ok")), "of", len(out), "checks ok")

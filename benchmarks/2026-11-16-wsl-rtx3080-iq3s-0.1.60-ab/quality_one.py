#!/usr/bin/env python3
"""6 short quality spot-check prompts (temp 0, max_tokens 512, seed 42). Prints one JSON line each."""
import json
import sys
import urllib.request

URL = "http://127.0.0.1:8080/v1/chat/completions"
PROMPTS = [
    ("math1", "只写数字，不要任何解释：1+2+3+...+100 等于多少？"),
    ("math2", "一个长方形长 12、宽 7，它的周长和面积各是多少？只写两个数字，用逗号分开。"),
    ("code1", "用 Python 写一个函数 is_palindrome(s)，判断字符串忽略大小写和空格后是不是回文。只给代码，不要解释。"),
    ("code2", "指出这段代码的问题并给出修正后的版本：def add(a, b): return a + b；print(add('1', 2))。只给修正后的代码和一句话说明。"),
    ("fact1", "中国的首都是哪里？只写城市名。"),
    ("fact2", "水的化学式是什么？只写化学式。"),
]


def main():
    key = sys.argv[1] if len(sys.argv) > 1 else ""
    for qid, prompt in PROMPTS:
        payload = {"model": "qwen3.8-flash-next-iq3_s",
                   "messages": [{"role": "user", "content": prompt}],
                   "temperature": 0, "top_p": 1, "seed": 42, "max_tokens": 512, "stream": False}
        req = urllib.request.Request(URL, data=json.dumps(payload).encode(),
                                     headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
        try:
            with urllib.request.urlopen(req, timeout=600) as resp:
                obj = json.load(resp)
            ch = obj.get("choices", [{}])[0]
            out = (ch.get("message") or {}).get("content", "")
            usage = obj.get("usage", {})
            rec = {"id": qid, "prompt": prompt, "output": out,
                   "prompt_tokens": usage.get("prompt_tokens"), "completion_tokens": usage.get("completion_tokens")}
        except Exception as e:  # noqa: BLE001 - record, don't crash the batch
            rec = {"id": qid, "prompt": prompt, "error": repr(e)}
        print(json.dumps(rec, ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

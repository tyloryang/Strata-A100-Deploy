#!/usr/bin/env python3
"""One fixed-protocol run against the local Strata server. Prints one JSON line.

Fixed conditions: prompt from prompt.txt, temperature 0, top_p 1, seed 42,
max_tokens 4096, stream. Key is passed as argv[3]; never printed.
"""
import json
import sys
import time
import urllib.request

BASE = "/home/yys/project/bigmodelproject/Strata-official-v0.2.13/runtime/noise-floor"
URL = "http://127.0.0.1:8080/v1/chat/completions"


def main():
    group, run, key = sys.argv[1], sys.argv[2], sys.argv[3]
    prompt = open(f"{BASE}/prompt.txt", encoding="utf-8").read()
    payload = {
        "model": "qwen3.8-flash-next-iq3_s",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0,
        "top_p": 1,
        "seed": 42,
        "max_tokens": 4096,
        "stream": True,
    }
    req = urllib.request.Request(
        URL,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
    )
    t0 = time.monotonic()
    t_first = None
    usage = {}
    content_len = 0
    try:
        with urllib.request.urlopen(req, timeout=1800) as resp:
            for raw in resp:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                try:
                    obj = json.loads(data)
                except json.JSONDecodeError:
                    continue
                if t_first is None:
                    t_first = time.monotonic()
                if "usage" in obj and obj["usage"]:
                    usage = obj["usage"]
                for ch in obj.get("choices", []):
                    d = ch.get("delta", {})
                    if "content" in d and d["content"]:
                        content_len += len(d["content"])
                    if "reasoning_content" in d and d["reasoning_content"]:
                        content_len += len(d["reasoning_content"])
    except Exception as e:  # noqa: BLE001 - record and let the caller decide
        rec = {"group": int(group), "run": int(run), "error": repr(e)}
        print(json.dumps(rec), flush=True)
        return 1
    t_end = time.monotonic()
    comp = usage.get("completion_tokens", 0)
    rec = {
        "group": int(group),
        "run": int(run),
        "prompt_tokens": usage.get("prompt_tokens"),
        "completion_tokens": comp,
        "ttft_s": round(t_first - t0, 3) if t_first else None,
        "total_s": round(t_end - t0, 3),
        "decode_tps": round(comp / (t_end - t_first), 3) if t_first and comp else None,
        "e2e_tps": round(comp / (t_end - t0), 3) if comp else None,
        "content_chars": content_len,
    }
    print(json.dumps(rec), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

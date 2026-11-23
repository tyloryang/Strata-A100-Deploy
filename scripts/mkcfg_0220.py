import json
import os
import sys

SRC = "/data/Strata/strata-iq3_xxs.json"
DST = "/data/Strata-0.2.20/strata-iq3_xxs.json"

if os.path.exists(DST):
    print("DST exists, not overwriting:", DST)
    sys.exit(1)

old = json.load(open(SRC, encoding="utf-8"))
new = json.loads(json.dumps(old))
new["exe"] = "/data/Strata-0.2.20/engine-cuda12/strata"
new["cwd"] = "/data/Strata-0.2.20"
new["log"] = "/data/Strata-0.2.20/strata-iq3_xxs.log"
new["lib_dirs"] = ["/data/Strata-0.2.20/engine-cuda12"]

with open(DST, "w", encoding="utf-8") as fh:
    json.dump(new, fh, ensure_ascii=False, indent=2)

print("== changed keys")
for k in sorted(set(old) | set(new)):
    if old.get(k) != new.get(k):
        print(f"  {k}: {old.get(k)!r} -> {new.get(k)!r}")
print("== unchanged keys:", ", ".join(k for k in old if old.get(k) == new.get(k)))

print("== leftover references to old dir /data/Strata/ :")
s = json.dumps(new, ensure_ascii=False)
left = [t for t in s.split('"') if t.startswith("/data/Strata/")]
print("  ", left or "none")

masked = dict(new)
if masked.get("api_key"):
    masked["api_key"] = "***"
print("== args:", masked.get("args"))
print("== env:", masked.get("env"))
print("MKCFG-OK")

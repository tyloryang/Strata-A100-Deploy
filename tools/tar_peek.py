import os
import sys


def parse_size(raw: bytes) -> int:
    if raw and (raw[0] & 0x80):
        return int.from_bytes(bytes([raw[0] & 0x7F]) + raw[1:], "big")
    return int(raw.strip(b"\0 ") or b"0", 8)


def main(path: str) -> None:
    total = os.path.getsize(path)
    off = 0
    rows = []
    with open(path, "rb") as fh:
        while off + 512 <= total:
            fh.seek(off)
            h = fh.read(512)
            if h == b"\0" * 512:
                break
            name = h[0:100].rstrip(b"\0").decode("utf-8", "replace")
            prefix = h[345:500].rstrip(b"\0").decode("utf-8", "replace")
            size = parse_size(h[124:136])
            typ = h[156:157].decode("latin-1")
            link = h[157:257].rstrip(b"\0").decode("utf-8", "replace")
            full = f"{prefix}/{name}" if prefix else name
            rows.append((typ, size, full, link))
            off += 512 + ((size + 511) // 512) * 512
    print(f"container bytes: {total:,}")
    for typ, size, full, link in rows:
        extra = f" -> {link}" if link else ""
        print(f"{typ:2} {size:>14,}  {full}{extra}")


if __name__ == "__main__":
    main(sys.argv[1])

#!/usr/bin/env python3
"""在远程主机上执行命令（密码认证），用于本仓库的批量运维。

凭据全部来自环境变量，不写入命令行、不写入历史：

    export DSH_SSH_HOST=203.0.113.10
    export DSH_SSH_PORT=22
    export DSH_SSH_USER=root
    export DSH_SSH_PASS='...'          # 也可用 DSH_SSH_KEY 指定私钥路径

    python rexec.py "nvidia-smi" "docker ps"
    python rexec.py --put docker-compose.yml:/tmp/dc.yml "docker-compose -f /tmp/dc.yml config"

每个参数作为一条独立命令（bash -lc）执行，逐条打印输出与退出码。
"""

import argparse
import os
import sys
import time

import paramiko

ROOT_BANNER = "\n===== $ "


def _utf8_stdio() -> None:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:  # noqa: BLE001
            pass


def run(client: paramiko.SSHClient, cmd: str, timeout: float) -> int:
    print(f"{ROOT_BANNER}{cmd}", flush=True)
    started = time.time()
    try:
        _, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    except Exception as exc:  # noqa: BLE001
        print(f"[exec failed] {exc}", file=sys.stderr, flush=True)
        return 255
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    rc = stdout.channel.recv_exit_status()
    if out:
        sys.stdout.write(out if out.endswith("\n") else out + "\n")
    if err:
        sys.stderr.write(err if err.endswith("\n") else err + "\n")
    print(f"----- exit={rc} elapsed={time.time() - started:.2f}s", flush=True)
    return rc


def connect(args) -> paramiko.SSHClient:
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    kwargs = dict(
        hostname=args.host,
        port=args.port,
        username=args.user,
        timeout=args.connect_timeout,
        banner_timeout=args.connect_timeout,
        auth_timeout=args.connect_timeout,
        look_for_keys=False,
        allow_agent=False,
    )
    if args.key:
        kwargs["key_filename"] = args.key
        kwargs["look_for_keys"] = True
    else:
        kwargs["password"] = args.password

    # sshd 偶尔在握手阶段直接断开（读不到 banner），重试即可
    last = None
    for attempt in range(1, 6):
        try:
            client.connect(**kwargs)
            return client
        except (paramiko.ssh_exception.SSHException, EOFError, OSError) as exc:
            last = exc
            print(f"[connect retry {attempt}/5] {type(exc).__name__}: {exc}", file=sys.stderr, flush=True)
            time.sleep(3 * attempt)
    raise last  # type: ignore[misc]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("commands", nargs="*")
    ap.add_argument("--host", default=os.environ.get("DSH_SSH_HOST"))
    ap.add_argument("--port", type=int, default=int(os.environ.get("DSH_SSH_PORT", "22")))
    ap.add_argument("--user", default=os.environ.get("DSH_SSH_USER", "root"))
    ap.add_argument("--password", default=os.environ.get("DSH_SSH_PASS"))
    ap.add_argument("--key", default=os.environ.get("DSH_SSH_KEY"))
    ap.add_argument("--connect-timeout", type=float, default=20.0)
    ap.add_argument("--timeout", type=float, default=300.0, help="单条命令超时（秒）")
    ap.add_argument("--put", action="append", default=[], metavar="LOCAL:/abs/remote")
    args = ap.parse_args()
    _utf8_stdio()

    if not args.host:
        ap.error("缺少 --host 或 DSH_SSH_HOST")
    if not args.password and not args.key:
        ap.error("缺少 --password/DSH_SSH_PASS 或 --key/DSH_SSH_KEY")
    if not args.commands and not args.put:
        ap.error("没有要执行的命令")

    client = connect(args)
    try:
        if args.put:
            sftp = client.open_sftp()
            try:
                for pair in args.put:
                    idx = pair.find(":/")
                    if idx < 0:
                        raise SystemExit(f"--put 需要 LOCAL:/abs/remote，收到 {pair!r}")
                    local, remote = pair[:idx], pair[idx + 1:]
                    sftp.put(local, remote)
                    print(f"[uploaded] {local} -> {remote}", flush=True)
            finally:
                sftp.close()

        last = 0
        for cmd in args.commands:
            rc = run(client, cmd, args.timeout)
            if rc != 0:
                last = rc
        return last
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())

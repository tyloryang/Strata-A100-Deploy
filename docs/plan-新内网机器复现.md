# Strata + Qwen3.8-Flash-Next IQ3_XXS 离线包：新内网机器复现计划

> 依据：《离线环境部署手册（2 × A100 40GB PCIe）》（F:\strata_pack_offline，本文简称"手册"）
> 执行机：<公网IP>:<SSH端口>（root），CentOS 7 + 2 × A100-SXM4-40GB
> 计划制定：2026-11-02 00:00 CST　｜　定时验证启动：2026-11-02 03:00 CST
> 说明：本文件是"怎么在新机器上跑起来"的可执行计划；实际执行结果另记在《执行记录》里。

---

## 0. 目的与通过判据

用一份 198GB 的离线包，在一台**完全无外网**的机器上把 Strata 引擎 + Qwen3.8-Flash-Next IQ3_XXS 跑起来，双卡、262144 上下文、8080 端口、API Key 鉴权、局域网可访问。

**整体通过判据（缺一不可）**

1. 5 个 tar 的 `sha256sum -c` 全过，2 个 GGUF 的 SHA256 等于手册固定值。
2. `docker load` 成功；容器内 Python 3.12.16；`ldd strata` 无 `not found`。
3. 启动日志出现 `ready:`，记录 layer split 与专家缓存数量。
4. `/health` 返回 `api_key: true`、`loaded: true`。
5. 无 Key 访问 `/v1/models` 得 401，带 Key 得 200。
6. `/v1/chat/completions` 返回通顺中文，`finish_reason=stop`。
7. `nvidia-smi` 两张卡都有显存占用；`docker stop` 后显存释放。
8. 全流程命令与输出有记录，可在另一台机器照抄复现。

---

## 1. 目标机基线

### 1.1 本机实测（2026-11-01 23:47）

| 项 | 本机实际 | 手册描述的目标机 | 判断 |
| --- | --- | --- | --- |
| GPU | 2 × A100-SXM4-40GB（40960 MiB，sm80，ECC 开，MIG 关） | 2 × A100-PCIE-40GB | 可用，显存一致 |
| 驱动 | **550.78**（CUDA 12.4 运行时） | 535.104.12（CUDA 12.2） | 更优：不需要升级驱动 |
| 系统 | **CentOS 7**（3.10.0-1160） | EL8 / CentOS 8 | 可用，Docker 20.10.17 已在 |
| 内存 | **94 GiB** + 8 GiB swap | 560 GB | **最大变量**，需盯紧 |
| CPU | 32 vCPU Xeon 8368Q，1 NUMA | 未记录 | 可用 |
| 磁盘 | `/data` = `/dev/vdb` 985G ext4，可用 930G | /data 2.0T，剩 1.3T | 够用（包 198G + 解开约 130G） |
| 根分区 | 192G，可用 172G | /opt 剩 9G | 拉镜像/解包都要走 /data |
| Docker | 20.10.17，已注册 nvidia runtime，容器内可见双卡 | 已装，带 nvidia runtime | 一致 |
| 网络 | 单网口 `ens3` <内网IP>/24（libvirt NAT 网段） | 内网 IP | **注意**：这是 NAT 地址，外部局域网默认访问不到 |
| 现有负载 | 无 vLLM 容器，8080 空闲 | 需先停 qwen3.8-27b | 无冲突 |

### 1.2 由此带来的三个偏差处置

1. **内存只有 94GB**：手册按 560GB 设计（专家层放内存）。2 × 40GB 显存要尽量把约 40GiB 专家全塞进显存；启动后先看日志里的专家缓存数量，**接近 24576 = 全部在显存**，内存压力才可控。若日志显示大量专家落内存，把 `--context` 从 262144 降到 131072 或 65536，或加 `--kv q4_0` 省 KV。
2. **网络是 <内网网段>/24（NAT）**：手册要求 `-p <内网IP>:8080:8080`。按本机现状只能绑 <内网IP>；要让外部局域网访问，需要在宿主机做端口转发/桥接，属于部署之外的网络配置，验收时按"本机 + NAT 网段内可达"判定，外部可达另记。
3. **CentOS 7 内核 3.10**：Docker 20.10 + nvidia-container-cli 1.10 已正常工作（实测容器内 `nvidia-smi` 看到双卡），预期无阻塞；`--security-opt label=disable` 仍保留，避免 SELinux 干扰。

### 1.3 容量与内存预算

- 包体 198GB + 解开后约 130GB（pack 44G、mtp 6.9G、GGUF 75.8G、源码/工具/venv 约 4G）≈ 330GB，`/data` 930G 够。校验通过后可删 tar 回收 198GB。
- 显存：专家约 40GiB + 稠密权重 2×1.5GiB + KV（262144/int8 约 3.6GB/槽）+ 缓冲，**单槽约 76GB**，80GB 显存刚好；开 parallel 必须走 `--kv q4_0` 或 `--kv-streaming on`。
- 内存：先把包读一遍预热页缓存（`cat ... > /dev/null`），可让后续重启快很多。

---

## 2. 交付物与校验值

| 文件 | 字节 | SHA256 | 还原到 |
| --- | --- | --- | --- |
| strata-qwen38-cuda12-1.0.tar | 7,630,861,312 | `cad3fffce7cfb927f1f088498dd2fe3ac0f466b0c769850392cfb0d53dbb7893` | `docker load` |
| strata-src.tar | 932,792,320 | `75b58551adb3e30c476f761dcdfc266557bd260e78238e9853beb29a04118cc8` | `$BASE/` → Strata |
| tools.tar | 1,217,095,680 | `c4e8ee2779dbf67c213aac694493fcb989aa072511678abebc4d3e6e2de13bbe` | `$BASE/` → tools |
| data-packs.tar | 44,460,963,840 | `63cc232f7100fcde11531364c2957d7838f8cbefdcb6917d2524e276cf2a4d9d` | `$BASE/Strata-data/` |
| data-mtp.tar | 6,927,687,680 | `7b00c76af8fe186800e8d668ae32cfe2a06b6c9f4a875a90526c98d69291712c` | `$BASE/Strata-data/` |
| Qwen3.8-...-IQ3_XXS-00001-of-00002.gguf | 47,039,860,096 | `219ea929900dfa9ef091f3aa473fdba6874b65fcb36526d7d851ac9e95856d15` | `$BASE/Strata-data/models/IQ3_XXS/` |
| Qwen3.8-...-IQ3_XXS-00002-of-00002.gguf | 28,800,138,432 | `316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113` | 同上 |
| gguf_done.tar | 286 | —（条目无目录前缀） | `-C .../models/IQ3_XXS` |
| SHA256SUMS-tars.txt | 412 | — | 任意（校验用） |

变量：`PK=/data`、`BASE=/data/qwen-strata`、`IMG=strata-qwen38:cuda12-1.0`、`BIND_IP=0.0.0.0`（平台已转发 公网 13270 → VM 8800，因此发布 8800）。

> 本机实际上传的 `Qwen3.8-...-00002-of-00002.tar`（75,840,001,024 字节）是**两个 GGUF 的打包**（47,039,860,096 + 28,800,138,432 + tar 头），解包后得到上表两片 GGUF，不再单独传 .gguf。

---

## 3. 执行计划

每阶段都有**门禁**：不通过就停，按"退路"处置，不带着问题进下一阶段。时间预算按 14.5 MB/s 上传 + 本地 SSD 读写估算。

### 阶段 A：传输与校验（预计 03:00 前完成上传，校验 20–40 min）

```bash
# A1 上传完成判定：无 .filepart，且各文件字节数与上表一致
ls -l /data; ls /data/*.filepart 2>/dev/null | wc -l

# A2 tar 校验（5 个，198GB，约 15–25 min）
cd /data && sha256sum -c SHA256SUMS-tars.txt

# A3 解出 GGUF 后再校验模型（两片各 47G/28.8G，约 10–15 min）
sha256sum /data/qwen-strata/Strata-data/models/IQ3_XXS/*.gguf
```

**门禁**：A2 五行全 `OK`；A3 两行与固定值逐字相同。
**退路**：任一不符 → 立即停，重传该文件；不要用 `--ignore` 或改清单。

### 阶段 B：解包与镜像（预计 40–70 min）

```bash
mkdir -p $BASE
tar -xf /data/strata-src.tar   -C $BASE
tar -xf /data/tools.tar        -C $BASE
tar -xf /data/data-packs.tar   -C $BASE/Strata-data
tar -xf /data/data-mtp.tar     -C $BASE/Strata-data
mkdir -p $BASE/Strata-data/models/IQ3_XXS
tar -xf /data/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00002-of-00002.tar -C $BASE/Strata-data/models/IQ3_XXS
tar -xf /data/gguf_done.tar    -C $BASE/Strata-data/models/IQ3_XXS   # 条目无目录前缀
docker load -i /data/strata-qwen38-cuda12-1.0.tar
```

**门禁**：`ls $BASE` 见 Strata、tools、Strata-data；`models/IQ3_XXS` 里 2 个 .gguf + 2 个 71 字节 .done；`docker images` 有 `strata-qwen38:cuda12-1.0`。
**退路**：解包中断就重跑（tar 可重复解）；`.done` 文件名对不上 GGUF 时按"GGUF 名 + .done"手工改名。

### 阶段 C：镜像自检（10 min）

```bash
docker run --rm --gpus '"device=0,1"' $IMG nvidia-smi -L
docker run --rm -v $BASE:/data $IMG /data/Strata/.venv/bin/python --version
docker run --rm -v $BASE:/data $IMG bash -c 'ldd /data/Strata/engine-cuda12/strata | grep "not found"; echo ldd-done'
```

**门禁**：两张卡列出；Python 3.12.16；`ldd-done` 之前无输出。
**退路**：容器拒绝启动 → 加 `-e NVIDIA_DISABLE_REQUIRE=true`；`ldd` 报缺库 → 停，记录库名，回云主机补包。

### 阶段 D：生成双卡配置 + API Key（15–30 min，最大未知项）

```bash
cp $BASE/Strata/strata-iq3_xxs.json $BASE/Strata/strata-iq3_xxs.json.cloud80g
install -d -m 700 /etc/strata
KEY=$(openssl rand -hex 24)
printf '%s' "$KEY" | tee /etc/strata/api_key >/dev/null && chmod 600 /etc/strata/api_key
# setup 用脚本文件执行，Key 从文件读，不出现在命令行/日志里
bash /root/offline_check/setup_offline.sh
chmod 600 $BASE/Strata/strata-iq3_xxs.json
grep -n '"gpu"\|layer_split' $BASE/Strata/strata-iq3_xxs.json
```

setup 脚本内容（等价手册 5.4，去掉 `--build`，Key 由文件读入）：

```bash
docker run --rm --gpus '"device=0,1"' -e KEY="$(cat /etc/strata/api_key)" \
  --security-opt label=disable --ulimit memlock=-1:-1 -v $BASE:/data $IMG \
  bash -c 'cd /data/Strata && ./setup.sh --setup --no-start --yes --cuda 12 --model IQ3_XXS \
    --gpus 0,1 --vision no --context 262144 --no-browser --host 0.0.0.0 \
    --api-key "$KEY" --data-dir /data/Strata-data --models-dir /data/Strata-data/models' \
  2>&1 | tee /root/offline_check/setup-offline.log
```

**门禁**：配置里 `"gpu": [0, 1]`、`layer_split` 存在；文件权限 600。
**退路**：断网下 setup 失败（pip/下载步骤）→ **不重试**，保存日志，手工改 JSON：`"gpu": [0,1]`、`"layer_split": "auto"`、`"api_key"`，并在 `run-iq3_xxs.sh` 末尾加 `"--host" "0.0.0.0"`。

### 阶段 E：启动与就绪（加载 3–5 min，94GB 内存下可能更久）

```bash
docker run -d --name strata --restart unless-stopped --gpus '"device=0,1"' \
  --ulimit memlock=-1:-1 --shm-size 2g --stop-timeout 120 \
  --security-opt label=disable -p <内网IP>:8080:8080 \
  -v $BASE:/data $IMG /data/Strata/run-iq3_xxs.sh
docker logs -f strata   # 等 ready:
```

**门禁**：日志出现 `ready:`；记录 `layer split` 行与专家缓存数量；`nvidia-smi` 两卡显存上涨。
**退路**：双卡启动失败 → 退回单卡（setup `--gpu 0`，容器 `device=0`）；`loaded` 一直 false → 查内存是否换页（`free -h`、`vmstat 1`）。

### 阶段 E-2：docker-compose 启动方式（日常推荐，已实测）

先用 `docker run` 跑通一次（阶段 E），确认镜像和配置没问题，再切 compose。compose 只是把同一份参数写成文件，方便启停和巡检。

**前置门禁：compose 必须在交付包里**

```bash
docker compose version || docker-compose version
```

两个都没有时，**不要在内网机临时安装**（离线装不了，且会引入系统包变更）：

- 首选：把官方 v2 独立二进制预先放进交付包，解到 `/usr/local/bin/docker-compose`（单文件，无依赖，60 MB 左右）；要支持 `docker compose` 写法就放到 `/usr/libexec/docker/cli-plugins/docker-compose`。
- 退路：继续用阶段 E 的 `docker run`，两者功能等价。

本次验证用的是 `v2.29.7` 的 `docker-compose-linux-x86_64`，在 Docker 20.10.17 / CentOS 7 上正常工作。

**文件**（`$BASE` 用回原变量，`/data/compose/strata` 与 `$BASE` 必须在同一块盘上或至少可用）：

```bash
mkdir -p /data/compose/strata && cd /data/compose/strata
cat > .env <<'EOF'
BASE=/data/qwen-strata
BIND_IP=0.0.0.0
EOF
```

`docker-compose.yml`：

```yaml
services:
  strata:
    image: strata-qwen38:cuda12-1.0
    container_name: strata
    restart: unless-stopped
    init: true
    command: ['/data/Strata/run-iq3_xxs.sh']
    ports:
      - '${BIND_IP}:8800:8080'
    volumes:
      - '${BASE}:/data'
    shm_size: 2g
    ulimits:
      memlock: {soft: -1, hard: -1}
    stop_grace_period: 120s
    security_opt: [label=disable]
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ['0', '1']
              capabilities: [gpu]
    healthcheck:
      test: ['CMD-SHELL', 'curl -fsS http://127.0.0.1:8080/health | grep -Eq loaded.:.true']
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 300s
```

要点：

- `init: true` 是本次补充项（原手册没有），给容器一个会回收孤儿的 PID 1。它**不能**解决 8bis.5 说的强删卡死，但服务端会 spawn 引擎子进程，加上更稳。
- `deploy.resources.reservations.devices` 需要 compose v2（v1 会忽略，容器里就看不到卡）。
- 健康检查在容器内跑 `curl 127.0.0.1:8080`，容器内监听 `0.0.0.0` 所以可用；宿主上的 `127.0.0.1:8080` 不可用（端口只绑内网 IP）。
- `start_period: 300s` 是给冷加载留的余量，实测 65 秒就 healthy。

**端口与访问（最容易搞错的地方）**

三层地址分开看：

| 层 | 值 | 改哪里 |
| --- | --- | --- |
| 容器内服务监听 | `0.0.0.0:8080` | `strata-iq3_xxs.json` 的 `"host"` / `"port"`（或重跑 setup 的 `--host`/`--port`） |
| 宿主发布映射 | `0.0.0.0:8800->8080` | compose 的 `'${BIND_IP}:8800:8080'`；`-p A:B` 中 A 是宿主端口、B 是容器端口 |
| 外部访问 | 平台转发 `公网 13270 -> VM 8800` | 虚拟化平台控制台，VM 内改不了 |

**先问平台要端口，再决定发布端口**。本机平台预留了 6 组（控制台"预留端口"页）：

| 公网端口 | VM 端口 |
| --- | --- |
| 13270 | **8800** |
| 13271 | 8801 |
| 13272 | 8802 |
| 13273 | 8803 |
| 13274 | 8804 |
| 13275 | 8805 |

公网地址两条：`<公网IP>`（移动）、`<公网IP-电信>`（电信）。所以 compose 发布 `8800`，公网访问 `http://<公网IP>:13270/`。**发布端口不落在这 6 个里，公网永远不通**——这跟容器、镜像、Strata 都没关系。

最终链路与已验证结果：

```
公网 13270 → VM 8800 → 容器 8080
GET http://<公网IP>:13270/health   → 200  {"status":"ok",...,"loaded":true}
GET http://<公网IP>:13270/         → 200  text/html 16,960B  <title>Strata</title>
GET http://<公网IP>:13270/v1/models 无 Key → 401
```

- `BIND_IP=0.0.0.0` 会让端口暴露在所有网卡上（含 docker0/virbr0）；手册原意是只绑内网 IP 以缩小暴露面。要按手册收紧就写 `<内网IP>`，要图省事就 `0.0.0.0`——API 有 Key 保护，但暴露面确实变大。注意：经平台转发到公网后，暴露面由平台端口决定，与 `BIND_IP` 无关。
- 只用 compose 改 published 端口而容器内还是 8080 时，映射写成 `8800:8080` 即可，不要以为写错；`docker port` 会显示 `8080/tcp -> 0.0.0.0:8800`。
- **Web 页面是 `GET /`**，`/v1` 只是 API 前缀，浏览器直接开 `http://<IP>:13270/v1` 会得到 404，这是正常的，不是服务坏了。
- 容器日志里的 `open http://127.0.0.1:8080/` 与 `from other devices: http://172.x.x.x:8080/` 是服务在容器内自己算的提示（`serve/server.py` 里 `host=0.0.0.0` 时把 `here` 写死成 127.0.0.1，另一个是容器的桥接 IP，重建网络还会变），**不能当访问地址**。
- 验收端口时按这个顺序查，能一步定位问题层：`docker-compose config | grep -A6 ports` → `docker port strata` → `ss -ltnp | grep <端口>` → `curl -I http://<宿主IP>:<端口>/health` → 最后才从公网测。

**切换步骤**

```bash
docker-compose config            # 先校验：host_ip / device_ids / 挂载 是否解析正确
docker stop strata               # 关键：必须优雅停，不要 rm -f（见下）
docker rm -f strata              # 只有在容器已 Exited 后才安全
docker-compose up -d
docker-compose ps                # 看 (healthy)
```

`up -d` 4 秒返回，65 秒 healthy。

**生命周期实测值（可直接作为验收门禁）**

| 命令 | 耗时 | 结果 |
| --- | --- | --- |
| `docker-compose up -d` | 4 秒返回 / 65 秒 healthy | 正常 |
| `docker-compose restart` | 77 秒 healthy | 正常 |
| `docker-compose stop` | 13 秒 | 显存释放到 1 MiB |
| `docker-compose start` | 65 秒 healthy | 显存恢复 |
| `docker-compose down` | 13 秒 | 删容器+网络，数据不动 |
| `docker-compose ps` | 即时 | `(healthy)` |

**必须记住的坑：不要对运行中的容器 `docker rm -f`**

两次实测都失败：无 `init` 时报 `PID ... is zombie and can not be killed`；有 `init` 时报 `tried to kill container, but did not receive an exit event`。原因是引擎持有 CUDA 上下文，SIGKILL 后要拆 GPU 上下文，进程进入不可中断状态，超过 docker 10 秒的等待就报错，容器留在不一致状态、服务中断。

正确做法：`docker-compose stop`（13 秒）→ `docker-compose down` → `docker-compose up -d`。真卡死了就等它自己变 `Exited (137)`（实测约 5 分钟）再删。

---

### 阶段 F：验收（10 min）

```bash
KEY=$(cat /etc/strata/api_key)
curl -s http://127.0.0.1:8080/health
curl -s -o /dev/null -w '%{http_code}\n' http://<内网IP>:8080/v1/models
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $KEY" http://<内网IP>:8080/v1/models
curl -s http://<内网IP>:8080/v1/chat/completions -H "Authorization: Bearer $KEY" \
  -H 'Content-Type: application/json' \
  -d '{"model":"x","messages":[{"role":"user","content":"用一句话说明什么是TCP三次握手。"}],"max_tokens":200,"temperature":0,"reasoning_effort":"none"}'
nvidia-smi
```

预期：`api_key/loaded` 均 true；401 → 200；推理返回中文且 `finish_reason=stop`；两卡都有占用。

### 阶段 G：可复现性归档

- 保留 `/root/offline_check/` 下的：上传状态、各阶段日志、`docker images`、`free -h`、`nvidia-smi`、配置 JSON（打码 Key）、验收响应原文。
- 记录**本机与手册的差异项实际影响**（驱动 550 vs 535、CentOS 7、94GB 内存、NAT 网段），这是"能否在新内网机器跑"的核心结论。
- 产出《执行记录》，把每步的实际耗时、输出、异常与处置都写进去。

---

## 4. 定时任务

| 时间（CST） | 动作 |
| --- | --- |
| 00:00 | 上传监控已启动（`/root/offline_check/watch_upload.sh`，60s 一次写状态） |
| 03:00 | 定时任务触发：开始阶段 A 校验 |
| 03:00–06:00 | 阶段 A→G 执行，边做边记 |
| 06:00 | 交付：执行记录 + 结论（能否在新内网机器复现）+ 遗留项 |

---

## 5. 风险登记

| 风险 | 触发信号 | 处置 |
| --- | --- | --- |
| 内存不足（94GB，手册按 560GB 写） | 启动日志专家大量落内存、`free` 见 swap 增长、`vmstat` 有换页 | 降 `--context` 到 131072/65536；`--kv q4_0`；必要时 `--low-ram` |
| 262144 上下文 + 40GB 卡放不下 | 启动 OOM 或层拆分失衡 | 先 `--context 131072` 跑通，再逐级加 |
| 断网下 setup 失败 | pip、curl、下载报错 | 手册退路：手工改 JSON，不重试 |
| 75.8GB tar 解包占空间 | `df` 逼近满 | 解包前确认剩余 ≥ 180G；解完删 tar |
| 上传不完整/被改名 | 无 .filepart 但字节数不符 | 只重传该文件，校验值不符一律不用 |
| NAT 网段外部不可达 | 局域网另一台机器连 <内网IP> 超时 | 交付时标注：需宿主机端口转发，非本包问题 |
| 驱动 550 与引擎 ABI | 容器拒绝启动/报驱动过旧 | 实测 550 ≥ 535 要求，预期可用；真报错再升级驱动或回 CUDA 12.2 重编 |

---

## 6. 回滚

- 只回滚服务，不动数据：`docker rm -f strata`，配置用 `strata-iq3_xxs.json.cloud80g` 覆盖回去。
- 完全回滚：停容器 → 删 `$BASE` → `docker rmi strata-qwen38:cuda12-1.0` → 重新从阶段 B 开始。
- 不删原始 tar，直到阶段 F 全过。

---

## 8. 实测结果回填（2026-11-02 02:23，本机实跑）

计划已在本机按 A→G 全部执行完毕，结论与偏差如下（详见 `执行记录.md`）：

| 阶段 | 计划耗时 | 实测耗时 | 结果 |
| --- | --- | --- | --- |
| A 校验 | 20–40 min | 57 s（5 tar）+ 77 s（2 GGUF） | 全过 |
| B 解包 + docker load | 40–70 min | 约 5 min（含 42G packs、75.8G 模型、7.6G 镜像） | 全过 |
| C 自检 | 10 min | 10 s | 过（Python 实为 3.10.12） |
| D 配置生成 | 15–30 min | 49 s，断网无请求 | 过 |
| E 启动 | 3–5 min | 70 s（首次）/ 54 s（重启） | 过 |
| F 验收 | 10 min | 约 2 min | 全过 |

关键实测值：解码 106–123 tok/s、1460 token 预填 1335 tok/s、显存 26.6+32.7 GiB、内存 44G/94G 用、swap 5 MB、专家缓存 12288（17.72 GiB）。

三处偏差均已确认不影响复现，但文档要改：容器内 Python 是 3.10.12 不是 3.12.16；`/health` 必须用绑定的内网 IP（127.0.0.1 不通）；本机驱动 550.78 高于手册的 535，第 10 节"驱动过旧"风险不存在。局域网外部可达需宿主机做 NAT 转发，未验。

---

## 7. 执行记录模板

| 阶段 | 开始 | 结束 | 耗时 | 结果 | 关键输出 | 异常/处置 |
| --- | --- | --- | --- | --- | --- | --- |
| A 校验 | | | | | | |
| B 解包 | | | | | | |
| C 自检 | | | | | | |
| D 配置 | | | | | | |
| E 启动 | | | | | | |
| F 验收 | | | | | | |

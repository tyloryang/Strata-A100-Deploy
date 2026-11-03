# Strata + Qwen3.8-Flash-Next IQ3_XXS · 2×A100 离线部署

在**完全无外网**的 2 × A100-40GB 机器上，用一份约 137 GB 的离线包部署 [Strata](https://github.com/Niko1221/Strata) 推理引擎和 Qwen3.8-Flash-Next IQ3_XXS：双卡层拆分、262144 上下文、OpenAI / Anthropic 兼容 API、API Key 鉴权、Web 聊天页。

这个仓库记录的是**一次真实部署和 14 轮调优的全过程**，包括可直接使用的配置、脚本和复现手册。离线包本身不在仓库里。

> ⚠️ 测试机已于 2026-11-02 23:40 回收，所有实测数据都来自那台机器，之后没有新数据。

---

## 我想……

| 我想 | 看这里 |
|---|---|
| 照着部署一套 | [快速开始](#快速开始) → [部署文档](docs/部署文档.md) |
| 知道某个参数是什么意思、在本机有没有用 | [参数详解](docs/参数详解.md) |
| 直接拿配置文件 | [`deploy/`](deploy/README.md) |
| 看性能数据、复现压测 | [压测文档](docs/压测文档.md)，14 个版本的总表在[部署文档 §12](docs/部署文档.md#12-参数演化与实测汇总历史存档) |
| 值班、排障 | [运维卡片](docs/运维卡片.md) |
| 迁到另一台机器 | [目标机迁移清单](docs/目标机迁移清单.md)（未执行） |
| 了解脚本怎么用 | [`scripts/README.md`](scripts/README.md) |
| 部署 IQ3_S、Coder 或 vLLM 27B | [待实施-其他模型](待实施-其他模型/README.md)（**都未部署、未验证**） |

---

## 结果

| 项 | 实测 |
|---|---|
| 部署耗时 | 传输完成到服务就绪 **8 分钟**；`setup.sh` 断网 49 秒，零网络请求 |
| 显存 | 层拆分 CUDA0 跑第 0–23 层、CUDA1 跑第 24–47 层；**全部 24576 个专家都在显存** |
| 单请求解码 | **105–111 tok/s**（TPOT 约 9 ms） |
| 长提示并发（in=2000，4 槽，并发 8） | 聚合 **59.5 tok/s**，TPOT 45.9 ms |
| 短提示并发（in≈800，8 槽，并发 8） | 聚合 **89.3 tok/s**，TPOT 71.4 ms |
| 长上下文 | 200K 提示 TTFT 39 秒，预填约 5100 tok/s；超长请求返回 400，从不截断 |
| 停启 | `stop` 13 秒释放显存，`up -d` 65 秒 healthy |

**结论**：没有免费扩容。并发越高，单个请求越慢；4 槽在长提示下全面最优，8 槽只在短提示、高并发时聚合更高。

---

## 推荐配置

| 场景 | 文件 | 对应实测版本 |
|---|---|---|
| 长提示 / 文档分析（**默认**） | [`deploy/strata-iq3_xxs.recommended.json`](deploy/strata-iq3_xxs.recommended.json) | v6，4 槽 |
| 短提示 / 高并发问答 | [`deploy/strata-iq3_xxs.recommended-8slot.json`](deploy/strata-iq3_xxs.recommended-8slot.json) | v5，8 槽 |

两份只差 `parallel`、`--batch`、`--conversation-cache-slots` 三处。

核心取舍：

| 参数 | 取值 | 为什么 |
|---|---|---|
| `--kv-resident` | 32768 | **必留**。去掉后显存被推到 99%，并发 8 吞吐崩 35% |
| `--ple-io` | `mmap` | 和 `ram` 性能相同，但不会锁死 26.8 GiB 内存 |
| `--resident-experts` | 开 | 引擎内存占用 61.7 → 39.3 GiB，显存不变 |
| `--batch-mtp` | 不加 | 双卡层拆分下会被引擎关掉；强制串行实测慢 16–20% |

> **ESP（实验性速度投影）可选，默认关闭。** 向量照常加载，但请求默认不用它，输出和原模型逐 token 一致。需要时可以按单个请求或在 Web 聊天页按对话打开。注意它**不是提速功能**：官方说明它是**拒答方向投影**，开启后模型拒答大幅减少，等于去掉一层安全行为，每 token 还会慢 0.2–0.4%。上面的 v6/v5 数据是在 ESP 开启时测的。详见[参数详解 §2.7](docs/参数详解.md#27-esp-控制向量先读这一节)。

---

## 快速开始

**前置条件**：2 × A100（sm80）、驱动 ≥ 525、docker + nvidia runtime、compose v2 二进制（离线机要提前放好）、内存 ≥ 94 GB、`/data` ≥ 400 GB。

```bash
# 1. 校验离线包（约 1 分钟）
cd /data && sha256sum -c SHA256SUMS-tars.txt

# 2. 解包、导入镜像
B=/data/qwen-strata
mkdir -p $B/Strata-data/models/IQ3_XXS
tar -xf strata-src.tar -C $B && tar -xf tools.tar -C $B
tar -xf data-packs.tar -C $B/Strata-data && tar -xf data-mtp.tar -C $B/Strata-data
tar -xf Qwen3.8-*-00002-of-00002.tar -C $B/Strata-data/models/IQ3_XXS
tar -xf gguf_done.tar -C $B/Strata-data/models/IQ3_XXS
docker load -i strata-qwen38-cuda12-1.0.tar

# 3. 生成 API Key（存文件，不进命令行和日志）
install -d -m 700 /etc/strata
openssl rand -hex 24 > /etc/strata/api_key && chmod 600 /etc/strata/api_key

# 4. 断网跑 setup，生成启动脚本和基础配置
#    脚本里的 BASE / 镜像名按实际改；不要加 --calibrate（见下方"踩坑"第 4 条）
bash scripts/setup_offline.sh

# 5. 换成推荐配置并填入 Key
cp deploy/strata-iq3_xxs.recommended.json $B/Strata/strata-iq3_xxs.json
python3 - <<'EOF'
import json; p = '/data/qwen-strata/Strata/strata-iq3_xxs.json'
c = json.load(open(p)); c['api_key'] = open('/etc/strata/api_key').read().strip()
json.dump(c, open(p, 'w'), ensure_ascii=False, indent=2)
EOF
chmod 600 $B/Strata/strata-iq3_xxs.json

# 6. 用 compose 启动（约 65 秒到 healthy）
mkdir -p /data/compose/strata
cp deploy/docker-compose.yml /data/compose/strata/
cp deploy/.env.example /data/compose/strata/.env
cd /data/compose/strata && docker-compose up -d && docker-compose ps

# 7. 验收
bash scripts/accept.sh
```

**验收标准**：
- `/health` 返回 `loaded: true`；
- 不带 Key 访问返回 401，带 Key 返回 200；
- 引擎日志里有 `100% of the experts resident`。

分阶段的门禁和失败退路见[部署文档](docs/部署文档.md)。

---

## 访问方式

```
公网 13270  →  宿主机 8800  →  容器 8080
 平台转发       compose 发布      server 监听 0.0.0.0:8080
```

| 用途 | 地址 |
|---|---|
| Web 聊天页 | `http://<公网IP>:13270/` |
| OpenAI 兼容 | `http://<公网IP>:13270/v1/chat/completions` |
| Anthropic 兼容 | `http://<公网IP>:13270/v1/messages` |
| 健康检查 | `http://<公网IP>:13270/health` |

请求头都要带 `Authorization: Bearer <Key>`，`model` 字段随便填。`/v1` 只是 API 前缀，浏览器直接打开会 404，网页在 `/`。

平台只转发 `13270–13275 → 8800–8805`，**宿主机发布端口必须是这 6 个之一**，否则公网不通。仓库里的 `<公网IP>` 等都是占位符，不记录真实地址。

---

## 踩坑

1. **不要对运行中的容器 `docker rm -f`。** 引擎占着两张卡的 CUDA 上下文，强杀后进程卡在不可中断状态，容器停在中间态（`is zombie` / `did not receive an exit event`）。`init: true` 也解决不了。正确做法：`docker-compose stop` → `down` → `up -d`。
2. **日志里的 `127.0.0.1:8080` 和 `172.x.x.x:8080` 不是访问地址**，只能走上面那条端口链。
3. **发布端口不在平台转发列表里**时，本机一切正常，公网永远不通。
4. **离线机上不要跑 `setup.sh --calibrate`。** 它会删掉 `.venv` 再联网重装，离线装不回来。`/data/strata-src.tar` 是唯一一份完整 venv 的副本，不能删。
5. **压测别用 `max_tokens=100` 又开着思考。** 思考预算是 4096，100 个 token 全被思考占满，回答是空的。压测时在请求里带 `reasoning_effort: "none"`。

---

## 测试环境

| 项 | 值 |
|---|---|
| 平台 | KVM 虚机（PCI 直通），CentOS 7.9 / 内核 3.10 |
| GPU | 2 × A100-SXM4-40GB（sm80，NVLink 不可用，卡间走 PCIe） |
| 驱动 / 引擎 | 550.78 / CUDA 12.4；Strata 0.1.45（`engine-cuda12`） |
| CPU / 内存 | 32 vCPU Xeon 8368Q / 94 GiB |
| 磁盘 | `/data` 1 TB ext4，约 1.4 GB/s |
| 容器 | Docker 20.10.17 + nvidia runtime，compose v2.29.7 |

---

## 仓库结构

```
├── README.md                   本文件
├── 整理说明.md                  2026-11-03 整理改了什么、更正了哪些说法
├── deploy/                     IQ3_XXS 生产部署物：两份推荐配置、compose、.env 样例
├── docs/                       IQ3_XXS 文档（索引见 docs/README.md）
│   ├── 参数详解.md              每个参数：含义、本机值、是否生效、来源
│   ├── 部署文档.md              完整部署流程；§12 是 14 个版本的实测汇总
│   ├── 压测文档.md              方法学、全部实测、缺陷、执行手册、实验计划
│   ├── 运维卡片.md              单页速查
│   ├── 目标机迁移清单.md         换机计划（未执行）
│   ├── 执行时间线.md            逐阶段原始记录
│   ├── 知识库摘要.md            参考资料
│   └── 归档/                   已被取代的早期文档
├── scripts/                    部署、验收、压测、运维脚本（说明见 scripts/README.md）
├── tools/                      tar_peek.py（读 tar 头）、rexec.py（远程批量执行）
└── 待实施-其他模型/              ⚠️ 未部署、未验证，和上面的内容隔离
    ├── IQ3_S.md                已下载，缺 pack
    ├── Coder-IQ1_M.md          已下载，缺 pack
    └── vLLM-Qwen3.8-27B.md     步骤清单，一条命令都没执行
```

**仓库不含**：离线包和模型权重（约 137 GB，走对象存储或内网分发）；任何密钥、SSH 凭据、云账号（配置里的 `api_key` 都是占位符）。

---

## 许可与来源

Strata 引擎（MIT）与 Qwen3.8-Flash-Next 权重（Qwen Community License 1.0）分别遵循各自的上游许可。本仓库只含部署实践与脚本。参数解释引用了 [Strata 官方仓库](https://github.com/Niko1221/Strata)的文档与源码，具体出处见[参数详解 §10](docs/参数详解.md#10-来源)。

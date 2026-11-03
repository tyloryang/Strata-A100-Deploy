# Strata + Qwen3.8-Flash-Next IQ3_XXS · 2×A100 离线部署

在**完全无外网**的机器上，用一份离线包部署 Strata 引擎 + Qwen3.8-Flash-Next IQ3_XXS：双卡层拆分、262144 上下文、API Key 鉴权、Web 页面，并能复现到新机器。

本仓库是**实际执行记录 + 可复用配置和脚本 + 复现手册**，不是离线包本身。

> 📚 文档索引见 [`docs/README.md`](docs/README.md)；**每个参数的含义见 [`docs/参数详解.md`](docs/参数详解.md)**。
> ⚠️ 测试机已于 2026-11-02 23:40 前后回收，文中所有实测数据都来自那台机器。
> 🗂 IQ3_S、Coder、vLLM 27B 等**其他模型的内容都未部署**，单独放在 [`待实施-其他模型/`](待实施-其他模型/README.md)，不和本 README 及 `docs/` 的结论混用。
> 📝 2026-11-03 的整理改了什么，见 [`整理说明.md`](整理说明.md)。

---

## 一、结论速览

| 项 | 结果 |
| --- | --- |
| 离线包完整性 | 5 个 tar `sha256sum -c` 全过；2 个 GGUF 与固定值逐字一致 |
| 部署 | 传输完成到服务 `ready:` 用 **8 分钟**；`setup.sh` 断网 49 秒跑完，零网络请求 |
| 双卡 | 层拆分 auto → 24：CUDA0 跑 0–23 层，CUDA1 跑 24–47 层；**全部 24576 个专家都在显存** |
| 单请求解码 | 约 **105–111 tok/s**（TPOT 约 9 ms） |
| 并发吞吐 | 长提示（2000 token）4 槽并发 8：聚合 **59.5 tok/s**；短提示（800 token）8 槽并发 8：聚合 **89.3 tok/s** |
| 长上下文 | 200K 提示 TTFT 39 秒，预填约 5100 tok/s；越界 400，不截断 |
| 停启 | `stop` 13 秒释放显存；`up -d` 65 秒 healthy |
| 公网 | `http://<公网IP>:13270/health` → 200 |

## 二、推荐配置

| 场景 | 配置文件 | 实测 |
|---|---|---|
| 长提示 / 文档分析（**默认**） | [`deploy/strata-iq3_xxs.recommended.json`](deploy/strata-iq3_xxs.recommended.json)（4 槽） | v6：A 轮并发 8 聚合 59.5 tok/s，TPOT 45.9 ms |
| 短提示 / 高并发问答 | [`deploy/strata-iq3_xxs.recommended-8slot.json`](deploy/strata-iq3_xxs.recommended-8slot.json)（8 槽） | v5：B 轮并发 8 聚合 89.3 tok/s，TPOT 翻倍 |

两份只差 `parallel`、`--batch`、`--conversation-cache-slots` 三处。用之前替换 `api_key` 并 `chmod 600`。

> ⚠️ **两份配置都开着 ESP（实验性速度投影）。** 官方文档说明它是**拒答方向投影**：模型拒答会大幅减少，等于去掉一层安全行为；它不提速，反而每 token 慢 0.2–0.4%。v6/v5 的数据是在开启状态下测的，所以配置暂时保持原样。**如果当初开它是为了提速，请关掉**，方法见[参数详解 §2.7](docs/参数详解.md#27-esp-控制向量先读这一节)。

## 三、端口三层链路

```
公网 13270  →  VM 8800  →  容器 8080
  平台转发      compose 发布     容器内监听（0.0.0.0:8080）
```

平台只转发预留端口：`13270→8800`、`13271→8801` … `13275→8805`。**宿主机发布端口必须是这 6 个之一**，否则公网不通，和镜像、容器、Strata 都无关。

| 用途 | 地址 |
| --- | --- |
| Web 聊天页 | `http://<公网IP>:13270/` |
| OpenAI 兼容 | `http://<公网IP>:13270/v1/chat/completions` |
| Anthropic 兼容 | `http://<公网IP>:13270/v1/messages` |
| 健康检查 | `http://<公网IP>:13270/health` |

`/v1` 是 API 前缀，不是页面；浏览器直接开 `/v1` 会 404，网页在 `/`。`<公网IP>`、`<内网IP>`、`<SSH端口>` 都是占位符，本仓库不记录真实地址。

## 四、测试环境

| 项 | 值 |
| --- | --- |
| 平台 | KVM 虚机（PCI 直通） |
| 系统 | CentOS 7.9 / 内核 3.10.0-1160 |
| GPU | 2 × A100-SXM4-40GB（sm80，ECC 开，MIG 关，**NVLink 不可用**，GPU 间走 PCIe） |
| 驱动 | 550.78 / CUDA 12.4 |
| 引擎 | Strata 0.1.45（`engine-cuda12`） |
| CPU / 内存 | 32 vCPU Xeon 8368Q / 94 GiB |
| 磁盘 | `/data` = 1 TB ext4（约 1.4 GB/s 顺序读写） |
| Docker | 20.10.17 + nvidia runtime；compose v2.29.7（独立二进制） |

## 五、仓库结构

```
README.md                       本文件
整理说明.md                      2026-11-03 整理改了什么、更正了哪些说法
deploy/                         ── IQ3_XXS 生产部署物 ──
  docker-compose.yml            compose 文件（每个字段带注释）
  .env.example                  compose 环境变量样例
  strata-iq3_xxs.recommended.json        推荐配置：4 槽，长提示
  strata-iq3_xxs.recommended-8slot.json  变体：8 槽，短提示
docs/                           ── IQ3_XXS 文档 ──（索引见 docs/README.md）
  参数详解.md                    每个参数：含义、本机值、是否生效、来源
  部署文档.md                    从零到可服务的完整流程；§12 是 14 个版本的实测汇总
  压测文档.md                    方法学、全部实测、缺陷、执行手册、实验计划
  运维卡片.md                    单页速查
  目标机迁移清单.md               IQ3_XXS 换机（未执行）
  执行时间线.md                  逐阶段原始记录
  知识库摘要.md                  参考资料
  归档/                         已被取代的早期文档
scripts/                        部署、验收、压测、运维脚本（说明见 scripts/README.md）
tools/                          tar_peek.py（读 tar 头）、rexec.py（远程批量执行）
待实施-其他模型/                  ⚠️ 未部署、未验证，和上面的内容隔离
  IQ3_S.md                      Flash-Next IQ3_S：已下载，缺 pack
  Coder-IQ1_M.md                Flash-Next Coder：已下载，缺 pack
  vLLM-Qwen3.8-27B.md           vLLM 对照部署：步骤清单，一条命令未执行
```

## 六、快速开始（新机器）

```bash
# 0) 前置：驱动 ≥ 525、docker + nvidia runtime、compose 二进制已预置
# 1) 传包并校验（约 30–60 分钟，取决于带宽）
cd /data && sha256sum -c SHA256SUMS-tars.txt

# 2) 解包
B=/data/qwen-strata
mkdir -p $B/Strata-data/models/IQ3_XXS
tar -xf strata-src.tar -C $B && tar -xf tools.tar -C $B
tar -xf data-packs.tar -C $B/Strata-data && tar -xf data-mtp.tar -C $B/Strata-data
tar -xf Qwen3.8-*-00002-of-00002.tar -C $B/Strata-data/models/IQ3_XXS
tar -xf gguf_done.tar -C $B/Strata-data/models/IQ3_XXS
docker load -i strata-qwen38-cuda12-1.0.tar

# 3) Key 存文件，不进命令行
install -d -m 700 /etc/strata && openssl rand -hex 24 > /etc/strata/api_key && chmod 600 /etc/strata/api_key

# 4) 断网跑 setup 生成基础配置（脚本里的 BASE / 镜像名按实际改；不要加 --calibrate）
bash scripts/setup_offline.sh

# 5) 用推荐配置覆盖 setup 生成的配置，填入 Key
cp deploy/strata-iq3_xxs.recommended.json $B/Strata/strata-iq3_xxs.json
python3 - <<'EOF'
import json; p='/data/qwen-strata/Strata/strata-iq3_xxs.json'
c=json.load(open(p)); c['api_key']=open('/etc/strata/api_key').read().strip()
json.dump(c,open(p,'w'),ensure_ascii=False,indent=2)
EOF
chmod 600 $B/Strata/strata-iq3_xxs.json

# 6) 用 compose 起
mkdir -p /data/compose/strata && cp deploy/docker-compose.yml /data/compose/strata/
cp deploy/.env.example /data/compose/strata/.env
cd /data/compose/strata && docker-compose up -d && docker-compose ps

# 7) 验收
bash scripts/accept.sh
```

分阶段的门禁与失败退路见 [`docs/部署文档.md`](docs/部署文档.md)；换机器见 [`docs/目标机迁移清单.md`](docs/目标机迁移清单.md)。

## 七、四个容易踩的坑

1. **不要对运行中的容器 `docker rm -f`。** 引擎持有两张卡的 CUDA 上下文，SIGKILL 后要拆 GPU 上下文，进程进入不可中断状态，docker 等不到退出事件（`is zombie` / `did not receive an exit event`），服务中断。用 `docker-compose stop` → `down` → `up -d`。加 `init: true` 也不解决。
2. **容器日志里的 `127.0.0.1:8080` / `172.x.x.x:8080` 不是访问地址。** 前者是 `host=0.0.0.0` 时写死的提示，后者是容器桥接 IP。
3. **发布端口必须在平台转发列表里**，否则本机全部正常、公网永远不通。
4. **离线机上不要跑 `setup.sh --calibrate`。** 它会删掉 `.venv` 再联网重装，离线装不回来。`/data/strata-src.tar` 是唯一一份完整 venv 的副本，不能删。

## 八、仓库不含什么

- **离线包本体**（约 137 GB tar / GGUF）与模型权重：体积原因，走对象存储或内网分发。
- **任何密钥**：`/etc/strata/api_key`、配置里的 `api_key`、SSH 凭据都没有入库，配置样例里是占位符。
- 云主机账号、密码、私钥文件。

## 九、许可与来源

Strata 引擎与 Qwen3.8-Flash-Next 权重分别遵循其上游许可（Strata 仓库 MIT、Qwen Community License 1.0）。本仓库只含部署实践与脚本。参数解释引用了 [Strata 官方仓库](https://github.com/Niko1221/Strata) 的文档与源码。

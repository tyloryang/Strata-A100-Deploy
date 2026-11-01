# Strata + Qwen3.8-Flash-Next IQ3_XXS · 2×A100 离线部署

在**完全无外网**的机器上用一份 198 GB 离线包部署 Strata 引擎 + Qwen3.8-Flash-Next IQ3_XXS（双卡层拆分、262144 上下文、API Key 鉴权、Web 页面），并复现到新机器。

本仓库是**实际执行记录 + 可复用脚本 + 复现手册**，不是原始离线包。

---

## 一、已验证的结论

| 项 | 结果 |
| --- | --- |
| 离线包完整性 | 5 个 tar `sha256sum -c` 全过；2 个 GGUF 与固定值逐字一致 |
| 部署 | 传输完成 → 服务 `ready:` 用 **8 分钟**；`setup.sh` 断网 49 秒跑完，零网络请求 |
| 双卡 | `layer split across GPUs [0, 1] (auto)`，显存 26.7 + 32.8 GiB |
| 速度 | 解码 **106–123 tok/s**（云主机 A100-80G 参考 112）；1460 token 预填 1335 tok/s |
| 长上下文 | 14.4 万 token 请求 27.7 秒返回，预填 **5271 tok/s** |
| 资源 | 内存 45/94 GB，swap 仅 5–20 MB，两卡余量约 22 GiB |
| 停启 | `stop` 13 秒释放显存；`start` 65 秒恢复 healthy |
| 公网 | `http://223.109.239.30:13270/health` → 200（移动线）；电信线 `180.127.11.167:13270` 同样 200 |

## 二、端口三层链路

```
公网 13270  →  VM 8800  →  容器 8080
  平台转发      compose published    容器内监听（0.0.0.0:8080）
```

平台只转发预留端口：`13270→8800`、`13271→8801` … `13275→8805`。**发布端口必须落在这 6 个里**，否则公网不通——与镜像、容器、Strata 都无关。

访问入口：

| 用途 | 地址 |
| --- | --- |
| Web 聊天页 | `http://<公网IP>:13270/` |
| OpenAI 兼容 | `http://<公网IP>:13270/v1/chat/completions` |
| Anthropic 兼容 | `http://<公网IP>:13270/v1/messages` |
| 健康检查 | `http://<公网IP>:13270/health` |

> `/v1` 是 API 前缀，不是页面；浏览器直接开 `/v1` 会 404，网页在 `/`。

## 三、测试环境

| 项 | 值 |
| --- | --- |
| 平台 | KVM 虚机（PCI 直通） |
| 系统 | CentOS 7.9 / 内核 3.10.0-1160 |
| GPU | 2 × A100-SXM4-40GB（sm80，ECC 开，MIG 关，**NVLink 不可用**，GPU 间走 PCIe） |
| 驱动 | 550.78 / CUDA 12.4 |
| CPU / 内存 | 32 vCPU Xeon 8368Q / 94 GiB |
| 磁盘 | `/data` = 1 TB ext4（实测约 1.4 GB/s 顺序读写） |
| Docker | 20.10.17 + nvidia runtime；compose v2.29.7（独立二进制） |
| 网络 | 单网口 libvirt NAT，**无 RDMA/IB**；NCCL 2 卡 all-reduce 9.3 GB/s |

## 四、仓库结构

```
docs/
  执行记录.md          逐阶段命令、原始输出、耗时、故障复盘（含端口与 compose 两次事故）
  plan-新内网机器复现.md  A–G 七阶段计划：门禁、预期、失败退路、耗时预算
  运维卡片.md          单页：启停、接口、改配置、故障速查
deploy/
  docker-compose.yml   生产配置（双卡、健康检查、init、发布端口）
scripts/               运维与验证脚本，见下表
tools/
  tar_peek.py          读 tar 头（支持 GNU base-256 大文件）
```

## 五、脚本

| 脚本 | 用途 |
| --- | --- |
| `preflight.sh` | 部署前检查：端口、容器、内存、SELinux、磁盘、GPU |
| `watch_upload.sh` / `start_watch.sh` | 上传监控（比对期望字节数，写状态文件） |
| `verify_offline.sh` | 5 个 tar + 2 个 GGUF 的 sha256 校验并计时 |
| `extract_model.sh` / `start_extract.sh` | 解包模型 tar 并校验两片 GGUF |
| `setup_offline.sh` | 断网生成双卡配置（Key 从文件读，不进命令行） |
| `start_strata.sh` | docker run 方式启动（compose 不可用时的退路） |
| `collect_evidence.sh` | 收集 nvidia-smi / free / docker / 日志 / 配置（Key 打码） |
| `accept.sh` | 验收：health、401/200、推理、slots |
| `web_check.sh` | Web 页面与静态资源、一次真实对话 |
| `speed_test.sh` | 短/长提示的解码与预填速度、草稿命中 |
| `long_context.sh` | 14 万 token 长上下文验证 |
| `api_surface.sh` | Anthropic 端点、并发排队行为 |
| `restart_test.sh` / `compose_lifecycle.sh` | 停启与 compose 生命周期计时 |
| `port8800.sh` / `diag_port.sh` | 切换发布端口、端口三层取证 |
| `recover.sh` / `rmf_test.sh` | 异常恢复、`rm -f` 卡死复现 |

## 六、快速开始（新机器）

```bash
# 0) 前置：驱动 ≥535、docker + nvidia runtime、compose 二进制已预置
# 1) 传包并校验（约 30–60 分钟，取决于带宽）
cd /data && sha256sum -c SHA256SUMS-tars.txt

# 2) 解包
B=/data/qwen-strata
tar -xf strata-src.tar -C $B && tar -xf tools.tar -C $B
tar -xf data-packs.tar -C $B/Strata-data && tar -xf data-mtp.tar -C $B/Strata-data
mkdir -p $B/Strata-data/models/IQ3_XXS
tar -xf Qwen3.8-*-00002-of-00002.tar -C $B/Strata-data/models/IQ3_XXS
tar -xf gguf_done.tar -C $B/Strata-data/models/IQ3_XXS
docker load -i strata-qwen38-cuda12-1.0.tar

# 3) 生成配置（API Key 存文件，不进命令行）
install -d -m 700 /etc/strata && openssl rand -hex 24 > /etc/strata/api_key && chmod 600 /etc/strata/api_key
bash scripts/setup_offline.sh     # 注意把里面的 BASE/镜像名改成实际值

# 4) 用 compose 起
cd /data/compose/strata && docker-compose up -d && docker-compose ps
```

分阶段的门禁与失败退路见 `docs/plan-新内网机器复现.md`。

## 七、三个容易踩的坑

1. **不要对运行中的容器 `docker rm -f`** —— 引擎持有 CUDA 上下文，SIGKILL 后要拆 GPU 上下文，进程进入不可中断状态，docker 等不到退出事件（`is zombie` / `did not receive an exit event`），容器卡在中间态、服务中断。用 `docker-compose stop` → `down` → `up -d`。加 `init: true` 也不解决。
2. **容器日志里的 `127.0.0.1:8080` / `172.x.x.x:8080` 不是访问地址** —— 前者是 `host=0.0.0.0` 时写死的提示，后者是容器桥接 IP（重建网络还会变）。
3. **发布端口必须在平台转发列表里** —— 否则本机全部正常、公网永远不通。

## 八、仓库不含什么

- **离线包本体**（198 GB tar/GGUF）与模型权重 —— 体积原因，走对象存储/内网分发。
- **任何密钥**：`/etc/strata/api_key`、配置文件里的 `api_key`、SSH 凭据均未入库；配置样例已打码。
- 云主机账号、密码、私钥文件。

## 九、许可与来源

Strata 引擎与 Qwen3.8-Flash-Next 权重分别遵循其上游许可（Strata 仓库、Qwen Community License 1.0）。本仓库只含部署实践与脚本。

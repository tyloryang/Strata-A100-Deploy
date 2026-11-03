# 脚本说明

> 测试机上这些脚本放在 `/root/offline_check/`（平铺，没有子目录），日志也写在那里。这里保持平铺，方便直接拷过去用。
> 所有脚本都**在宿主机上执行**（evalscope 压测除外，它要在容器里跑，见[压测文档 §1.1](../docs/压测文档.md#11-工具与环境)）。

## 一、按阶段分类

### 部署前与部署

| 脚本 | 什么时候用 | 做什么 | 只读？ |
|---|---|---|---|
| `preflight.sh` | 部署前 | 检查端口 8800/8080 是否空闲、已有容器、内存、SELinux、磁盘类型与容量、GPU 占用、docker runtime | 是 |
| `watch_upload.sh` | 上传离线包期间 | 每 60 秒比对 `/data` 下 8 个文件的字节数和期望值，写 `status.txt`（`uploading` / `COMPLETE` / `IDLE_INCOMPLETE`）。不算哈希，免得和上传抢带宽 | 是 |
| `start_watch.sh` | 同上 | 后台启动 `watch_upload.sh`，pid 写进 `watch.pid`，防止重复启动 | 是 |
| `verify_offline.sh` | 上传完成后 | `sha256sum -c SHA256SUMS-tars.txt` 校验 tar；GGUF 已解出时再算两个分片的哈希并打印期望值 | 是 |
| `extract_model.sh` | 校验通过后 | 解包模型 tar 到 `Strata-data/models/IQ3_XXS/`，再算两个 GGUF 的 sha256 | 否（写磁盘） |
| `start_extract.sh` | 同上 | 后台启动 `extract_model.sh`，pid 写进 `extract.pid` | 否 |
| `check_image.sh` | 镜像导入后 | 容器内 Python 版本、关键依赖、torch 能否看到两张卡、`setup.sh --help`、现有配置（Key 打码） | 是 |
| `setup_offline.sh` | 生成配置 | 断网跑 `setup.sh --setup` 生成双卡配置；Key 从 `/etc/strata/api_key` 读，不出现在命令行和日志里 | 否（生成配置） |
| `show_config.sh` | 任意时候 | 打印配置（Key 打码）、启动脚本、文件权限 | 是 |
| `start_strata.sh` | **compose 不可用时的兜底** | `docker run` 方式启动，参数与 compose 对齐 | 否（重建容器） |

### 验收与压测

| 脚本 | 做什么 | 只读？ |
|---|---|---|
| `accept.sh` | 验收：health、无 Key 401、有 Key 200、模型列表、一次中文推理、slots、nvidia-smi、内存 | 是（会发一个推理请求） |
| `web_check.sh` | Web 页面、静态资源、一次真实对话 | 是 |
| `speed_test.sh` | 短提示解码、同提示复测（看缓存）、约 2000 token 长提示预填；打印预填/解码 tok/s 和草稿接受数 | 是 |
| `long_context.sh` | 发一个约 20 万 token 的中文长提示，记录预填耗时和之后的资源状态 | 是（占用服务约 40 秒） |
| `api_surface.sh` | Anthropic `/v1/messages` 端点、无 Key 401、两个并发请求的处理方式、请求后资源 | 是 |
| `collect_evidence.sh` | 把 nvidia-smi、free、df、docker、日志、配置（Key 打码）收进 `evidence/<时间戳>/` | 是 |

### 运维与故障

| 脚本 | 做什么 | 风险 |
|---|---|---|
| `restart_test.sh` | `docker stop` 看显存是否释放，再 `docker start` 计时到 ready | 中断服务约 1 分钟 |
| `compose_lifecycle.sh` | 依次测 compose 的 restart / stop / start / down / up -d 耗时 | 中断服务数分钟 |
| `recover.sh` | 恢复服务：compose stop → down → 清理残留 → up -d，等到 healthy | 中断服务 |
| `diag_port.sh` | 端口三层链路取证：.env、compose 解析结果、运行态端口绑定、宿主机/容器内探活 | 只读 |
| `port8800.sh` | 把发布端口切到 8800（**一次性迁移，测试机上已做完**） | 中断服务 |
| `compose_up_test.sh` / `compose_up2.sh` | 从 `docker run` 切到 compose 管理（**一次性迁移，测试机上已做完**） | 中断服务 |
| `rmf_test.sh` | ⚠️ 复现"运行中 `docker rm -f` 卡死"。**默认拒绝执行**，要设 `I_KNOW_THIS_BREAKS_SERVICE=1` | 中断服务，容器可能卡约 5 分钟 |

## 二、可调的环境变量

| 变量 | 默认值 | 用在哪些脚本 | 含义 |
|---|---|---|---|
| `IP` | `127.0.0.1` | speed_test、long_context、api_surface、compose_*、recover、restart_test | 访问服务用的宿主机地址。`.env` 的 `BIND_IP` 是具体内网 IP 时，这里要填那个 IP |
| `PORT` | `8800` | 同上，以及 start_strata | 宿主机发布端口，必须和 compose 的 `'${BIND_IP}:8800:8080'` 前半段一致 |
| `BIND_IP` | `0.0.0.0`（start_strata）/ `127.0.0.1`（accept、diag_port） | start_strata、accept、diag_port | 发布地址；accept 用它拼访问地址 |
| `I_KNOW_THIS_BREAKS_SERVICE` | `0` | rmf_test | 设为 1 才允许执行 |

脚本里写死、换机器时要检查的值：

| 值 | 出现在 | 说明 |
|---|---|---|
| `BASE=/data/qwen-strata` | setup_offline、start_strata、show_config、check_image、collect_evidence | 离线包解开的目录 |
| `IMG=strata-qwen38:cuda12-1.0` | setup_offline、start_strata、check_image | 镜像名 |
| `/data/compose/strata` | compose_*、recover、diag_port、port8800、rmf_test | compose 文件所在目录 |
| `/etc/strata/api_key` | 几乎所有发请求的脚本 | Key 文件，600 权限；丢了见[部署文档 §9.5](../docs/部署文档.md#95-恢复后-api-返回-401-或脚本报-filenotfounderror-etcstrataapi_key) |
| `/root/offline_check/` | 所有写日志的脚本 | 日志目录，脚本会自动创建 |

## 三、本次整理对脚本做的修改

| 修改 | 涉及脚本 | 原因 |
|---|---|---|
| 访问端口从写死的 `8080` 改成 `$PORT`（默认 8800） | speed_test、long_context、api_surface、compose_lifecycle、compose_up2、compose_up_test、recover、restart_test | 端口链改成"宿主 8800 → 容器 8080"之后，宿主机上的 8080 已经不监听，这些脚本按原样会连不上 |
| `start_strata.sh` 的端口映射从 `8080:8080` 改成 `${PORT}:8080`，并加 `--init` | start_strata | 和 compose 保持一致；8080 不在平台转发列表里，公网不通 |
| 删除运行中容器前先 `docker stop -t 120` | start_strata、compose_up2、compose_up_test、recover | 仓库自己的结论是"不要对运行中的容器 `docker rm -f`"，旧脚本却在这么做 |
| `rmf_test.sh` 默认拒绝执行 | rmf_test | 它的作用就是让服务卡死，结论已有 |
| `preflight.sh` 检查 8800/8080，不再检查 1309 | preflight | 1309 是早期 vLLM 容器的端口，和 IQ3_XXS 部署无关 |
| `diag_port.sh` 去掉重复的探活地址，加容器内探活 | diag_port | 原来有两条完全相同的 URL（脱敏时把不同 IP 都替换成了 127.0.0.1） |
| `api_surface.sh` 读 `/slots` 时带上 Key | api_surface | 开启鉴权后不带 Key 会 401 |
| 写日志前 `mkdir -p` | 所有写日志的脚本 | 新机器上 `/root/offline_check/` 不存在时脚本会直接失败 |

## 四、`tools/`

| 文件 | 做什么 |
|---|---|
| `tools/tar_peek.py` | 不解包直接读 tar 头，列出里面的文件和大小（支持 GNU base-256 编码的超大文件）。用法：`python3 tools/tar_peek.py <tar 文件>` |
| `tools/rexec.py` | 从本地批量在远程主机执行命令或上传文件（paramiko）。凭据只从环境变量读：`DSH_SSH_HOST`、`DSH_SSH_PORT`、`DSH_SSH_USER`、`DSH_SSH_PASS` 或 `DSH_SSH_KEY`。用法：`python rexec.py "nvidia-smi" "docker ps"`、`python rexec.py --put 本地文件:/远程绝对路径 "命令"`。参数：`--timeout` 单条命令超时（默认 300 秒），`--connect-timeout` 连接超时（默认 20 秒） |

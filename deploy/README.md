# deploy/：IQ3_XXS 生产部署物

> **最新实测配置（2026-11-14）**：[双 A100 PCIe 40GB 最终快照](strata-iq3_xxs.a100-pcie40g-20261114.measured.json)，针对 32K 新输入 TTFT 筛选并复验。平均 8.149 秒，未达 2 秒；完整差异、实际 argv 和测量条件见[最新压测报告](../docs/最新压测结果-2026-11-14.md)。它保留实际测试字段，仅 Key 脱敏，使用 `/data/Strata` 路径；不能直接覆盖下方旧 SXM4 Docker 配置。

| 文件 | 放到哪里 | 是什么 |
|---|---|---|
| `strata-iq3_xxs.a100-pcie40g-20261114.measured.json` | 按实际 AutoDL 路径与私有 Key 配置 | **2026-11-14 最新实测快照**：4 引擎槽、prefill 8192，32K 目标选中组合 |
| `strata-iq3_xxs.recommended.json` | `/data/qwen-strata/Strata/strata-iq3_xxs.json` | **推荐配置**：4 槽，长提示 / 文档分析（实测 v6） |
| `strata-iq3_xxs.recommended-8slot.json` | 同上（二选一） | 变体：8 槽，短提示 / 高并发问答（实测 v5） |
| `docker-compose.yml` | `/data/compose/strata/docker-compose.yml` | compose 服务定义，每个字段都有注释 |
| `.env.example` | `/data/compose/strata/.env` | compose 环境变量：`BASE`、`BIND_IP` |

## 用法

```bash
# 1. 选一份配置，填入 Key，收紧权限
cp strata-iq3_xxs.recommended.json /data/qwen-strata/Strata/strata-iq3_xxs.json
python3 - <<'EOF'
import json; p='/data/qwen-strata/Strata/strata-iq3_xxs.json'
c=json.load(open(p)); c['api_key']=open('/etc/strata/api_key').read().strip()
json.dump(c,open(p,'w'),ensure_ascii=False,indent=2)
EOF
chmod 600 /data/qwen-strata/Strata/strata-iq3_xxs.json

# 2. compose
mkdir -p /data/compose/strata
cp docker-compose.yml /data/compose/strata/ && cp .env.example /data/compose/strata/.env
cd /data/compose/strata && docker-compose config >/dev/null && docker-compose up -d
```

改完配置后的验证步骤见[参数详解 §9](../docs/参数详解.md#9-改完怎么验)。

## 两份配置的差异

| 项 | 4 槽（推荐） | 8 槽 |
|---|---|---|
| `parallel` | 4 | 8 |
| `args` 里的 `--batch` | 4 | 8 |
| `--conversation-cache-slots` | 4 | 8 |
| 长提示（in=2000）并发 8 | 聚合 59.5 tok/s，TPOT 45.9 ms | 聚合 56.4 tok/s，TPOT 94.7 ms |
| 短提示（in≈800）并发 8 | 聚合 80.7 tok/s，TPOT 40.8 ms | 聚合 89.3 tok/s，TPOT 71.4 ms |

## 配置文件里的 `_说明` / `_注意` / `_代价`

这些以 `_` 开头的键是给人看的说明，server.py 不使用。JSON 不支持注释，所以说明只能这样写。**每个参数的完整解释在 [`docs/参数详解.md`](../docs/参数详解.md)**，这里只列两份配置共同的四个要点：

1. **ESP 可选、默认关闭**：4 个 `--control-vector*` / `--cvec-*` 参数照常加载向量，`sampling.experimental_speed_projection: false` 让请求默认不用它。需要时按请求或按对话打开，方法见[参数详解 §2.7](../docs/参数详解.md#27-esp-控制向量先读这一节)。它是拒答方向投影，不是提速功能。
2. `STRATA_ROUTE_TAIL_SKIP=0` 在本机不起作用（专家全在显存），保留无害。
3. 相对测试机最后使用的配置，整理时删除了 `STRATA_ADAPT_OVERLAP` 和 `STRATA_ADAPT_OVERLAP_RESIDENT`：本机日志显示它们在层拆分下是关闭的，删除不改变行为。
4. 所有路径都是容器内路径，宿主机目录必须挂到容器的 `/data`。

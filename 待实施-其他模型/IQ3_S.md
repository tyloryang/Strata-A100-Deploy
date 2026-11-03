# ⚠️ 待实施：Qwen3.8-Flash-Next IQ3_S（Strata）

> **状态：未部署、未验证。** 只完成了下载和字节数核对。下面的步骤和估算都没在机器上跑过。
> 内容来源：原[部署文档 §12.10](../docs/部署文档.md#1210-未完成的事项)（已移到这里）、[归档的原始压测报告 §一](../docs/归档/压测报告-原始版-2026-11-02.md)、Strata 官方 `docs/MODELS.md`。

## 一、模型是什么

- 来源：`ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF`，量化档 **IQ3_S**
- 官方定位：四个 ISTA-DASLab 原版档（Q2_0 / IQ2_XS / IQ3_XXS / IQ3_S）里**质量最好、速度最慢**的一档，"在已发布的测试上与完整模型持平"
- 和 IQ3_XXS 的区别：同一个模型，专家权重量化得更细，所以更大

| 项 | IQ3_S | IQ3_XXS（对照） |
|---|---|---|
| 分片 1 | 54,817,524,224 字节（约 52 GB） | 约 47 GB |
| 分片 2（PLE 表，共用） | 28,800,138,432 字节 | 同一个文件 |
| 专家总量（官方 MODELS.md） | **约 50 GB** | 约 43 GB |
| 内存 + 显存合计需求（官方） | 54.8 GB | 47.0 GB |

下载记录：2026-11-02 07:53–08:39，与 ModelScope 文件清单逐字节一致，落在 `Strata-data/models/IQ3_S/`。

## 二、为什么不能直接用 IQ3_XXS 的配置

**pack 和量化档是绑定的。** `packs/iq3_xxs/experts.bin`（40 GB）是按字节偏移从 IQ3_XXS 分片里抠出来的，`experts.bin.src.json` 和 `native_experts.txt` 里钉死了 IQ3_XXS 的分片名、大小和偏移，**不能复用**。必须给 IQ3_S 重新生成 pack。

## 三、部署步骤（未执行）

### 3.1 生成 pack

```bash
/data/Strata/.venv/bin/python /data/Strata/tools/iq_pack.py \
  --gguf /data/Strata-data/models/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf \
  --out  /data/Strata-data/packs/iq3_s
```

- **不要加 `--experts-bin`**。不加时 pack 只含 index + tokenizer + dense（约 1.5 GB，几分钟完成），引擎直接从 GGUF 读专家；加了才会生成约 40 GB 的 `experts.bin`（几十分钟）。
- 参数以 `tools/iq_pack.py --help` 为准。

### 3.2 写配置

复制 IQ3_XXS 的推荐配置为 `strata-iq3_s.json`，**只换模型相关的 5 处**：

| 项 | 改成 |
|---|---|
| `--pack` | `/data/Strata-data/packs/iq3_s` |
| `--native` | `/data/Strata-data/models/IQ3_S/…-IQ3_S-00001-of-00002.gguf` |
| `--ple-gguf` | `/data/Strata-data/models/IQ3_S/…-IQ3_S-00002-of-00002.gguf`（或硬链接到 IQ3_XXS 的那份） |
| `tokenizer` | `/data/Strata-data/packs/iq3_s/tokenizer` |
| `model_name` / `log` | 改成 iq3_s，避免和 IQ3_XXS 的日志混在一起 |

`--expert-profile` 是否能沿用 IQ3_XXS 的那份**没有确认**（同一模型的专家热度应当相近，但文件格式是否绑定量化档不清楚），启动日志会说明它是否被接受。

### 3.3 启动

- 需要一个对应的启动脚本（仿照 `run-iq3_xxs.sh` 指向新配置），compose 的 `command` 改成它。
- **两张卡已被 IQ3_XXS 占用**，必须先 `docker-compose stop` 停掉 IQ3_XXS，或换机器。

## 四、需要重新核的风险（估算，未验证）

- **专家可能装不满显存。** IQ3_XXS 时两卡已用 37.8 + 31.2 GB，其中专家 17.72 + 22.24 GiB；IQ3_S 的专家比 IQ3_XXS 多约 7 GB。按这个账本，IQ3_S **很可能有一部分专家放不进显存**，由 CPU 从内存计算，解码会明显变慢。这时：
  - `STRATA_ROUTE_TAIL_SKIP` 会变得有意义（专家有未命中了），0 和 7 值得做一次 A/B；
  - `--prefill auto:32768` 借走的显存槽位会更伤，可以对比 `--prefill auto`。
- **内存**：`--resident-experts` 会把显卡放不下的专家拷进内存，内存占用会比 IQ3_XXS 高；94 GiB 机器上要重新算。
- **验收**：启动日志里看 `N% of the experts resident` 和两行 `VRAM free with everything loaded`；然后按[压测文档 §7](../docs/压测文档.md#7-压测执行手册可复用)的规矩单独建基线。

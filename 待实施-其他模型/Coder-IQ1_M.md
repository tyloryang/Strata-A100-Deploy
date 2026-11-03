# ⚠️ 待实施：Qwen3.8-Flash-Next Coder IQ1_M（Strata）

> **状态：未部署、未验证。** 只完成了下载和字节数核对。
> 内容来源：[归档的原始压测报告 §一](../docs/归档/压测报告-原始版-2026-11-02.md)、Strata 官方 `docs/MODELS.md` 和 `docs/DETAILS.md`。

## 一、模型是什么

- 来源：`ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF`
- **剪枝版**：每层 512 个专家只保留 256 个（每 token 仍激活 10 个），按代码、agent 和图像数据挑选
- 官方数据：SWE-bench Verified 达到完整模型的 91%，LiveCodeBench 达到 99%
- **代码以外的任务、英文以外的语言（包括中文）会变弱**。官方建议：通用场景、或者内存允许时，选保留全部专家的档位（比如 IQ3_XXS）
- **只有 IQ1_M 这一档**（专家的存储方式和 IQ3_S 相同），不存在"Coder + IQ3_S"

| 项 | 值 |
|---|---|
| 分片 1 | 29,608,446,496 字节（约 29.6 GB），其中专家约 23 GB |
| 分片 2（PLE 表，和其他档共用） | 28,800,138,432 字节 |
| 测试机落位 | `Strata-data/models/coder-IQ1_M/`（setup.py 的规则：`models_dir / (tag + model)`，coder 的 tag 是 `coder-`） |

## 二、部署思路（未执行）

1. **生成 pack**：和 [IQ3_S](IQ3_S.md#31-生成-pack) 一样用 `tools/iq_pack.py` 指向 Coder 的分片 1，输出到单独的 pack 目录。具体参数以 `tools/iq_pack.py --help` 和 `./setup.sh --help` 为准（官方终端安装方式是 `strata launch --family coder --model IQ1_M`）。
2. **写配置**：复制 IQ3_XXS 推荐配置，换 `--pack`、`--native`、`--ple-gguf`、`tokenizer`、`model_name`、`log`。
3. **停掉 IQ3_XXS 或换机器**：两张卡不能同时给两个服务。

## 三、预期与风险（估算，未验证）

- 专家只有约 23 GB，两张 40 GB 卡**一定能全部装进显存**，显存和内存都会比 IQ3_XXS 宽松，有余量试更多槽位。
- 是否适合上线取决于业务：如果主要是中文问答、文档分析，官方明确说它会变弱，**不建议替换 IQ3_XXS**；只适合专门的代码 / agent 场景。
- 上线前需要单独做质量评测，不能只看吞吐。

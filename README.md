# Amplicon Analysis Agent

面向 Claude Code 的可审计扩增子微生物组 MCP Server。首版从 ASV 丰度表、分类表和样本信息表开始，完成输入诊断、分析计划、一次性审批、R 分析、结果校验和 HTML 报告。

项目级专家 Skill 已放在 `.claude/skills/amplicon-analysis/`，从仓库目录启动 Claude Code 时会自动发现；MCP Server 负责真正的文件检查、审批和分析执行。

## 已实现能力

- QC、Observed/Shannon/Simpson Alpha 多样性；
- Bray-Curtis、PCoA、PERMANOVA 与组内离散度检验；
- Genus 优先、自动降级分类层级的 Top-N 群落组成；
- 输入哈希、固定参数、一次性审批令牌、运行日志；
- HTML 报告和机器可读 JSON；
- 所有文件访问限制在 `AMPLICON_WORKSPACE` 内；
- 无有效重复时自动跳过不适用的显著性检验。
- 支持按 `batch_column` 分层推断，避免实验批次与处理效应混杂；
- 支持通过 `gradient_column` 分析连续增强的胁迫梯度。
- 注册55个 R 分析函数，并记录 `verified`、`registered_untested`、`conditional`、`blocked` 兼容状态；
- 扩展函数在批次隔离的 phyloseq 工作区执行，输出独立日志和清单。
- 支持可选系统发育树、代表序列和函数专属参数，全部纳入文件哈希与审批失效机制；
- 函数执行前按批次检查样本量、分组数、树、KO及source/sink等前置条件。
- 全部函数完成后，确定性脚本自动扫描运行目录，把所有图件按批次/结果类型导入统一 HTML；
- 自动生成 `report_data.json` 供大模型在校验通过后解读，并生成带文件哈希的 `artifact_manifest.json`。

## 分层架构

`专家 Skill → MCP 编排与审批 → R 函数确定性计算 → 确定性校验与报告汇总 → 大模型解读`

- 专家 Skill 解析生物学问题和实验设计、整理输入、选择合适分析并设定解释边界；
- MCP Server 负责工具 Schema、路径安全、输入哈希、分析合同、一次性审批和执行状态；
- R 分析函数只负责统计计算和原始图表；
- 报告脚本递归扫描结果文件夹，自动生成 HTML、机器可读摘要和完整产物清单；
- 大模型只在校验通过后读取结构化摘要，负责解释，不负责计算、找文件或拼报告。

详细设计见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

## 目录结构

```text
.claude/skills/amplicon-analysis/  专家工作流与函数选择规范
src/amplicon_agent/                MCP、合同、审批、校验和报告代码
r/run_analysis.R                   基础分析执行器
r/functions/                       注册的 R 分析函数与共享输入适配器
scripts/                           示例运行、报告重建和目录生成脚本
examples/demo/                     最小三表示例
tests/                             输入、审批、注册表和报告测试
docs/                              架构、函数目录和集成边界
```

## 本地运行

```powershell
cd amplicon-analysis-agent
$env:AMPLICON_WORKSPACE=(Get-Location).Path
python -m pip install -e ".[test]"
python -m pytest
python scripts/demo_run.py
```

使用工作区外部的 TSV 数据：

```powershell
$env:PYTHONPATH="src"
python scripts/demo_run.py --workspace "E:\桌面\生信agent" `
  --abundance "rawdata\otutab.txt" `
  --taxonomy "rawdata\taxonomy.txt" `
  --metadata "rawdata\metadata.tsv" `
  --group-column treatment
```

## Docker 与 Claude Code

```powershell
docker build -t amplicon-analysis-agent:0.2.0 .
docker run --rm -i -v "${PWD}:/workspace" -e AMPLICON_WORKSPACE=/workspace amplicon-analysis-agent:0.2.0
```

构建镜像后，可复制 `.mcp.json.example` 为 `.mcp.json`，或执行：

```powershell
claude mcp add amplicon-analysis -- docker run --rm -i -v "${PWD}:/workspace" -e AMPLICON_WORKSPACE=/workspace amplicon-analysis-agent:0.2.0
```

建议提示词：

> 请使用 amplicon-analysis skill 检查三张输入表。先展示分析合同，未经我确认不要执行。

## 三表格式

- 丰度表：第一列为 Feature ID，其余列为样本；也支持自动识别转置方向；
- 分类表：第一列为 Feature ID，其余为 Kingdom 到 Species 等分类层级；
- 样本表：第一列为 Sample ID，并包含指定的生物学分组列；
- CSV 和 TSV 均可自动识别。

## MCP 工具

`inspect_amplicon_inputs`、`prepare_amplicon_analysis`、`approve_analysis`、`run_amplicon_analysis`、`get_run_status`、`validate_amplicon_results`、`get_analysis_report`、`get_report_context`。

扩展能力查询工具：`list_amplicon_analysis_functions`、`inspect_amplicon_function`。

完整的55个函数、状态、参数和前置条件见 [`docs/FUNCTION_CATALOG.md`](docs/FUNCTION_CATALOG.md)。

函数兼容状态来自自动冒烟测试：31个已验证、24个条件可用、无未处理阻断函数。条件函数只有在输入和样本量要求满足时才执行；不适用批次会写入 `skipped` 和明确原因，不会伪造结果。旧 DESeq2 和组成图封装的版本冲突已有原生回退实现。

多实验数据应在检查和计划工具中同时传入 `batch_column`。剂量、时间或胁迫强度为有序数值时传入 `gradient_column`。此时分类实验在批次内部运行 Kruskal–Wallis、PERMANOVA 与离散度检验；完整数值梯度运行 Spearman Alpha 趋势和连续变量 PERMANOVA。Agent 不执行跨批次的总体显著性检验。

## 分析函数来源

团队整理的函数已作为普通 R 分析函数纳入 `r/functions/`。函数直接通过合同中的函数 ID 调用，不使用额外的包名前缀。来源、兼容规则和修改边界见 [`docs/FUNCTION_INTEGRATION.md`](docs/FUNCTION_INTEGRATION.md)。

## 解释边界

- 未审批不执行，审批令牌只能使用一次；
- 输入文件变化后旧审批失效；
- PERMANOVA 必须与组内离散度检验共同解释；
- 组间差异与相关性不能证明因果关系。

# Amplicon Analysis Agent

面向 Claude Code 的可审计扩增子微生物组 MCP Server。首版从 ASV 丰度表、分类表和样本信息表开始，完成输入诊断、分析计划、一次性审批、R 分析、结果校验和 HTML 报告。

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

## 本地运行

```powershell
cd amplicon-analysis-agent
$env:AMPLICON_WORKSPACE=(Get-Location).Path
python -m pip install -e ".[test]"
pytest
python scripts/demo_run.py
```

使用本项目附带的真实 TSV 数据：

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
docker build -t amplicon-analysis-agent:0.1.0 .
docker run --rm -i -v "${PWD}:/workspace" -e AMPLICON_WORKSPACE=/workspace amplicon-analysis-agent:0.1.0
```

构建镜像后，可复制 `.mcp.json.example` 为 `.mcp.json`，或执行：

```powershell
claude mcp add amplicon-analysis -- docker run --rm -i -v "${PWD}:/workspace" -e AMPLICON_WORKSPACE=/workspace amplicon-analysis-agent:0.1.0
```

建议提示词：

> 请使用 amplicon-analysis skill 检查三张输入表。先展示分析合同，未经我确认不要执行。

## 三表格式

- 丰度表：第一列为 Feature ID，其余列为样本；也支持自动识别转置方向；
- 分类表：第一列为 Feature ID，其余为 Kingdom 到 Species 等分类层级；
- 样本表：第一列为 Sample ID，并包含指定的生物学分组列；
- CSV 和 TSV 均可自动识别。

## MCP 工具

`inspect_amplicon_inputs`、`prepare_amplicon_analysis`、`approve_analysis`、`run_amplicon_analysis`、`get_run_status`、`validate_amplicon_results`、`get_analysis_report`。

多实验数据应在检查和计划工具中同时传入 `batch_column`。剂量、时间或胁迫强度为有序数值时传入 `gradient_column`。此时分类实验在批次内部运行 Kruskal–Wallis、PERMANOVA 与离散度检验；完整数值梯度运行 Spearman Alpha 趋势和连续变量 PERMANOVA。Agent 不执行跨批次的总体显著性检验。

## EMO 函数来源

团队整理函数位于上级工作区 `R/`。首版基线执行器保持轻依赖；后续按模块提取纯函数并记录作者、来源版本和修改内容，详见 `docs/EMO_INTEGRATION.md`。

## 解释边界

- 未审批不执行，审批令牌只能使用一次；
- 输入文件变化后旧审批失效；
- PERMANOVA 必须与组内离散度检验共同解释；
- 组间差异与相关性不能证明因果关系。

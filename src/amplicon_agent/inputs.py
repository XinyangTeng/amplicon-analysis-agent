from __future__ import annotations

import csv
from pathlib import Path

import pandas as pd

from .models import InputFiles, InspectionResult
from .security import secure_path, sha256_file


ID_CANDIDATES = {"featureid", "feature_id", "asv", "otu", "id", "sampleid", "sample_id"}
RANK_ORDER = ["Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species"]
GROUP_HINTS = ("group", "treatment", "condition", "stress", "处理", "分组", "组别", "胁迫")


def _raw_header(path: Path) -> list[str]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        sample = handle.read(4096)
        handle.seek(0)
        try:
            dialect = csv.Sniffer().sniff(sample, delimiters=",\t;")
        except csv.Error:
            dialect = csv.excel
        return next(csv.reader(handle, dialect))


def _read(path: Path) -> pd.DataFrame:
    return pd.read_csv(path, sep=None, engine="python", encoding="utf-8-sig")


def _duplicates(items: list[str]) -> list[str]:
    seen: set[str] = set()
    duplicates: set[str] = set()
    for item in items:
        if item in seen:
            duplicates.add(item)
        seen.add(item)
    return sorted(duplicates)


def _suggest_group_columns(meta: pd.DataFrame) -> list[str]:
    candidates: list[tuple[int, int, str]] = []
    sample_count = max(1, len(meta))
    for column in [str(value) for value in meta.columns[1:]]:
        clean = meta[column].dropna().astype(str).str.strip()
        unique_count = clean.nunique()
        if unique_count < 2 or unique_count > max(20, sample_count // 2):
            continue
        name_score = 0 if any(hint in column.lower() for hint in GROUP_HINTS) else 1
        candidates.append((name_score, unique_count, column))
    return [column for _, _, column in sorted(candidates)[:8]]


def inspect_inputs(abundance: str, taxonomy: str, metadata: str, group_column: str,
                   batch_column: str | None = None,
                   gradient_column: str | None = None) -> InspectionResult:
    paths = {
        "abundance": secure_path(abundance),
        "taxonomy": secure_path(taxonomy),
        "metadata": secure_path(metadata),
    }
    blockers: list[str] = []
    warnings: list[str] = []

    try:
        for name, path in paths.items():
            header = _raw_header(path)
            dup = _duplicates(header)
            if dup:
                blockers.append(f"{name} 存在重复列名：{dup}")
        abd = _read(paths["abundance"])
        tax = _read(paths["taxonomy"])
        meta = _read(paths["metadata"])
    except Exception as exc:
        return InspectionResult(
            status="blocked",
            files=InputFiles(**{k: str(v) for k, v in paths.items()}),
            file_hashes={k: sha256_file(v) for k, v in paths.items()},
            orientation="unknown",
            blockers=blockers + [f"无法解析输入表格：{exc}"],
        )

    if abd.shape[1] < 2 or tax.shape[1] < 2 or meta.shape[1] < 2:
        blockers.append("每张表都必须包含一列 ID 和至少一列数据")

    abd_ids = abd.iloc[:, 0].astype(str).str.strip()
    tax_ids = tax.iloc[:, 0].astype(str).str.strip()
    sample_ids = meta.iloc[:, 0].astype(str).str.strip()
    if abd_ids.duplicated().any():
        blockers.append("丰度表存在重复的行 ID")
    if tax_ids.duplicated().any():
        blockers.append("分类注释表存在重复的 Feature ID")
    if sample_ids.duplicated().any():
        blockers.append("metadata 存在重复的 Sample ID")
    group_column = group_column.strip()
    if not group_column:
        blockers.append("尚未指定分组列；可使用 AI 助手识别实验设计并生成修正预览")
    elif group_column not in meta.columns:
        blockers.append(f"metadata 中找不到分组列：{group_column}")
    if batch_column and batch_column not in meta.columns:
        blockers.append(f"metadata 中找不到批次列：{batch_column}")
    if gradient_column and gradient_column not in meta.columns:
        blockers.append(f"metadata 中找不到梯度列：{gradient_column}")

    abd_columns = [str(x).strip() for x in abd.columns[1:]]
    meta_set = set(sample_ids)
    feature_set = set(tax_ids)
    feature_by_sample = meta_set == set(abd_columns)
    sample_by_feature = meta_set == set(abd_ids) and feature_set == set(abd_columns)
    if feature_by_sample:
        orientation = "feature_by_sample"
        transpose = False
        feature_ids = set(abd_ids)
        numeric = abd.iloc[:, 1:].apply(pd.to_numeric, errors="coerce")
    elif sample_by_feature:
        orientation = "sample_by_feature"
        transpose = True
        feature_ids = set(abd_columns)
        numeric = abd.iloc[:, 1:].apply(pd.to_numeric, errors="coerce")
        warnings.append("丰度表为 Sample × Feature 方向，运行时将自动转置")
    else:
        orientation = "unknown"
        transpose = False
        feature_ids = set(abd_ids)
        numeric = abd.iloc[:, 1:].apply(pd.to_numeric, errors="coerce")
        blockers.append("丰度表方向无法与 metadata 的 Sample ID 和分类表的 Feature ID 对应")

    missing_tax = sorted(feature_ids - feature_set)
    extra_tax = sorted(feature_set - feature_ids)
    if missing_tax:
        blockers.append(f"丰度表中有 {len(missing_tax)} 个 Feature 在分类注释表中缺失")
    if extra_tax:
        warnings.append(f"分类注释表中有 {len(extra_tax)} 个 Feature 不在丰度表中，运行时将忽略")
    if numeric.isna().any().any():
        blockers.append("丰度值必须全部为数值且不能缺失")
    elif (numeric < 0).any().any():
        blockers.append("丰度表包含负数")
    elif ((numeric % 1) != 0).any().any():
        blockers.append("丰度表包含小数；当前流程要求原始计数")

    groups: dict[str, int] = {}
    if group_column in meta.columns:
        if meta[group_column].isna().any():
            blockers.append(f"metadata 分组列 {group_column} 包含缺失值")
        groups = {str(k): int(v) for k, v in meta[group_column].astype(str).value_counts().items()}
        if len(groups) < 2:
            warnings.append("当前只有一个分组，将跳过组间推断统计检验")
        if any(v < 2 for v in groups.values()):
            warnings.append("至少一个分组少于 2 个样本，将跳过组间显著性检验")

    design_summary: dict[str, object] = {}
    if batch_column and batch_column in meta.columns:
        batches: dict[str, object] = {}
        for batch, frame in meta.groupby(batch_column, dropna=False):
            batch_groups = (
                {str(k): int(v) for k, v in frame[group_column].value_counts().items()}
                if group_column in frame.columns
                else {}
            )
            batch_info: dict[str, object] = {"sample_count": len(frame), "groups": batch_groups}
            if gradient_column and gradient_column in frame.columns:
                gradient = pd.to_numeric(frame[gradient_column], errors="coerce")
                observed = sorted({float(x) for x in gradient.dropna()})
                if observed:
                    batch_info["gradient_levels"] = observed
                    batch_info["gradient_complete"] = len(observed) >= 3
            batches[str(batch)] = batch_info
        design_summary = {"batch_column": batch_column, "batches": batches}
        if len(batches) > 1:
            warnings.append("检测到多个实验批次；推断统计将按批次分层处理")

    ranks = [rank for rank in RANK_ORDER if rank in tax.columns]
    if not ranks:
        ranks = [str(c) for c in tax.columns[1:]]
        warnings.append("未找到标准分类层级名称，将使用分类表最后一列")
    selected_rank = "Genus" if "Genus" in ranks else (ranks[-1] if ranks else None)
    if selected_rank != "Genus":
        warnings.append(f"缺少 Genus，群落组成分析将降级使用 {selected_rank}")

    sample_count = len(meta)
    feature_count = len(feature_ids)
    zero_fraction = float((numeric == 0).sum().sum() / max(1, numeric.size)) if not numeric.empty else 0.0
    status = "blocked" if blockers else ("warning" if warnings else "ready")
    return InspectionResult(
        status=status,
        files=InputFiles(**{k: str(v) for k, v in paths.items()}),
        file_hashes={k: sha256_file(v) for k, v in paths.items()},
        orientation=orientation,
        transpose_abundance=transpose,
        sample_count=sample_count,
        feature_count=feature_count,
        groups=groups,
        taxonomy_ranks=ranks,
        taxonomy_columns=[str(column) for column in tax.columns],
        metadata_columns=[str(column) for column in meta.columns],
        suggested_group_columns=_suggest_group_columns(meta),
        selected_taxonomy_rank=selected_rank,
        warnings=warnings,
        blockers=blockers,
        metrics={"zero_fraction": round(zero_fraction, 6)},
        design_summary=design_summary,
    )

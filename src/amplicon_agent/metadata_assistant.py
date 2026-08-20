from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

import pandas as pd

from .models import MetadataProposal
from .security import secure_path, sha256_file


def read_metadata(path: Path) -> pd.DataFrame:
    try:
        frame = pd.read_csv(
            path,
            sep=None,
            engine="python",
            encoding="utf-8-sig",
            dtype=object,
        )
    except Exception as exc:
        raise ValueError(f"无法读取 metadata：{exc}") from exc
    if frame.empty:
        raise ValueError("metadata 没有任何样本行")
    if frame.shape[1] < 1:
        raise ValueError("metadata 至少需要一列 Sample ID")
    return frame


def _even_positions(length: int, limit: int) -> list[int]:
    if length <= limit:
        return list(range(length))
    if limit <= 1:
        return [0]
    return sorted(
        {
            round(index * (length - 1) / (limit - 1))
            for index in range(limit)
        }
    )


def build_metadata_context(
    metadata_path: Path,
    *,
    inspection: dict[str, Any],
    user_context: str,
    priority_columns: list[str] | None = None,
) -> dict[str, Any]:
    """构造紧凑上下文；不发送丰度矩阵，只发送 metadata 摘要和代表行。"""
    frame = read_metadata(metadata_path)
    max_rows = max(10, min(120, int(os.getenv("AI_METADATA_MAX_ROWS", "40"))))
    max_columns = max(3, min(25, int(os.getenv("AI_METADATA_MAX_COLUMNS", "15"))))
    all_columns = [str(value) for value in frame.columns]
    ordered_columns = [all_columns[0]]
    for column in [*(priority_columns or []), *all_columns[1:]]:
        if column in all_columns and column not in ordered_columns:
            ordered_columns.append(column)
    visible_columns = ordered_columns[:max_columns]
    profiles: list[dict[str, Any]] = []
    for column in visible_columns:
        series = frame[column]
        clean = series.dropna().astype(str).map(str.strip)
        unique = list(dict.fromkeys(clean.tolist()))
        profiles.append(
            {
                "column": column,
                "missing_count": int(series.isna().sum()),
                "unique_count": len(unique),
                "unique_values": [value[:160] for value in unique[:20]],
                "unique_values_truncated": len(unique) > 20,
            }
        )
    positions = _even_positions(len(frame), max_rows)
    preview = frame.iloc[positions, :max_columns].where(pd.notna(frame), None)
    rows = [
        {
            str(key): None if value is None else str(value)[:200]
            for key, value in row.items()
        }
        for row in preview.to_dict(orient="records")
    ]
    return {
        "用户说明": user_context.strip(),
        "程序检查结果": {
            "状态": inspection.get("status"),
            "样本数": inspection.get("sample_count"),
            "当前分组": inspection.get("groups", {}),
            "警告": inspection.get("warnings", []),
            "阻断项": inspection.get("blockers", []),
        },
        "metadata": {
            "row_count": len(frame),
            "column_count": frame.shape[1],
            "sample_id_column": str(frame.columns[0]),
            "columns": [str(value) for value in frame.columns],
            "column_profiles": profiles,
            "representative_rows": rows,
            "rows_are_complete": len(frame) <= max_rows,
        },
    }


def metadata_proposal_schema() -> dict[str, Any]:
    return {
        "summary": "中文总结",
        "recommended_group_column": "建议使用的分组列名，必填",
        "recommended_batch_column": "建议批次列名或 null",
        "recommended_gradient_column": "建议梯度列名或 null",
        "column_renames": [
            {"source": "原列名", "target": "新列名", "reason": "中文理由"}
        ],
        "value_mappings": [
            {
                "column": "原列名或重命名后的列名",
                "mapping": {"原值": "规范值"},
                "reason": "中文理由",
            }
        ],
        "sample_group_assignments": [
            {"sample_id": "样本ID", "group": "建议分组", "reason": "中文理由"}
        ],
        "controls": ["对照或参照组"],
        "treatments": ["处理组"],
        "research_question": "建议的中文研究问题",
        "sample_type": "样本类型",
        "gradient_direction": "梯度方向说明",
        "design_notes": "需要写入实验设计的中文说明",
        "questions": ["仍需用户回答的问题"],
        "warnings": ["不能从文件确定的事项"],
    }


def validate_and_preview_proposal(
    metadata_path: Path,
    proposal_value: dict[str, Any],
    preview_path: Path,
) -> dict[str, Any]:
    try:
        proposal = MetadataProposal.model_validate(proposal_value)
    except Exception as exc:
        raise ValueError(f"模型返回的 metadata 建议格式不完整：{exc}") from exc

    frame = read_metadata(metadata_path)
    original_columns = [str(value) for value in frame.columns]
    sample_column = original_columns[0]
    original_sample_ids = frame.iloc[:, 0].tolist()
    working = frame.copy()
    working.columns = [str(value).strip() for value in working.columns]
    changes: list[dict[str, Any]] = []

    rename_map: dict[str, str] = {}
    for item in proposal.column_renames:
        source = item.source.strip()
        target = item.target.strip()
        if not source or not target or source == target:
            continue
        if source not in working.columns:
            raise ValueError(f"模型建议重命名不存在的列：{source}")
        if target in working.columns and target != source:
            raise ValueError(f"列重命名会产生重复列：{target}")
        rename_map[source] = target
        changes.append(
            {
                "type": "column_rename",
                "source": source,
                "target": target,
                "reason": item.reason,
            }
        )
    if rename_map:
        working = working.rename(columns=rename_map)

    renamed_sample_column = rename_map.get(sample_column, sample_column)
    if renamed_sample_column not in working.columns:
        raise ValueError("修正后找不到 Sample ID 列")

    for column in working.columns[1:]:
        if working[column].dtype == object:
            before = working[column].copy()
            working[column] = working[column].map(
                lambda value: value.strip() if isinstance(value, str) else value
            )
            if not before.equals(working[column]):
                changes.append(
                    {
                        "type": "trim_whitespace",
                        "column": str(column),
                        "reason": "清理单元格首尾空格",
                    }
                )

    for item in proposal.value_mappings:
        requested = item.column.strip()
        column = rename_map.get(requested, requested)
        if column not in working.columns:
            raise ValueError(f"模型建议修改不存在的列：{requested}")
        if column == renamed_sample_column:
            raise ValueError("为保护样本对应关系，AI 不允许修改 Sample ID")
        mapping = {str(key): str(value) for key, value in item.mapping.items()}
        observed = {
            str(value)
            for value in working[column].dropna().astype(str).tolist()
        }
        unknown = sorted(set(mapping) - observed)
        if unknown:
            raise ValueError(
                f"列 {column} 的映射包含文件中不存在的值：{unknown[:10]}"
            )
        working[column] = working[column].map(
            lambda value: mapping.get(str(value), value) if pd.notna(value) else value
        )
        if mapping:
            changes.append(
                {
                    "type": "value_mapping",
                    "column": column,
                    "mapping": mapping,
                    "reason": item.reason,
                }
            )

    group_column = rename_map.get(
        proposal.recommended_group_column,
        proposal.recommended_group_column,
    ).strip()
    if not group_column:
        raise ValueError("模型没有给出建议分组列")

    assignments = {
        item.sample_id.strip(): item.group.strip()
        for item in proposal.sample_group_assignments
        if item.sample_id.strip() and item.group.strip()
    }
    if assignments:
        sample_keys = working[renamed_sample_column].astype(str).map(str.strip)
        unknown_samples = sorted(set(assignments) - set(sample_keys))
        if unknown_samples:
            raise ValueError(
                f"模型建议包含文件中不存在的 Sample ID：{unknown_samples[:10]}"
            )
        if group_column not in working.columns:
            working[group_column] = pd.NA
        working[group_column] = [
            assignments.get(sample_id, current)
            for sample_id, current in zip(
                sample_keys,
                working[group_column].tolist(),
                strict=True,
            )
        ]
        changes.append(
            {
                "type": "sample_group_assignments",
                "column": group_column,
                "assignment_count": len(assignments),
                "reason": "根据用户说明和 Sample ID 生成分组预览",
            }
        )

    if group_column not in working.columns:
        raise ValueError(f"建议分组列不存在，且没有完整的样本分组建议：{group_column}")
    if len(working) != len(frame) or working.iloc[:, 0].tolist() != original_sample_ids:
        raise ValueError("安全校验失败：AI 建议改变了 Sample ID 或样本行顺序")
    if working.columns.duplicated().any():
        raise ValueError("修正后出现重复列名")

    preview_path = secure_path(preview_path, must_exist=False)
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    working.to_csv(preview_path, index=False, encoding="utf-8-sig")
    display = working.head(20).where(pd.notna(working), None)
    preview_rows = [
        {str(key): None if value is None else str(value) for key, value in row.items()}
        for row in display.to_dict(orient="records")
    ]
    normalized = proposal.model_dump()
    normalized["recommended_group_column"] = group_column
    for key in ("recommended_batch_column", "recommended_gradient_column"):
        value = normalized.get(key)
        if value:
            normalized[key] = rename_map.get(str(value), str(value))
    return {
        "proposal": normalized,
        "changes": changes,
        "preview_columns": [str(value) for value in working.columns],
        "preview_rows": preview_rows,
        "row_count": len(working),
        "preview_path": str(preview_path),
        "source_hash": sha256_file(metadata_path),
    }


def write_draft(path: Path, value: dict[str, Any]) -> None:
    secure = secure_path(path, must_exist=False)
    secure.write_text(
        json.dumps(value, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

from __future__ import annotations

import csv
from pathlib import Path

import pandas as pd

from .models import InputFiles, InspectionResult
from .security import secure_path, sha256_file


ID_CANDIDATES = {"featureid", "feature_id", "asv", "otu", "id", "sampleid", "sample_id"}
RANK_ORDER = ["Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species"]


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

    for name, path in paths.items():
        header = _raw_header(path)
        dup = _duplicates(header)
        if dup:
            blockers.append(f"{name} contains duplicate columns: {dup}")

    try:
        abd = _read(paths["abundance"])
        tax = _read(paths["taxonomy"])
        meta = _read(paths["metadata"])
    except Exception as exc:
        return InspectionResult(
            status="blocked",
            files=InputFiles(**{k: str(v) for k, v in paths.items()}),
            file_hashes={k: sha256_file(v) for k, v in paths.items()},
            orientation="unknown",
            blockers=blockers + [f"Unable to parse input tables: {exc}"],
        )

    if abd.shape[1] < 2 or tax.shape[1] < 2 or meta.shape[1] < 2:
        blockers.append("Each table must contain an ID column and at least one data column")

    abd_ids = abd.iloc[:, 0].astype(str).str.strip()
    tax_ids = tax.iloc[:, 0].astype(str).str.strip()
    sample_ids = meta.iloc[:, 0].astype(str).str.strip()
    if abd_ids.duplicated().any():
        blockers.append("abundance contains duplicate row IDs")
    if tax_ids.duplicated().any():
        blockers.append("taxonomy contains duplicate Feature IDs")
    if sample_ids.duplicated().any():
        blockers.append("metadata contains duplicate Sample IDs")
    if group_column not in meta.columns:
        blockers.append(f"metadata is missing group column: {group_column}")
    if batch_column and batch_column not in meta.columns:
        blockers.append(f"metadata is missing batch column: {batch_column}")
    if gradient_column and gradient_column not in meta.columns:
        blockers.append(f"metadata is missing gradient column: {gradient_column}")

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
        warnings.append("Abundance table is sample-by-feature and will be transposed")
    else:
        orientation = "unknown"
        transpose = False
        feature_ids = set(abd_ids)
        numeric = abd.iloc[:, 1:].apply(pd.to_numeric, errors="coerce")
        blockers.append("Cannot reconcile abundance orientation with metadata Sample IDs and taxonomy Feature IDs")

    missing_tax = sorted(feature_ids - feature_set)
    extra_tax = sorted(feature_set - feature_ids)
    if missing_tax:
        blockers.append(f"{len(missing_tax)} abundance features are absent from taxonomy")
    if extra_tax:
        warnings.append(f"{len(extra_tax)} taxonomy features are absent from abundance and will be ignored")
    if numeric.isna().any().any():
        blockers.append("Abundance values must all be numeric and non-missing")
    elif (numeric < 0).any().any():
        blockers.append("Abundance contains negative values")
    elif ((numeric % 1) != 0).any().any():
        blockers.append("Abundance contains non-integer values; raw counts are required")

    groups: dict[str, int] = {}
    if group_column in meta.columns:
        if meta[group_column].isna().any():
            blockers.append(f"metadata group column {group_column} contains missing values")
        groups = {str(k): int(v) for k, v in meta[group_column].astype(str).value_counts().items()}
        if len(groups) < 2:
            warnings.append("Only one group is present; inferential group tests will be skipped")
        if any(v < 2 for v in groups.values()):
            warnings.append("At least one group has fewer than two samples; group significance tests will be skipped")

    design_summary: dict[str, object] = {}
    if batch_column and batch_column in meta.columns:
        batches: dict[str, object] = {}
        for batch, frame in meta.groupby(batch_column, dropna=False):
            batch_groups = {str(k): int(v) for k, v in frame[group_column].value_counts().items()}
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
            warnings.append("Multiple experiment batches detected; inferential tests will be stratified by batch")

    ranks = [rank for rank in RANK_ORDER if rank in tax.columns]
    if not ranks:
        ranks = [str(c) for c in tax.columns[1:]]
        warnings.append("No canonical taxonomy rank names found; the last taxonomy column will be used")
    selected_rank = "Genus" if "Genus" in ranks else (ranks[-1] if ranks else None)
    if selected_rank != "Genus":
        warnings.append(f"Genus is unavailable; composition will use {selected_rank}")

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
        selected_taxonomy_rank=selected_rank,
        warnings=warnings,
        blockers=blockers,
        metrics={"zero_fraction": round(zero_fraction, 6)},
        design_summary=design_summary,
    )

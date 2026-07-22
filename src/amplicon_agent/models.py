from __future__ import annotations

from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, Field


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


class InputFiles(BaseModel):
    abundance: str
    taxonomy: str
    metadata: str


class InspectionResult(BaseModel):
    status: Literal["ready", "warning", "blocked"]
    files: InputFiles
    file_hashes: dict[str, str]
    orientation: Literal["feature_by_sample", "sample_by_feature", "unknown"]
    transpose_abundance: bool = False
    sample_count: int = 0
    feature_count: int = 0
    groups: dict[str, int] = Field(default_factory=dict)
    taxonomy_ranks: list[str] = Field(default_factory=list)
    selected_taxonomy_rank: str | None = None
    warnings: list[str] = Field(default_factory=list)
    blockers: list[str] = Field(default_factory=list)
    metrics: dict[str, float | int | str] = Field(default_factory=dict)
    design_summary: dict[str, object] = Field(default_factory=dict)


class AnalysisContract(BaseModel):
    schema_version: str = "1.1"
    plan_id: str
    created_at: str = Field(default_factory=utc_now)
    files: InputFiles
    file_hashes: dict[str, str]
    group_column: str
    batch_column: str | None = None
    gradient_column: str | None = None
    orientation: str
    transpose_abundance: bool
    modules: list[str]
    parameters: dict[str, object]
    warnings: list[str]
    blockers: list[str]
    expected_outputs: list[str]
    approval_status: Literal["pending", "approved", "consumed"] = "pending"
    status: Literal["prepared", "running", "succeeded", "failed"] = "prepared"
    approval_token_hash: str | None = None
    run_directory: str | None = None
    error: str | None = None


class ApprovalResult(BaseModel):
    plan_id: str
    approval_token: str
    expires_when: str = "single use, or whenever inputs/parameters change"


class RunResult(BaseModel):
    plan_id: str
    status: Literal["succeeded", "failed"]
    run_directory: str
    report_path: str | None = None
    validation_path: str | None = None
    error: str | None = None

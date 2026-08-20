from __future__ import annotations

from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


class InputFiles(BaseModel):
    abundance: str
    taxonomy: str
    metadata: str
    tree: str | None = None
    representative_sequences: str | None = None


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
    taxonomy_columns: list[str] = Field(default_factory=list)
    metadata_columns: list[str] = Field(default_factory=list)
    suggested_group_columns: list[str] = Field(default_factory=list)
    selected_taxonomy_rank: str | None = None
    warnings: list[str] = Field(default_factory=list)
    blockers: list[str] = Field(default_factory=list)
    metrics: dict[str, float | int | str] = Field(default_factory=dict)
    design_summary: dict[str, object] = Field(default_factory=dict)


class AnalysisContract(BaseModel):
    schema_version: str = "2.1"
    plan_id: str
    created_at: str = Field(default_factory=utc_now)
    files: InputFiles
    file_hashes: dict[str, str]
    group_column: str
    batch_column: str | None = None
    gradient_column: str | None = None
    project_design: dict[str, object] = Field(default_factory=dict)
    analysis_scope: Literal["full", "targeted"] = "targeted"
    orientation: str
    transpose_abundance: bool
    functions: list[str]
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


class AnalysisInterpretation(BaseModel):
    project_summary: str
    key_findings: list[dict[str, object]] = Field(default_factory=list)
    section_interpretations: dict[str, str] = Field(default_factory=dict)
    supported_conclusions: list[str] = Field(default_factory=list)
    unsupported_conclusions: list[str] = Field(default_factory=list)
    limitations: list[str] = Field(default_factory=list)
    next_steps: list[str] = Field(default_factory=list)


class MetadataColumnRename(BaseModel):
    model_config = ConfigDict(extra="ignore")

    source: str
    target: str
    reason: str = ""


class MetadataValueMapping(BaseModel):
    model_config = ConfigDict(extra="ignore")

    column: str
    mapping: dict[str, str] = Field(default_factory=dict)
    reason: str = ""


class MetadataSampleAssignment(BaseModel):
    model_config = ConfigDict(extra="ignore")

    sample_id: str
    group: str
    reason: str = ""


class MetadataProposal(BaseModel):
    """模型提出、程序验证后才能应用的 metadata 整理建议。"""

    model_config = ConfigDict(extra="ignore")

    summary: str
    recommended_group_column: str
    recommended_batch_column: str | None = None
    recommended_gradient_column: str | None = None
    column_renames: list[MetadataColumnRename] = Field(default_factory=list)
    value_mappings: list[MetadataValueMapping] = Field(default_factory=list)
    sample_group_assignments: list[MetadataSampleAssignment] = Field(
        default_factory=list
    )
    controls: list[str] = Field(default_factory=list)
    treatments: list[str] = Field(default_factory=list)
    research_question: str = ""
    sample_type: str = ""
    gradient_direction: str = ""
    design_notes: str = ""
    questions: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)

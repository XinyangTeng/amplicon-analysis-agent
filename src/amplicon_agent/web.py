from __future__ import annotations

import json
import os
import re
import shutil
import uuid
from pathlib import Path
from typing import Annotated, Any

from fastapi import BackgroundTasks, Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .function_registry import list_functions
from .model_client import (
    chat_completion,
    model_presets,
    public_model_config,
    save_model_config,
)
from .security import secure_path, workspace_root
from .service import AgentService
from .store import PlanStore


STATIC = Path(__file__).with_name("web_static")
BASELINE_FUNCTIONS = ["qc", "alpha", "beta", "composition"]
ALLOWED_SUFFIXES = {
    "abundance": {".csv", ".tsv", ".txt"},
    "taxonomy": {".csv", ".tsv", ".txt"},
    "metadata": {".csv", ".tsv", ".txt"},
    "tree": {".nwk", ".tree", ".tre", ".txt"},
    "representative_sequences": {".fasta", ".fa", ".fna"},
}

app = FastAPI(
    title="Amplicon Analysis Agent Web",
    description="Plan-first, auditable amplicon microbiome analysis",
    version="0.3.0",
)


def get_service() -> AgentService:
    return AgentService()


def require_token(authorization: str | None = Header(default=None)) -> None:
    expected = os.getenv("AMPLICON_WEB_TOKEN", "").strip()
    if expected and authorization != f"Bearer {expected}":
        raise HTTPException(401, "需要有效的访问令牌")


def api_error(exc: Exception) -> HTTPException:
    if isinstance(exc, HTTPException):
        return exc
    return HTTPException(400, str(exc))


def _upload_root(upload_id: str) -> Path:
    try:
        normalized = str(uuid.UUID(upload_id))
    except ValueError as exc:
        raise HTTPException(400, "无效的上传编号") from exc
    return secure_path(Path("uploads") / normalized, must_exist=True)


async def save_upload(upload: UploadFile, upload_dir: Path, role: str) -> str:
    suffix = Path(upload.filename or "").suffix.lower()
    if suffix not in ALLOWED_SUFFIXES[role]:
        allowed = "、".join(sorted(ALLOWED_SUFFIXES[role]))
        raise HTTPException(400, f"{role} 文件类型不支持；允许：{allowed}")
    limit = int(os.getenv("AMPLICON_MAX_UPLOAD_MB", "200")) * 1024 * 1024
    target = upload_dir / f"{role}{suffix}"
    written = 0
    with target.open("wb") as output:
        while chunk := await upload.read(1024 * 1024):
            written += len(chunk)
            if written > limit:
                output.close()
                target.unlink(missing_ok=True)
                raise HTTPException(413, f"{role} 文件超过 {limit // 1024 // 1024} MB 限制")
            output.write(chunk)
    if written == 0:
        target.unlink(missing_ok=True)
        raise HTTPException(400, f"{role} 文件为空")
    return str(target.relative_to(workspace_root())).replace("\\", "/")


def _read_upload_manifest(upload_id: str) -> dict[str, str]:
    upload_dir = _upload_root(upload_id)
    manifest_path = upload_dir / "upload.json"
    if not manifest_path.exists():
        raise HTTPException(404, "上传记录不存在")
    value = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise HTTPException(400, "上传记录损坏")
    return {str(key): str(item) for key, item in value.items() if item}


@app.middleware("http")
async def security_headers(request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "same-origin"
    response.headers["X-Frame-Options"] = "SAMEORIGIN"
    response.headers["Cache-Control"] = "no-store" if request.url.path.startswith("/api/") else "public, max-age=300"
    return response


@app.get("/api/health")
def health() -> dict[str, Any]:
    model = public_model_config()
    return {
        "status": "ok",
        "version": app.version,
        "model": {
            "provider": model["provider"],
            "api_key_configured": model["api_key_configured"],
        },
    }


@app.get("/api/functions", dependencies=[Depends(require_token)])
def functions() -> dict[str, Any]:
    functions_data = list_functions()
    categories = sorted({str(item["category"]) for item in functions_data})
    return {
        "baseline": BASELINE_FUNCTIONS,
        "categories": categories,
        "functions": functions_data,
    }


@app.get("/api/model/presets", dependencies=[Depends(require_token)])
def get_model_presets() -> dict[str, Any]:
    return {"presets": model_presets()}


@app.get("/api/model", dependencies=[Depends(require_token)])
def get_model() -> dict[str, Any]:
    return public_model_config()


class ModelSettings(BaseModel):
    provider: str = "openai_compatible"
    protocol: str = "openai"
    base_url: str
    model: str
    api_key: str | None = None
    persist_api_key: bool = False
    clear_api_key: bool = False


@app.put("/api/model", dependencies=[Depends(require_token)])
def put_model(settings: ModelSettings) -> dict[str, Any]:
    try:
        return save_model_config(
            settings.provider,
            settings.protocol,
            settings.base_url,
            settings.model,
            api_key=settings.api_key,
            persist_api_key=settings.persist_api_key,
            clear_api_key=settings.clear_api_key,
        )
    except Exception as exc:
        raise api_error(exc)


@app.post("/api/model/test", dependencies=[Depends(require_token)])
def test_model() -> dict[str, str]:
    try:
        answer = chat_completion(
            [{"role": "user", "content": "只回复 OK 两个字母，不要添加其他内容。"}]
        )
        return {"status": "ok", "reply": answer[:200]}
    except Exception as exc:
        raise api_error(exc)


@app.post("/api/uploads/inspect", dependencies=[Depends(require_token)])
async def inspect_upload(
    abundance: Annotated[UploadFile, File(...)],
    taxonomy: Annotated[UploadFile, File(...)],
    metadata: Annotated[UploadFile, File(...)],
    group_column: Annotated[str, Form(...)],
    batch_column: Annotated[str | None, Form()] = None,
    gradient_column: Annotated[str | None, Form()] = None,
    tree: Annotated[UploadFile | None, File()] = None,
    representative_sequences: Annotated[UploadFile | None, File()] = None,
) -> dict[str, Any]:
    upload_id = str(uuid.uuid4())
    upload_dir = secure_path(Path("uploads") / upload_id, must_exist=False)
    upload_dir.mkdir(parents=True, exist_ok=False)
    try:
        paths = {
            "abundance": await save_upload(abundance, upload_dir, "abundance"),
            "taxonomy": await save_upload(taxonomy, upload_dir, "taxonomy"),
            "metadata": await save_upload(metadata, upload_dir, "metadata"),
        }
        if tree and tree.filename:
            paths["tree"] = await save_upload(tree, upload_dir, "tree")
        if representative_sequences and representative_sequences.filename:
            paths["representative_sequences"] = await save_upload(
                representative_sequences, upload_dir, "representative_sequences"
            )
        (upload_dir / "upload.json").write_text(
            json.dumps(paths, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        inspection = get_service().inspect(
            paths["abundance"],
            paths["taxonomy"],
            paths["metadata"],
            group_column.strip(),
            batch_column.strip() if batch_column else None,
            gradient_column.strip() if gradient_column else None,
        )
        return {"upload_id": upload_id, "files": paths, "inspection": inspection}
    except Exception as exc:
        shutil.rmtree(upload_dir, ignore_errors=True)
        raise api_error(exc)


class PlanRequest(BaseModel):
    upload_id: str
    group_column: str
    batch_column: str | None = None
    gradient_column: str | None = None
    research_question: str = Field(min_length=3)
    sample_type: str = Field(min_length=1)
    controls: list[str] = Field(min_length=1)
    treatments: list[str] = Field(min_length=1)
    analysis_scope: str = "targeted"
    functions: list[str] = Field(default_factory=lambda: BASELINE_FUNCTIONS.copy())
    permutations: int = 999
    top_n: int = 10
    function_parameters: dict[str, Any] = Field(default_factory=dict)
    design_notes: str | None = None


@app.post("/api/plans", dependencies=[Depends(require_token)])
def create_plan(request: PlanRequest) -> dict[str, Any]:
    try:
        paths = _read_upload_manifest(request.upload_id)
        selected = list(dict.fromkeys([*BASELINE_FUNCTIONS, *request.functions]))
        design = {
            "research_question": request.research_question.strip(),
            "sample_type": request.sample_type.strip(),
            "controls": [item.strip() for item in request.controls if item.strip()],
            "treatments": [item.strip() for item in request.treatments if item.strip()],
            "design_notes": (request.design_notes or "").strip(),
        }
        return get_service().prepare(
            paths["abundance"],
            paths["taxonomy"],
            paths["metadata"],
            request.group_column.strip(),
            functions=selected,
            permutations=request.permutations,
            top_n=request.top_n,
            batch_column=request.batch_column.strip() if request.batch_column else None,
            gradient_column=request.gradient_column.strip() if request.gradient_column else None,
            tree=paths.get("tree"),
            representative_sequences=paths.get("representative_sequences"),
            function_parameters=request.function_parameters,
            project_design=design,
            analysis_scope=request.analysis_scope,
        )
    except Exception as exc:
        raise api_error(exc)


@app.get("/api/plans", dependencies=[Depends(require_token)])
def recent_plans() -> dict[str, Any]:
    store = PlanStore()
    plans: list[dict[str, Any]] = []
    for path in sorted(store.root.glob("*.json"), key=lambda item: item.stat().st_mtime, reverse=True)[:25]:
        try:
            contract = store.load(path.stem)
        except Exception:
            continue
        plans.append(
            {
                "plan_id": contract.plan_id,
                "created_at": contract.created_at,
                "status": contract.status,
                "approval_status": contract.approval_status,
                "research_question": contract.project_design.get("research_question", ""),
                "functions": contract.functions,
            }
        )
    return {"plans": plans}


class ApprovalRequest(BaseModel):
    confirmation: str


@app.post("/api/plans/{plan_id}/approve", dependencies=[Depends(require_token)])
def approve_plan(plan_id: str, request: ApprovalRequest) -> dict[str, Any]:
    try:
        return get_service().approve(plan_id, request.confirmation).model_dump()
    except Exception as exc:
        raise api_error(exc)


class RunRequest(BaseModel):
    approval_token: str


@app.post("/api/plans/{plan_id}/run", dependencies=[Depends(require_token)])
def run_plan(plan_id: str, request: RunRequest, background_tasks: BackgroundTasks) -> dict[str, str]:
    try:
        service = get_service()
        contract = service.status(plan_id)
        if contract["approval_status"] != "approved":
            raise ValueError("分析计划尚未审批")
        background_tasks.add_task(service.run, plan_id, request.approval_token)
        return {"plan_id": plan_id, "status": "queued"}
    except Exception as exc:
        raise api_error(exc)


@app.get("/api/plans/{plan_id}", dependencies=[Depends(require_token)])
def plan_status(plan_id: str) -> dict[str, Any]:
    try:
        return get_service().status(plan_id)
    except Exception as exc:
        raise api_error(exc)


@app.get("/api/plans/{plan_id}/validation", dependencies=[Depends(require_token)])
def plan_validation(plan_id: str) -> dict[str, Any]:
    try:
        return get_service().validate(plan_id)
    except Exception as exc:
        raise api_error(exc)


def _extract_json(value: str) -> dict[str, Any]:
    text = value.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    parsed = json.loads(text)
    if not isinstance(parsed, dict):
        raise ValueError("模型解释必须是 JSON 对象")
    return parsed


@app.post("/api/plans/{plan_id}/interpret", dependencies=[Depends(require_token)])
def interpret(plan_id: str) -> dict[str, Any]:
    try:
        service = get_service()
        context = service.report_context(plan_id)
        schema_hint = {
            "project_summary": "string",
            "key_findings": [{"title": "string", "evidence": "string", "interpretation": "string"}],
            "section_interpretations": {"section_name": "string"},
            "supported_conclusions": ["string"],
            "unsupported_conclusions": ["string"],
            "limitations": ["string"],
            "next_steps": ["string"],
        }
        result = chat_completion(
            [
                {
                    "role": "system",
                    "content": (
                        "你是微生物组统计分析专家。只能根据已校验结果和实验设计解释，"
                        "必须区分相关性与因果性，不得虚构未提供的对照或处理。"
                        "输出严格 JSON，不要使用 Markdown。"
                    ),
                },
                {
                    "role": "user",
                    "content": (
                        "请按给定结构生成项目化解释。\n"
                        f"结构：{json.dumps(schema_hint, ensure_ascii=False)}\n"
                        f"已验证数据：{json.dumps(context, ensure_ascii=False)}"
                    ),
                },
            ],
            response_format={"type": "json_object"},
        )
        return service.save_interpretation(plan_id, _extract_json(result))
    except Exception as exc:
        raise api_error(exc)


@app.get("/api/plans/{plan_id}/report", dependencies=[Depends(require_token)])
def report(plan_id: str):
    try:
        path = secure_path(get_service().report(plan_id)["report_path"])
        return FileResponse(
            path,
            media_type="text/html; charset=utf-8",
            headers={"Content-Disposition": f'inline; filename="amplicon-{plan_id}.html"'},
        )
    except Exception as exc:
        raise api_error(exc)


app.mount("/", StaticFiles(directory=STATIC, html=True), name="web")


def main() -> None:
    import uvicorn

    uvicorn.run(
        "amplicon_agent.web:app",
        host=os.getenv("WEB_HOST", "0.0.0.0"),
        port=int(os.getenv("WEB_PORT", "8000")),
        reload=os.getenv("WEB_RELOAD", "").lower() in {"1", "true", "yes"},
    )


if __name__ == "__main__":
    main()

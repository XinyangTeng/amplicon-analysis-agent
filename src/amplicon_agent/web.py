from __future__ import annotations

import html
import json
import os
import re
import secrets
import shutil
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated, Any, AsyncIterator

from fastapi import Cookie, Depends, FastAPI, File, Form, Header, HTTPException, Request, Response, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, PlainTextResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field, SecretStr

from .auth import AuthStore, AuthUser, SessionIdentity
from .function_registry import list_functions
from .model_client import (
    chat_completion,
    model_presets,
    public_model_config,
    resolved_model_config,
)
from .security import secure_path, user_workspace, workspace_root, workspace_scope
from .service import AgentService
from .store import PlanStore
from .tasks import celery_app, enqueue_analysis


STATIC = Path(__file__).with_name("web_static")
SESSION_COOKIE = "amplicon_session"
BASELINE_FUNCTIONS = ["qc", "alpha", "beta", "composition"]
ALLOWED_SUFFIXES = {
    "abundance": {".csv", ".tsv", ".txt"},
    "taxonomy": {".csv", ".tsv", ".txt"},
    "metadata": {".csv", ".tsv", ".txt"},
    "tree": {".nwk", ".tree", ".tre", ".txt"},
    "representative_sequences": {".fasta", ".fa", ".fna"},
}
SAFE_METHODS = {"GET", "HEAD", "OPTIONS"}


def _truthy(name: str, default: str = "") -> bool:
    return os.getenv(name, default).strip().lower() in {"1", "true", "yes", "on"}


@asynccontextmanager
async def lifespan(_: FastAPI):
    bootstrap = os.getenv("AMPLICON_BOOTSTRAP_INVITE", "").strip()
    if bootstrap:
        AuthStore().ensure_bootstrap_invite(bootstrap)
    yield


app = FastAPI(
    title="BioAgent 扩增子分析工作台",
    description="邀请制、先计划后执行、可审计的扩增子微生物组分析",
    version="0.4.0",
    lifespan=lifespan,
)


def api_error(exc: Exception) -> HTTPException:
    if isinstance(exc, HTTPException):
        return exc
    if isinstance(exc, FileNotFoundError):
        return HTTPException(404, "资源不存在或已经过期")
    return HTTPException(400, str(exc))


def _cookie_secure() -> bool:
    return _truthy("AMPLICON_COOKIE_SECURE")


def _set_session_cookie(response: Response, token: str) -> None:
    max_age = int(os.getenv("AMPLICON_SESSION_DAYS", "7")) * 86400
    response.set_cookie(
        SESSION_COOKIE,
        token,
        max_age=max_age,
        httponly=True,
        secure=_cookie_secure(),
        samesite="lax",
        path="/",
    )


def _page(name: str, replacements: dict[str, str] | None = None) -> HTMLResponse:
    text = (STATIC / name).read_text(encoding="utf-8")
    for key, value in (replacements or {}).items():
        text = text.replace(f"{{{{{key}}}}}", html.escape(value))
    return HTMLResponse(text)


def _public_base_url() -> str:
    return os.getenv("PUBLIC_BASE_URL", "").strip().rstrip("/")


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    if request.url.path.startswith(("/api/", "/app", "/login")):
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Robots-Tag"] = "noindex, nofollow"
    else:
        response.headers.setdefault("Cache-Control", "public, max-age=300")
    if "/report" in request.url.path:
        response.headers["Content-Security-Policy"] = (
            "default-src 'none'; img-src data: blob:; style-src 'unsafe-inline'; "
            "font-src data:; base-uri 'none'; frame-ancestors 'none'"
        )
    else:
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; img-src 'self' data:; style-src 'self'; "
            "script-src 'self'; connect-src 'self'; object-src 'none'; "
            "base-uri 'self'; frame-ancestors 'none'; form-action 'self'"
        )
    return response


@app.get("/", response_class=HTMLResponse)
def landing_page(request: Request) -> HTMLResponse:
    base = _public_base_url() or str(request.base_url).rstrip("/")
    return _page(
        "landing.html",
        {
            "CANONICAL_URL": f"{base}/",
        },
    )


@app.get("/login", response_class=HTMLResponse)
def login_page() -> HTMLResponse:
    return _page("login.html")


@app.get("/app", response_class=HTMLResponse)
def workbench_page(
    amplicon_session: Annotated[str | None, Cookie()] = None,
) -> HTMLResponse:
    if not amplicon_session or not AuthStore().authenticate_session(amplicon_session):
        from fastapi.responses import RedirectResponse

        return RedirectResponse("/login?return=/app", status_code=303)
    return _page("index.html")


@app.get("/privacy", response_class=HTMLResponse)
def privacy_page() -> HTMLResponse:
    return _page(
        "privacy.html",
        {
            "RETENTION_DAYS": os.getenv("AMPLICON_RETENTION_DAYS", "7"),
            "PRIVACY_CONTACT": os.getenv(
                "PRIVACY_CONTACT",
                "项目维护者（正式上线前配置联系邮箱）",
            ),
        },
    )


@app.get("/robots.txt", response_class=PlainTextResponse)
def robots(request: Request) -> str:
    base = _public_base_url() or str(request.base_url).rstrip("/")
    sitemap = f"\nSitemap: {base}/sitemap.xml"
    return f"User-agent: *\nAllow: /\nDisallow: /app\nDisallow: /api/\nDisallow: /login{sitemap}\n"


@app.get("/sitemap.xml", response_class=Response)
def sitemap(request: Request) -> Response:
    base = _public_base_url() or str(request.base_url).rstrip("/")
    value = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
        f"<url><loc>{html.escape(base)}/</loc></url>"
        f"<url><loc>{html.escape(base)}/privacy</loc></url>"
        "</urlset>"
    )
    return Response(value, media_type="application/xml")


@app.get("/sw.js")
def service_worker() -> FileResponse:
    return FileResponse(
        STATIC / "sw.js",
        media_type="application/javascript",
        headers={
            "Service-Worker-Allowed": "/",
            "Cache-Control": "no-cache",
        },
    )


@app.get("/api/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "version": app.version,
        "queue": "celery",
    }


@app.get("/api/public-config")
def public_config() -> dict[str, Any]:
    return {
        "invitation_only": True,
        "retention_days": int(os.getenv("AMPLICON_RETENTION_DAYS", "7")),
        "max_upload_mb": int(os.getenv("AMPLICON_MAX_UPLOAD_MB", "200")),
        "max_total_upload_mb": int(
            os.getenv("AMPLICON_MAX_TOTAL_UPLOAD_MB", "500")
        ),
        "privacy_contact": os.getenv("PRIVACY_CONTACT", ""),
    }


class RegisterRequest(BaseModel):
    email: str
    password: str
    display_name: str = ""
    invite_code: str
    privacy_accepted: bool = False


class LoginRequest(BaseModel):
    email: str
    password: str


def _auth_response(identity: SessionIdentity) -> dict[str, Any]:
    return {
        "status": "authenticated",
        "user": AuthStore().user_summary(
            identity.user,
            csrf_token=identity.csrf_token,
        ),
        "session_expires_at": identity.session_expires_at,
    }


@app.post("/api/auth/register")
def register(request: RegisterRequest, response: Response) -> dict[str, Any]:
    try:
        store = AuthStore()
        user = store.register(
            email=request.email,
            password=request.password,
            display_name=request.display_name,
            invite_code=request.invite_code,
            privacy_accepted=request.privacy_accepted,
        )
        token, identity = store.create_session(user.user_id)
        _set_session_cookie(response, token)
        return _auth_response(identity)
    except Exception as exc:
        raise api_error(exc)


@app.post("/api/auth/login")
def login(request: LoginRequest, response: Response) -> dict[str, Any]:
    try:
        store = AuthStore()
        user = store.authenticate_password(request.email, request.password)
        token, identity = store.create_session(user.user_id)
        _set_session_cookie(response, token)
        return _auth_response(identity)
    except Exception as exc:
        raise api_error(exc)


def current_identity(
    amplicon_session: Annotated[str | None, Cookie()] = None,
) -> SessionIdentity:
    if not amplicon_session:
        raise HTTPException(401, "请先登录")
    identity = AuthStore().authenticate_session(amplicon_session)
    if not identity:
        raise HTTPException(401, "登录已过期，请重新登录")
    return identity


async def scoped_identity(
    request: Request,
    identity: Annotated[SessionIdentity, Depends(current_identity)],
    x_csrf_token: Annotated[str | None, Header()] = None,
) -> AsyncIterator[SessionIdentity]:
    if request.method not in SAFE_METHODS and not (
        x_csrf_token
        and secrets.compare_digest(x_csrf_token, identity.csrf_token)
    ):
        raise HTTPException(403, "页面校验信息已过期，请刷新后重试")
    with workspace_scope(user_workspace(identity.user.user_id)):
        yield identity


@app.get("/api/auth/me")
def me(
    identity: Annotated[SessionIdentity, Depends(current_identity)],
) -> dict[str, Any]:
    return AuthStore().user_summary(
        identity.user,
        csrf_token=identity.csrf_token,
    )


@app.post("/api/auth/logout")
def logout(
    response: Response,
    identity: Annotated[SessionIdentity, Depends(scoped_identity)],
    amplicon_session: Annotated[str | None, Cookie()] = None,
) -> dict[str, str]:
    del identity
    if amplicon_session:
        AuthStore().delete_session(amplicon_session)
    response.delete_cookie(SESSION_COOKIE, path="/")
    return {"status": "logged_out"}


class DeleteRequest(BaseModel):
    confirmation: str


def _delete_user_workspace(user_id: str) -> None:
    target = user_workspace(user_id).resolve()
    target.relative_to(workspace_root().resolve())
    if target.exists():
        shutil.rmtree(target)


@app.delete("/api/me/data")
def delete_my_data(
    request: DeleteRequest,
    identity: Annotated[SessionIdentity, Depends(scoped_identity)],
) -> dict[str, Any]:
    if request.confirmation != "DELETE MY DATA":
        raise HTTPException(400, "确认文本必须为 DELETE MY DATA")
    store = AuthStore()
    tasks = store.cancel_user_jobs(identity.user.user_id)
    for task_id in tasks:
        try:
            celery_app.control.revoke(task_id, terminate=True, signal="SIGTERM")
        except Exception:
            pass
    _delete_user_workspace(identity.user.user_id)
    store.purge_user_data_records(identity.user.user_id)
    return {"status": "deleted", "cancelled_tasks": len(tasks)}


@app.delete("/api/me/account")
def delete_my_account(
    request: DeleteRequest,
    response: Response,
    identity: Annotated[SessionIdentity, Depends(scoped_identity)],
) -> dict[str, str]:
    if request.confirmation != "DELETE MY ACCOUNT":
        raise HTTPException(400, "确认文本必须为 DELETE MY ACCOUNT")
    store = AuthStore()
    tasks = store.cancel_user_jobs(identity.user.user_id)
    for task_id in tasks:
        try:
            celery_app.control.revoke(task_id, terminate=True, signal="SIGTERM")
        except Exception:
            pass
    _delete_user_workspace(identity.user.user_id)
    store.delete_account(identity.user.user_id)
    response.delete_cookie(SESSION_COOKIE, path="/")
    return {"status": "account_deleted"}


@app.get("/api/functions")
def functions(
    identity: Annotated[SessionIdentity, Depends(scoped_identity)],
) -> dict[str, Any]:
    del identity
    functions_data = list_functions()
    categories = sorted({str(item["category"]) for item in functions_data})
    return {
        "baseline": BASELINE_FUNCTIONS,
        "categories": categories,
        "functions": functions_data,
    }


@app.get("/api/model/presets")
def get_model_presets(
    identity: Annotated[SessionIdentity, Depends(scoped_identity)],
) -> dict[str, Any]:
    del identity
    return {"presets": model_presets()}


@app.get("/api/model")
def get_model(
    identity: Annotated[SessionIdentity, Depends(scoped_identity)],
) -> dict[str, Any]:
    config = public_model_config()
    return {
        "server_default": config,
        "quota": AuthStore().user_summary(identity.user),
        "byok_supported": True,
        "api_key_storage": "request_only",
    }


class ModelCallSettings(BaseModel):
    provider: str | None = None
    protocol: str | None = None
    base_url: str | None = None
    model: str | None = None
    api_key: SecretStr | None = None

    def overrides(self) -> dict[str, Any]:
        value = self.model_dump(exclude_none=True)
        if self.api_key:
            value["api_key"] = self.api_key.get_secret_value()
        return value


def _model_call(
    *,
    user: AuthUser,
    settings: ModelCallSettings | None,
    messages: list[dict[str, str]],
    response_format: dict[str, Any] | None = None,
) -> str:
    overrides = settings.overrides() if settings else None
    config = resolved_model_config(overrides)
    use_server_key = not bool(settings and settings.api_key)
    if not config.get("api_key"):
        raise ValueError("共享模型尚未配置；请填写自己的 API Key")
    store = AuthStore()
    usage_id = store.reserve_model_call(
        user=user,
        provider=str(config["provider"]),
        use_server_key=use_server_key,
    )
    try:
        result = chat_completion(
            messages,
            response_format=response_format,
            config_override=overrides,
        )
        store.finish_model_call(usage_id, succeeded=True)
        return result
    except Exception:
        store.finish_model_call(usage_id, succeeded=False)
        raise


@app.post("/api/model/test")
def test_model(
    settings: ModelCallSettings | None,
    identity: Annotated[SessionIdentity, Depends(scoped_identity)],
) -> dict[str, str]:
    try:
        answer = _model_call(
            user=identity.user,
            settings=settings,
            messages=[
                {
                    "role": "user",
                    "content": "只回复 OK 两个字母，不要添加其他内容。",
                }
            ],
        )
        return {"status": "ok", "reply": answer[:200]}
    except Exception as exc:
        raise api_error(exc)


def _upload_root(upload_id: str) -> Path:
    try:
        normalized = str(uuid.UUID(upload_id))
    except ValueError as exc:
        raise HTTPException(400, "无效的上传编号") from exc
    return secure_path(Path("uploads") / normalized, must_exist=True)


def _directory_size(path: Path) -> int:
    return sum(item.stat().st_size for item in path.rglob("*") if item.is_file())


async def save_upload(
    upload: UploadFile,
    upload_dir: Path,
    role: str,
) -> tuple[str, int]:
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
                raise HTTPException(
                    413,
                    f"{role} 文件超过 {limit // 1024 // 1024} MB 限制",
                )
            output.write(chunk)
    if written == 0:
        target.unlink(missing_ok=True)
        raise HTTPException(400, f"{role} 文件为空")
    return (
        str(target.relative_to(workspace_root())).replace("\\", "/"),
        written,
    )


def _read_upload_manifest(upload_id: str, user_id: str) -> dict[str, str]:
    if not AuthStore().owns_resource(
        kind="upload",
        resource_id=upload_id,
        user_id=user_id,
    ):
        raise HTTPException(404, "上传记录不存在或已经过期")
    upload_dir = _upload_root(upload_id)
    manifest_path = upload_dir / "upload.json"
    if not manifest_path.exists():
        raise HTTPException(404, "上传记录不存在")
    value = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise HTTPException(400, "上传记录损坏")
    return {str(key): str(item) for key, item in value.items() if item}


@app.post("/api/uploads/inspect")
async def inspect_upload(
    abundance: Annotated[UploadFile, File(...)],
    taxonomy: Annotated[UploadFile, File(...)],
    metadata: Annotated[UploadFile, File(...)],
    group_column: Annotated[str, Form(...)],
    identity: Annotated[SessionIdentity, Depends(scoped_identity)],
    batch_column: Annotated[str | None, Form()] = None,
    gradient_column: Annotated[str | None, Form()] = None,
    tree: Annotated[UploadFile | None, File()] = None,
    representative_sequences: Annotated[UploadFile | None, File()] = None,
) -> dict[str, Any]:
    upload_id = str(uuid.uuid4())
    upload_dir = secure_path(Path("uploads") / upload_id, must_exist=False)
    existing_bytes = _directory_size(workspace_root())
    user_limit = int(
        os.getenv("AMPLICON_MAX_USER_STORAGE_MB", "2048")
    ) * 1024 * 1024
    if existing_bytes >= user_limit:
        raise HTTPException(413, "个人存储空间已满，请先删除历史数据")
    upload_dir.mkdir(parents=True, exist_ok=False)
    try:
        paths: dict[str, str] = {}
        total = 0
        for role, upload in (
            ("abundance", abundance),
            ("taxonomy", taxonomy),
            ("metadata", metadata),
        ):
            paths[role], written = await save_upload(upload, upload_dir, role)
            total += written
        if tree and tree.filename:
            paths["tree"], written = await save_upload(tree, upload_dir, "tree")
            total += written
        if representative_sequences and representative_sequences.filename:
            paths["representative_sequences"], written = await save_upload(
                representative_sequences,
                upload_dir,
                "representative_sequences",
            )
            total += written
        request_limit = int(
            os.getenv("AMPLICON_MAX_TOTAL_UPLOAD_MB", "500")
        ) * 1024 * 1024
        if total > request_limit or existing_bytes + total > user_limit:
            raise HTTPException(413, "本次上传或个人存储总量超过限制")
        (upload_dir / "upload.json").write_text(
            json.dumps(paths, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        inspection = AgentService().inspect(
            paths["abundance"],
            paths["taxonomy"],
            paths["metadata"],
            group_column.strip(),
            batch_column.strip() if batch_column else None,
            gradient_column.strip() if gradient_column else None,
        )
        AuthStore().register_resource(
            kind="upload",
            resource_id=upload_id,
            user=identity.user,
        )
        return {
            "upload_id": upload_id,
            "files": paths,
            "inspection": inspection,
            "expires_in_days": identity.user.retention_days,
        }
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


@app.post("/api/plans")
def create_plan(
    request: PlanRequest,
    identity: Annotated[SessionIdentity, Depends(scoped_identity)],
) -> dict[str, Any]:
    try:
        paths = _read_upload_manifest(request.upload_id, identity.user.user_id)
        selected = list(dict.fromkeys([*BASELINE_FUNCTIONS, *request.functions]))
        design = {
            "research_question": request.research_question.strip(),
            "sample_type": request.sample_type.strip(),
            "controls": [item.strip() for item in request.controls if item.strip()],
            "treatments": [
                item.strip() for item in request.treatments if item.strip()
            ],
            "design_notes": (request.design_notes or "").strip(),
        }
        contract = AgentService().prepare(
            paths["abundance"],
            paths["taxonomy"],
            paths["metadata"],
            request.group_column.strip(),
            functions=selected,
            permutations=request.permutations,
            top_n=request.top_n,
            batch_column=request.batch_column.strip()
            if request.batch_column
            else None,
            gradient_column=request.gradient_column.strip()
            if request.gradient_column
            else None,
            tree=paths.get("tree"),
            representative_sequences=paths.get("representative_sequences"),
            function_parameters=request.function_parameters,
            project_design=design,
            analysis_scope=request.analysis_scope,
        )
        AuthStore().register_resource(
            kind="plan",
            resource_id=contract["plan_id"],
            user=identity.user,
        )
        return contract
    except Exception as exc:
        raise api_error(exc)


def _require_plan_owner(plan_id: str, user_id: str) -> None:
    if not AuthStore().owns_resource(
        kind="plan",
        resource_id=plan_id,
        user_id=user_id,
    ):
        raise HTTPException(404, "分析计划不存在或已经过期")


@app.get("/api/plans")
def recent_plans(
    identity: Annotated[SessionIdentity, Depends(scoped_identity)],
) -> dict[str, Any]:
    store = PlanStore()
    plans: list[dict[str, Any]] = []
    for path in sorted(
        store.root.glob("*.json"),
        key=lambda item: item.stat().st_mtime,
        reverse=True,
    )[:25]:
        if not AuthStore().owns_resource(
            kind="plan",
            resource_id=path.stem,
            user_id=identity.user.user_id,
        ):
            continue
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
                "research_question": contract.project_design.get(
                    "research_question",
                    "",
                ),
                "functions": contract.functions,
                "job": AuthStore().job_status(
                    plan_id=contract.plan_id,
                    user_id=identity.user.user_id,
                ),
            }
        )
    return {"plans": plans}


class ApprovalRequest(BaseModel):
    confirmation: str


@app.post("/api/plans/{plan_id}/approve")
def approve_plan(
    plan_id: str,
    request: ApprovalRequest,
    identity: Annotated[SessionIdentity, Depends(scoped_identity)],
) -> dict[str, Any]:
    try:
        _require_plan_owner(plan_id, identity.user.user_id)
        return AgentService().approve(plan_id, request.confirmation).model_dump()
    except Exception as exc:
        raise api_error(exc)


class RunRequest(BaseModel):
    approval_token: str


@app.post("/api/plans/{plan_id}/run")
def run_plan(
    plan_id: str,
    request: RunRequest,
    identity: Annotated[SessionIdentity, Depends(scoped_identity)],
) -> dict[str, str]:
    try:
        _require_plan_owner(plan_id, identity.user.user_id)
        service = AgentService()
        contract = service.status(plan_id)
        if contract["approval_status"] != "approved":
            raise ValueError("分析计划尚未审批")
        auth = AuthStore()
        max_jobs = int(os.getenv("AMPLICON_MAX_ACTIVE_JOBS", "1"))
        if auth.active_job_count(identity.user.user_id) >= max_jobs:
            raise ValueError(f"每位用户最多同时运行 {max_jobs} 个任务")
        task_id = str(uuid.uuid4())
        auth.create_job(
            task_id=task_id,
            plan_id=plan_id,
            user_id=identity.user.user_id,
        )
        try:
            enqueue_analysis(
                user_id=identity.user.user_id,
                plan_id=plan_id,
                approval_token=request.approval_token,
                task_id=task_id,
            )
        except Exception as exc:
            auth.update_job(task_id, status="failed", error=str(exc))
            raise RuntimeError("任务队列暂时不可用，请稍后重试") from exc
        return {"plan_id": plan_id, "task_id": task_id, "status": "queued"}
    except Exception as exc:
        raise api_error(exc)


@app.get("/api/plans/{plan_id}")
def plan_status(
    plan_id: str,
    identity: Annotated[SessionIdentity, Depends(scoped_identity)],
) -> dict[str, Any]:
    try:
        _require_plan_owner(plan_id, identity.user.user_id)
        contract = AgentService().status(plan_id)
        contract["job"] = AuthStore().job_status(
            plan_id=plan_id,
            user_id=identity.user.user_id,
        )
        return contract
    except Exception as exc:
        raise api_error(exc)


@app.get("/api/plans/{plan_id}/validation")
def plan_validation(
    plan_id: str,
    identity: Annotated[SessionIdentity, Depends(scoped_identity)],
) -> dict[str, Any]:
    try:
        _require_plan_owner(plan_id, identity.user.user_id)
        return AgentService().validate(plan_id)
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


@app.post("/api/plans/{plan_id}/interpret")
def interpret(
    plan_id: str,
    settings: ModelCallSettings | None,
    identity: Annotated[SessionIdentity, Depends(scoped_identity)],
) -> dict[str, Any]:
    try:
        _require_plan_owner(plan_id, identity.user.user_id)
        service = AgentService()
        context = service.report_context(plan_id)
        schema_hint = {
            "project_summary": "string",
            "key_findings": [
                {
                    "title": "string",
                    "evidence": "string",
                    "interpretation": "string",
                }
            ],
            "section_interpretations": {"section_name": "string"},
            "supported_conclusions": ["string"],
            "unsupported_conclusions": ["string"],
            "limitations": ["string"],
            "next_steps": ["string"],
        }
        result = _model_call(
            user=identity.user,
            settings=settings,
            messages=[
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
                        "请按给定结构生成项目化解读。\n"
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


@app.get("/api/plans/{plan_id}/report")
def report(
    plan_id: str,
    identity: Annotated[SessionIdentity, Depends(scoped_identity)],
):
    try:
        _require_plan_owner(plan_id, identity.user.user_id)
        path = secure_path(AgentService().report(plan_id)["report_path"])
        return FileResponse(
            path,
            media_type="text/html; charset=utf-8",
            headers={
                "Content-Disposition": f'inline; filename="amplicon-{plan_id}.html"',
                "X-Robots-Tag": "noindex, nofollow",
            },
        )
    except Exception as exc:
        raise api_error(exc)


app.mount("/assets", StaticFiles(directory=STATIC), name="assets")


def main() -> None:
    import uvicorn

    uvicorn.run(
        "amplicon_agent.web:app",
        host=os.getenv("WEB_HOST", "0.0.0.0"),
        port=int(os.getenv("PORT", os.getenv("WEB_PORT", "8000"))),
        reload=_truthy("WEB_RELOAD"),
    )


if __name__ == "__main__":
    main()

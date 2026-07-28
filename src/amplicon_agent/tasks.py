from __future__ import annotations

import os
import shutil
from pathlib import Path

from celery import Celery

from .auth import AuthStore
from .resource_limits import analysis_timeout_seconds
from .security import user_workspace, workspace_scope
from .service import AgentService
from .store import PlanStore


def _truthy(name: str, default: str = "") -> bool:
    return os.getenv(name, default).strip().lower() in {"1", "true", "yes", "on"}


eager_mode = _truthy("CELERY_TASK_ALWAYS_EAGER")
broker_url = (
    "memory://"
    if eager_mode
    else os.getenv("CELERY_BROKER_URL", "redis://redis:6379/0")
)
result_backend = (
    "cache+memory://"
    if eager_mode
    else os.getenv("CELERY_RESULT_BACKEND", "redis://redis:6379/1")
)
celery_app = Celery(
    "amplicon_agent",
    broker=broker_url,
    backend=result_backend,
)
hard_limit = analysis_timeout_seconds()
celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="Asia/Shanghai",
    enable_utc=True,
    task_track_started=True,
    task_acks_late=True,
    task_reject_on_worker_lost=True,
    worker_prefetch_multiplier=1,
    task_soft_time_limit=max(60, hard_limit - 60),
    task_time_limit=hard_limit,
    task_always_eager=eager_mode,
    task_store_eager_result=False,
    beat_schedule={
        "cleanup-expired-analysis-data": {
            "task": "amplicon.cleanup_expired_data",
            "schedule": 3600.0,
        },
    },
)


def enqueue_analysis(
    *,
    user_id: str,
    plan_id: str,
    approval_token: str,
    task_id: str,
) -> None:
    run_analysis_task.apply_async(
        args=[user_id, plan_id, approval_token],
        task_id=task_id,
    )


def _delete_plan_data(user_id: str, plan_id: str) -> None:
    root = user_workspace(user_id)
    with workspace_scope(root):
        run_dir = root / "runs" / plan_id
        if run_dir.exists():
            shutil.rmtree(run_dir, ignore_errors=True)
        plan_path = PlanStore().path(plan_id)
        plan_path.unlink(missing_ok=True)


@celery_app.task(bind=True, name="amplicon.run_analysis")
def run_analysis_task(
    self,
    user_id: str,
    plan_id: str,
    approval_token: str,
) -> dict[str, str | None]:
    task_id = self.request.id
    auth = AuthStore()
    if auth.is_job_cancelled(task_id):
        auth.update_job(task_id, status="cancelled")
        return {"plan_id": plan_id, "status": "cancelled", "error": None}
    auth.update_job(task_id, status="running")
    try:
        with workspace_scope(user_workspace(user_id)):
            result = AgentService().run(plan_id, approval_token)
        if auth.is_job_cancelled(task_id):
            _delete_plan_data(user_id, plan_id)
            auth.forget_resource(kind="plan", resource_id=plan_id)
            auth.update_job(task_id, status="cancelled")
            return {"plan_id": plan_id, "status": "cancelled", "error": None}
        auth.update_job(
            task_id,
            status="succeeded" if result.status == "succeeded" else "failed",
            error=result.error,
        )
        return {
            "plan_id": plan_id,
            "status": result.status,
            "error": result.error,
        }
    except Exception as exc:
        auth.update_job(task_id, status="failed", error=str(exc))
        raise


@celery_app.task(name="amplicon.cleanup_expired_data")
def cleanup_expired_data() -> dict[str, int]:
    auth = AuthStore()
    deleted = 0
    for resource in auth.list_expired_resources():
        user_id = resource["user_id"]
        resource_id = resource["resource_id"]
        kind = resource["kind"]
        root = user_workspace(user_id)
        if kind == "upload":
            target = root / "uploads" / resource_id
            if target.exists():
                shutil.rmtree(target, ignore_errors=True)
        elif kind == "plan":
            _delete_plan_data(user_id, resource_id)
        auth.forget_resource(kind=kind, resource_id=resource_id)
        deleted += 1
    expired_sessions = auth.cleanup_sessions()
    return {"resources_deleted": deleted, "sessions_deleted": expired_sessions}

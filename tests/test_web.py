from __future__ import annotations

import json
from pathlib import Path

import pytest

pytest.importorskip("fastapi")
from fastapi.testclient import TestClient

from amplicon_agent.auth import AuthStore
from amplicon_agent.web import app


ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("AMPLICON_WORKSPACE", str(tmp_path))
    monkeypatch.setenv("CELERY_TASK_ALWAYS_EAGER", "true")
    monkeypatch.setenv("AMPLICON_RETENTION_DAYS", "7")
    monkeypatch.setenv("AMPLICON_MONTHLY_MODEL_QUOTA", "2")
    monkeypatch.delenv("MODEL_API_KEY", raising=False)
    with TestClient(app) as value:
        yield value


def register_user(
    client: TestClient,
    *,
    email: str = "researcher@example.org",
) -> dict:
    invite = AuthStore().create_invite(label="test", max_uses=1, valid_days=1)
    response = client.post(
        "/api/auth/register",
        json={
            "email": email,
            "display_name": "测试研究者",
            "password": "secure-pass-2026",
            "invite_code": invite,
            "privacy_accepted": True,
        },
    )
    assert response.status_code == 200, response.text
    user = response.json()["user"]
    client.headers["X-CSRF-Token"] = user["csrf_token"]
    return user


def upload_demo(client: TestClient) -> dict:
    example = ROOT / "examples" / "demo"
    with (
        (example / "abundance.csv").open("rb") as abundance,
        (example / "taxonomy.csv").open("rb") as taxonomy,
        (example / "metadata.csv").open("rb") as metadata,
    ):
        response = client.post(
            "/api/uploads/inspect",
            data={"group_column": "Group"},
            files={
                "abundance": ("abundance.csv", abundance, "text/csv"),
                "taxonomy": ("taxonomy.csv", taxonomy, "text/csv"),
                "metadata": ("metadata.csv", metadata, "text/csv"),
            },
        )
    assert response.status_code == 200, response.text
    return response.json()


def prepare_demo_plan(client: TestClient, upload_id: str) -> dict:
    response = client.post(
        "/api/plans",
        json={
            "upload_id": upload_id,
            "group_column": "Group",
            "research_question": "处理是否改变群落结构？",
            "sample_type": "根际土",
            "controls": ["Control"],
            "treatments": ["Treatment"],
            "analysis_scope": "targeted",
            "functions": [],
            "permutations": 99,
            "top_n": 10,
        },
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_public_landing_auth_gate_and_registry(client: TestClient) -> None:
    index = client.get("/")
    assert index.status_code == 200
    assert "BioAgent" in index.text
    assert "邀请制" in index.text
    assert client.get("/privacy").status_code == 200
    assert client.get("/assets/style.css").status_code == 200
    assert client.get("/assets/manifest.webmanifest").status_code == 200
    assert client.get("/sw.js").status_code == 200
    assert client.get("/app", follow_redirects=False).status_code == 303
    assert client.get("/api/functions").status_code == 401

    register_user(client)
    assert client.get("/app").status_code == 200
    health = client.get("/api/health").json()
    assert health["status"] == "ok"
    assert health["version"] == "0.6.0"
    functions = client.get("/api/functions").json()
    assert functions["baseline"] == ["qc", "alpha", "beta", "composition"]
    assert len(functions["functions"]) == 72
    assert all(item["display_name"] != item["function_id"] for item in functions["functions"])
    assert all(item["description"] for item in functions["functions"])


def test_invite_is_single_use_and_csrf_is_required(client: TestClient) -> None:
    invite = AuthStore().create_invite(label="single", max_uses=1, valid_days=1)
    payload = {
        "email": "first@example.org",
        "display_name": "First",
        "password": "secure-pass-2026",
        "invite_code": invite,
        "privacy_accepted": True,
    }
    first = client.post("/api/auth/register", json=payload)
    assert first.status_code == 200
    second = client.post(
        "/api/auth/register",
        json={**payload, "email": "second@example.org"},
    )
    assert second.status_code == 400

    client.headers.pop("X-CSRF-Token", None)
    blocked = client.post("/api/auth/logout", json={})
    assert blocked.status_code == 403


def test_inspect_prepare_and_user_isolation(client: TestClient) -> None:
    first = register_user(client, email="one@example.org")
    upload = upload_demo(client)
    assert upload["inspection"]["sample_count"] == 6
    assert upload["inspection"]["groups"] == {"Control": 3, "Treatment": 3}
    plan = prepare_demo_plan(client, upload["upload_id"])
    assert plan["functions"] == ["qc", "alpha", "beta", "composition"]
    assert plan["approval_status"] == "pending"
    assert not plan["blockers"]

    client.post("/api/auth/logout", json={})
    client.cookies.clear()
    second = register_user(client, email="two@example.org")
    assert second["user_id"] != first["user_id"]
    assert client.get(f"/api/plans/{plan['plan_id']}").status_code == 404


def test_group_column_is_required_and_can_be_reinspected(client: TestClient) -> None:
    register_user(client)
    example = ROOT / "examples" / "demo"
    with (
        (example / "abundance.csv").open("rb") as abundance,
        (example / "taxonomy.csv").open("rb") as taxonomy,
        (example / "metadata.csv").open("rb") as metadata,
    ):
        missing = client.post(
            "/api/uploads/inspect",
            files={
                "abundance": ("abundance.csv", abundance, "text/csv"),
                "taxonomy": ("taxonomy.csv", taxonomy, "text/csv"),
                "metadata": ("metadata.csv", metadata, "text/csv"),
            },
        )
    assert missing.status_code == 422
    assert "提交内容不完整" in missing.json()["detail"]

    upload = upload_demo(client)
    response = client.post(
        f"/api/uploads/{upload['upload_id']}/reinspect",
        json={"group_column": "Site"},
    )
    assert response.status_code == 200, response.text
    assert response.json()["inspection"]["groups"] == {"A": 3, "B": 3}


def test_ai_metadata_preview_requires_confirmation_and_preserves_original(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    register_user(client)
    upload = upload_demo(client)
    proposal = {
        "summary": "将英文分组值规范为中文，并保留 Sample ID。",
        "recommended_group_column": "Group",
        "recommended_batch_column": None,
        "recommended_gradient_column": None,
        "column_renames": [
            {"source": "Group", "target": "分组", "reason": "便于中文用户理解"}
        ],
        "value_mappings": [
            {
                "column": "Group",
                "mapping": {"Control": "对照", "Treatment": "处理"},
                "reason": "统一分组名称",
            }
        ],
        "sample_group_assignments": [],
        "controls": ["对照"],
        "treatments": ["处理"],
        "research_question": "处理是否改变根际微生物群落？",
        "sample_type": "根际土",
        "gradient_direction": "",
        "design_notes": "使用对照组作为参照。",
        "questions": [],
        "warnings": [],
    }
    monkeypatch.setattr(
        "amplicon_agent.web._model_call",
        lambda **kwargs: json.dumps(
            {"reply": "已生成安全修正预览，请核对后决定是否应用。", "metadata_proposal": proposal},
            ensure_ascii=False,
        ),
    )
    chat = client.post(
        "/api/assistant/chat",
        json={
            "message": "请帮我规范分组名称",
            "upload_id": upload["upload_id"],
            "group_column": "Group",
        },
    )
    assert chat.status_code == 200, chat.text
    draft = chat.json()["metadata_draft"]
    assert draft["proposal"]["recommended_group_column"] == "分组"
    assert draft["preview_rows"][0]["SampleID"] == "S1"

    rejected = client.post(
        f"/api/uploads/{upload['upload_id']}/metadata/apply",
        json={"draft_id": draft["draft_id"], "accepted": False},
    )
    assert rejected.status_code == 400
    applied = client.post(
        f"/api/uploads/{upload['upload_id']}/metadata/apply",
        json={"draft_id": draft["draft_id"], "accepted": True},
    )
    assert applied.status_code == 200, applied.text
    result = applied.json()
    assert result["group_column"] == "分组"
    assert result["inspection"]["groups"] == {"对照": 3, "处理": 3}
    download = client.get(result["download_url"])
    assert download.status_code == 200
    assert "SampleID" in download.text


def test_byok_secret_is_request_only_and_does_not_use_shared_quota(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    register_user(client)
    monkeypatch.setattr(
        "amplicon_agent.web.chat_completion",
        lambda *args, **kwargs: "OK",
    )
    response = client.post(
        "/api/model/test",
        json={
            "provider": "custom",
            "protocol": "openai",
            "base_url": "https://models.example.org/v1",
            "model": "private-model",
            "api_key": "do-not-store-or-return",
        },
    )
    assert response.status_code == 200, response.text
    assert "do-not-store-or-return" not in response.text
    me = client.get("/api/auth/me").json()
    assert me["monthly_model_used"] == 0
    assert me["monthly_model_remaining"] == 2


def test_delete_all_user_data_keeps_account(client: TestClient) -> None:
    user = register_user(client)
    upload = upload_demo(client)
    plan = prepare_demo_plan(client, upload["upload_id"])

    response = client.request(
        "DELETE",
        "/api/me/data",
        json={"confirmation": "DELETE MY DATA"},
    )
    assert response.status_code == 200, response.text
    assert client.get("/api/auth/me").json()["email"] == user["email"]
    assert client.get(f"/api/plans/{plan['plan_id']}").status_code == 404

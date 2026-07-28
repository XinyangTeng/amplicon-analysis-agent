from __future__ import annotations

from pathlib import Path

import pytest

pytest.importorskip("fastapi")
from fastapi.testclient import TestClient

from amplicon_agent.web import app


ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> TestClient:
    monkeypatch.setenv("AMPLICON_WORKSPACE", str(tmp_path))
    monkeypatch.delenv("AMPLICON_WEB_TOKEN", raising=False)
    monkeypatch.delenv("MODEL_API_KEY", raising=False)
    return TestClient(app)


def test_web_shell_health_and_registry(client: TestClient) -> None:
    index = client.get("/")
    assert index.status_code == 200
    assert "扩增子分析 Agent" in index.text
    assert client.get("/manifest.webmanifest").status_code == 200

    health = client.get("/api/health").json()
    assert health["status"] == "ok"
    assert health["version"] == "0.3.0"
    assert "api_key" not in health["model"]

    functions = client.get("/api/functions").json()
    assert functions["baseline"] == ["qc", "alpha", "beta", "composition"]
    assert len(functions["functions"]) == 55


def test_optional_bearer_token_is_enforced(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("AMPLICON_WEB_TOKEN", "test-secret")
    assert client.get("/api/functions").status_code == 401
    response = client.get(
        "/api/functions", headers={"Authorization": "Bearer test-secret"}
    )
    assert response.status_code == 200


def test_inspect_then_prepare_plan(client: TestClient) -> None:
    example = ROOT / "examples" / "demo"
    with (
        (example / "abundance.csv").open("rb") as abundance,
        (example / "taxonomy.csv").open("rb") as taxonomy,
        (example / "metadata.csv").open("rb") as metadata,
    ):
        inspection_response = client.post(
            "/api/uploads/inspect",
            data={"group_column": "Group"},
            files={
                "abundance": ("abundance.csv", abundance, "text/csv"),
                "taxonomy": ("taxonomy.csv", taxonomy, "text/csv"),
                "metadata": ("metadata.csv", metadata, "text/csv"),
            },
        )
    assert inspection_response.status_code == 200, inspection_response.text
    upload = inspection_response.json()
    assert upload["inspection"]["status"] in {"ready", "warning"}
    assert upload["inspection"]["sample_count"] == 6
    assert upload["inspection"]["groups"] == {"Control": 3, "Treatment": 3}

    plan_response = client.post(
        "/api/plans",
        json={
            "upload_id": upload["upload_id"],
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
    assert plan_response.status_code == 200, plan_response.text
    plan = plan_response.json()
    assert plan["functions"] == ["qc", "alpha", "beta", "composition"]
    assert plan["approval_status"] == "pending"
    assert not plan["blockers"]

    wrong = client.post(
        f"/api/plans/{plan['plan_id']}/approve",
        json={"confirmation": "CONFIRM wrong"},
    )
    assert wrong.status_code == 400


def test_model_settings_never_return_secret(client: TestClient) -> None:
    response = client.put(
        "/api/model",
        json={
            "provider": "custom",
            "protocol": "openai",
            "base_url": "http://localhost:11434/v1",
            "model": "local-test",
            "api_key": "do-not-return",
            "persist_api_key": False,
        },
    )
    assert response.status_code == 200, response.text
    value = response.json()
    assert value["api_key_configured"] is True
    assert value["api_key_source"] == "runtime"
    assert "api_key" not in value
    assert "do-not-return" not in response.text

    fetched = client.get("/api/model")
    assert "do-not-return" not in fetched.text

    cleared = client.put(
        "/api/model",
        json={
            "provider": "custom",
            "protocol": "openai",
            "base_url": "http://localhost:11434/v1",
            "model": "local-test",
            "clear_api_key": True,
        },
    )
    assert cleared.json()["api_key_configured"] is False

from __future__ import annotations

from pathlib import Path

import pytest

from amplicon_agent.auth import AuthStore, iso_time, utc_now
from amplicon_agent.security import secure_path, user_workspace, workspace_scope
from amplicon_agent.tasks import cleanup_expired_data


def create_user(store: AuthStore, email: str):
    invite = store.create_invite(max_uses=1, valid_days=1)
    return store.register(
        email=email,
        password="secure-pass-2026",
        display_name=email.split("@")[0],
        invite_code=invite,
        privacy_accepted=True,
    )


def test_user_workspaces_and_plan_paths_are_isolated(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("AMPLICON_WORKSPACE", str(tmp_path))
    store = AuthStore()
    first = create_user(store, "one@example.org")
    second = create_user(store, "two@example.org")

    with workspace_scope(user_workspace(first.user_id)):
        first_path = secure_path("uploads/example", must_exist=False)
    with workspace_scope(user_workspace(second.user_id)):
        second_path = secure_path("uploads/example", must_exist=False)

    assert first_path != second_path
    assert first.user_id in str(first_path)
    assert second.user_id in str(second_path)


def test_shared_model_quota_and_byok_accounting(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("AMPLICON_WORKSPACE", str(tmp_path))
    monkeypatch.setenv("AMPLICON_MONTHLY_MODEL_QUOTA", "1")
    store = AuthStore()
    user = create_user(store, "quota@example.org")

    usage = store.reserve_model_call(
        user=user,
        provider="qwen",
        use_server_key=True,
    )
    store.finish_model_call(usage, succeeded=True)
    with pytest.raises(ValueError, match="额度"):
        store.reserve_model_call(
            user=user,
            provider="qwen",
            use_server_key=True,
        )

    byok = store.reserve_model_call(
        user=user,
        provider="custom",
        use_server_key=False,
    )
    store.finish_model_call(byok, succeeded=True)
    assert store.user_summary(user)["monthly_model_remaining"] == 0


def test_failed_shared_model_call_is_not_charged(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("AMPLICON_WORKSPACE", str(tmp_path))
    monkeypatch.setenv("AMPLICON_MONTHLY_MODEL_QUOTA", "1")
    store = AuthStore()
    user = create_user(store, "refund@example.org")

    failed = store.reserve_model_call(
        user=user,
        provider="qwen",
        use_server_key=True,
    )
    store.finish_model_call(failed, succeeded=False)
    summary = store.user_summary(user)
    assert summary["monthly_model_used"] == 0
    assert summary["monthly_model_remaining"] == 1

    retry = store.reserve_model_call(
        user=user,
        provider="qwen",
        use_server_key=True,
    )
    store.finish_model_call(retry, succeeded=True)
    assert store.user_summary(user)["monthly_model_remaining"] == 0


def test_expired_upload_is_removed_by_cleanup_task(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("AMPLICON_WORKSPACE", str(tmp_path))
    store = AuthStore()
    user = create_user(store, "cleanup@example.org")
    upload_id = "58ef33b4-5415-4337-9a45-251d3c650006"
    upload_dir = user_workspace(user.user_id) / "uploads" / upload_id
    upload_dir.mkdir(parents=True)
    (upload_dir / "abundance.csv").write_text("FeatureID,S1\nF1,1\n", encoding="utf-8")
    store.register_resource(kind="upload", resource_id=upload_id, user=user)
    with store.connect() as connection:
        connection.execute(
            """
            UPDATE resources SET expires_at = ?
            WHERE kind = 'upload' AND resource_id = ?
            """,
            (iso_time(utc_now().replace(year=2020)), upload_id),
        )

    result = cleanup_expired_data.run()
    assert result["resources_deleted"] == 1
    assert not upload_dir.exists()
    assert not store.owns_resource(
        kind="upload",
        resource_id=upload_id,
        user_id=user.user_id,
    )

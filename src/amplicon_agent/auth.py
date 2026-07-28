from __future__ import annotations

import hashlib
import hmac
import os
import re
import secrets
import sqlite3
import threading
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterator

from .security import global_workspace_root, token_hash


EMAIL_PATTERN = re.compile(r"^[^@\s]{1,64}@[^@\s]{1,190}$")
_INIT_LOCK = threading.Lock()
_INITIALIZED_DATABASES: set[Path] = set()


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso_time(value: datetime | None = None) -> str:
    return (value or utc_now()).isoformat()


def parse_time(value: str) -> datetime:
    return datetime.fromisoformat(value)


def _password_hash(password: str, salt: bytes) -> str:
    digest = hashlib.scrypt(
        password.encode("utf-8"),
        salt=salt,
        n=2**14,
        r=8,
        p=1,
        dklen=32,
    )
    return digest.hex()


def _normalize_email(value: str) -> str:
    email = value.strip().lower()
    if not EMAIL_PATTERN.fullmatch(email):
        raise ValueError("请输入有效的邮箱地址")
    return email


def _validate_password(value: str) -> None:
    if len(value) < 10:
        raise ValueError("密码至少需要 10 个字符")
    if len(value) > 256:
        raise ValueError("密码过长")
    if not re.search(r"[A-Za-z]", value) or not re.search(r"\d", value):
        raise ValueError("密码需要同时包含字母和数字")


@dataclass(frozen=True)
class AuthUser:
    user_id: str
    email: str
    display_name: str
    status: str
    role: str
    retention_days: int
    monthly_model_quota: int


@dataclass(frozen=True)
class SessionIdentity:
    user: AuthUser
    csrf_token: str
    session_expires_at: str


class AuthStore:
    """Small SQLite-backed identity, quota, ownership and job store."""

    def __init__(self, database_path: Path | None = None) -> None:
        self.database_path = (
            database_path
            or global_workspace_root() / ".amplicon-agent" / "app.sqlite3"
        ).resolve()
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    @contextmanager
    def connect(self) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(
            self.database_path,
            timeout=30,
            isolation_level=None,
        )
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA busy_timeout = 30000")
        try:
            yield connection
        finally:
            connection.close()

    def _initialize(self) -> None:
        if self.database_path in _INITIALIZED_DATABASES:
            return
        with _INIT_LOCK:
            if self.database_path in _INITIALIZED_DATABASES:
                return
            with self.connect() as connection:
                connection.execute("PRAGMA journal_mode = WAL")
                connection.executescript(
                    """
                    CREATE TABLE IF NOT EXISTS users (
                        user_id TEXT PRIMARY KEY,
                        email TEXT NOT NULL UNIQUE,
                        display_name TEXT NOT NULL,
                        password_hash TEXT NOT NULL,
                        password_salt TEXT NOT NULL,
                        status TEXT NOT NULL DEFAULT 'active',
                        role TEXT NOT NULL DEFAULT 'member',
                        retention_days INTEGER NOT NULL,
                        monthly_model_quota INTEGER NOT NULL,
                        privacy_accepted_at TEXT NOT NULL,
                        created_at TEXT NOT NULL,
                        last_login_at TEXT,
                        failed_attempts INTEGER NOT NULL DEFAULT 0,
                        locked_until TEXT
                    );
                    CREATE TABLE IF NOT EXISTS invites (
                        invite_id TEXT PRIMARY KEY,
                        code_hash TEXT NOT NULL UNIQUE,
                        label TEXT NOT NULL,
                        max_uses INTEGER NOT NULL,
                        use_count INTEGER NOT NULL DEFAULT 0,
                        expires_at TEXT NOT NULL,
                        created_at TEXT NOT NULL,
                        revoked_at TEXT
                    );
                    CREATE TABLE IF NOT EXISTS sessions (
                        token_hash TEXT PRIMARY KEY,
                        user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
                        csrf_token TEXT NOT NULL,
                        created_at TEXT NOT NULL,
                        expires_at TEXT NOT NULL,
                        last_seen_at TEXT NOT NULL
                    );
                    CREATE INDEX IF NOT EXISTS sessions_user_idx ON sessions(user_id);
                    CREATE TABLE IF NOT EXISTS resources (
                        kind TEXT NOT NULL,
                        resource_id TEXT NOT NULL,
                        user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
                        created_at TEXT NOT NULL,
                        expires_at TEXT NOT NULL,
                        PRIMARY KEY(kind, resource_id)
                    );
                    CREATE INDEX IF NOT EXISTS resources_expiry_idx ON resources(expires_at);
                    CREATE INDEX IF NOT EXISTS resources_user_idx ON resources(user_id);
                    CREATE TABLE IF NOT EXISTS model_usage (
                        usage_id TEXT PRIMARY KEY,
                        user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
                        source TEXT NOT NULL,
                        status TEXT NOT NULL,
                        provider TEXT NOT NULL,
                        created_at TEXT NOT NULL,
                        finished_at TEXT
                    );
                    CREATE INDEX IF NOT EXISTS model_usage_user_time_idx
                        ON model_usage(user_id, created_at);
                    CREATE TABLE IF NOT EXISTS jobs (
                        task_id TEXT PRIMARY KEY,
                        plan_id TEXT NOT NULL,
                        user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
                        status TEXT NOT NULL,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        error TEXT
                    );
                    CREATE INDEX IF NOT EXISTS jobs_user_status_idx ON jobs(user_id, status);
                    """
                )
            _INITIALIZED_DATABASES.add(self.database_path)

    def create_invite(
        self,
        *,
        label: str = "internal-test",
        max_uses: int = 1,
        valid_days: int = 30,
        code: str | None = None,
    ) -> str:
        if not 1 <= max_uses <= 1000:
            raise ValueError("max_uses 必须在 1 到 1000 之间")
        if not 1 <= valid_days <= 365:
            raise ValueError("valid_days 必须在 1 到 365 之间")
        raw_code = code.strip() if code else f"BIO-{secrets.token_urlsafe(18)}"
        if len(raw_code) < 12:
            raise ValueError("邀请码至少需要 12 个字符")
        with self.connect() as connection:
            connection.execute(
                """
                INSERT INTO invites(
                    invite_id, code_hash, label, max_uses, expires_at, created_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    str(uuid.uuid4()),
                    token_hash(raw_code),
                    label.strip()[:100] or "internal-test",
                    max_uses,
                    iso_time(utc_now() + timedelta(days=valid_days)),
                    iso_time(),
                ),
            )
        return raw_code

    def ensure_bootstrap_invite(self, code: str) -> None:
        value = code.strip()
        if not value:
            return
        with self.connect() as connection:
            found = connection.execute(
                "SELECT 1 FROM invites WHERE code_hash = ?",
                (token_hash(value),),
            ).fetchone()
        if not found:
            self.create_invite(
                label="bootstrap",
                max_uses=int(os.getenv("AMPLICON_BOOTSTRAP_INVITE_USES", "10")),
                valid_days=int(os.getenv("AMPLICON_BOOTSTRAP_INVITE_DAYS", "30")),
                code=value,
            )

    def list_invites(self) -> list[dict[str, object]]:
        with self.connect() as connection:
            rows = connection.execute(
                """
                SELECT invite_id, label, max_uses, use_count, expires_at,
                       created_at, revoked_at
                FROM invites ORDER BY created_at DESC
                """
            ).fetchall()
        return [dict(row) for row in rows]

    def revoke_invite(self, invite_id: str) -> None:
        normalized = str(uuid.UUID(invite_id))
        with self.connect() as connection:
            cursor = connection.execute(
                """
                UPDATE invites SET revoked_at = ?
                WHERE invite_id = ? AND revoked_at IS NULL
                """,
                (iso_time(), normalized),
            )
        if cursor.rowcount != 1:
            raise ValueError("邀请码记录不存在或已经撤销")

    def register(
        self,
        *,
        email: str,
        password: str,
        display_name: str,
        invite_code: str,
        privacy_accepted: bool,
    ) -> AuthUser:
        clean_email = _normalize_email(email)
        _validate_password(password)
        clean_name = display_name.strip()[:80] or clean_email.split("@", 1)[0]
        if not privacy_accepted:
            raise ValueError("注册前需要阅读并同意隐私政策")
        now = utc_now()
        salt = secrets.token_bytes(16)
        user_id = str(uuid.uuid4())
        retention_days = int(os.getenv("AMPLICON_RETENTION_DAYS", "7"))
        quota = int(os.getenv("AMPLICON_MONTHLY_MODEL_QUOTA", "10"))
        with self.connect() as connection:
            try:
                connection.execute("BEGIN IMMEDIATE")
                invite = connection.execute(
                    """
                    SELECT invite_id, max_uses, use_count, expires_at, revoked_at
                    FROM invites WHERE code_hash = ?
                    """,
                    (token_hash(invite_code.strip()),),
                ).fetchone()
                if (
                    not invite
                    or invite["revoked_at"]
                    or invite["use_count"] >= invite["max_uses"]
                    or parse_time(invite["expires_at"]) <= now
                ):
                    raise ValueError("邀请码无效、已过期或使用次数已满")
                connection.execute(
                    """
                    INSERT INTO users(
                        user_id, email, display_name, password_hash, password_salt,
                        retention_days, monthly_model_quota, privacy_accepted_at,
                        created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        user_id,
                        clean_email,
                        clean_name,
                        _password_hash(password, salt),
                        salt.hex(),
                        retention_days,
                        quota,
                        iso_time(now),
                        iso_time(now),
                    ),
                )
                connection.execute(
                    "UPDATE invites SET use_count = use_count + 1 WHERE invite_id = ?",
                    (invite["invite_id"],),
                )
                connection.execute("COMMIT")
            except sqlite3.IntegrityError as exc:
                connection.execute("ROLLBACK")
                raise ValueError("该邮箱已经注册") from exc
            except Exception:
                connection.execute("ROLLBACK")
                raise
        return self.get_user(user_id)

    def authenticate_password(self, email: str, password: str) -> AuthUser:
        clean_email = _normalize_email(email)
        now = utc_now()
        with self.connect() as connection:
            row = connection.execute(
                "SELECT * FROM users WHERE email = ?",
                (clean_email,),
            ).fetchone()
            dummy_salt = bytes.fromhex("00" * 16)
            candidate = _password_hash(
                password,
                bytes.fromhex(row["password_salt"]) if row else dummy_salt,
            )
            valid = bool(
                row
                and row["status"] == "active"
                and hmac.compare_digest(candidate, row["password_hash"])
            )
            locked = bool(
                row
                and row["locked_until"]
                and parse_time(row["locked_until"]) > now
            )
            if locked:
                valid = False
            if not valid:
                if row and not locked:
                    attempts = int(row["failed_attempts"]) + 1
                    locked_until = (
                        iso_time(now + timedelta(minutes=15)) if attempts >= 5 else None
                    )
                    connection.execute(
                        """
                        UPDATE users
                        SET failed_attempts = ?, locked_until = ?
                        WHERE user_id = ?
                        """,
                        (0 if locked_until else attempts, locked_until, row["user_id"]),
                    )
                raise ValueError("邮箱或密码错误；连续失败 5 次将锁定 15 分钟")
            connection.execute(
                """
                UPDATE users
                SET failed_attempts = 0, locked_until = NULL, last_login_at = ?
                WHERE user_id = ?
                """,
                (iso_time(now), row["user_id"]),
            )
        return self.get_user(row["user_id"])

    def create_session(self, user_id: str) -> tuple[str, SessionIdentity]:
        token = secrets.token_urlsafe(32)
        csrf_token = secrets.token_urlsafe(24)
        now = utc_now()
        expires = now + timedelta(
            days=int(os.getenv("AMPLICON_SESSION_DAYS", "7"))
        )
        with self.connect() as connection:
            connection.execute(
                """
                INSERT INTO sessions(
                    token_hash, user_id, csrf_token, created_at, expires_at, last_seen_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    token_hash(token),
                    user_id,
                    csrf_token,
                    iso_time(now),
                    iso_time(expires),
                    iso_time(now),
                ),
            )
        return token, SessionIdentity(
            user=self.get_user(user_id),
            csrf_token=csrf_token,
            session_expires_at=iso_time(expires),
        )

    def authenticate_session(self, token: str) -> SessionIdentity | None:
        now = utc_now()
        with self.connect() as connection:
            row = connection.execute(
                """
                SELECT
                    s.csrf_token, s.expires_at,
                    u.user_id, u.email, u.display_name, u.status, u.role,
                    u.retention_days, u.monthly_model_quota
                FROM sessions s
                JOIN users u ON u.user_id = s.user_id
                WHERE s.token_hash = ?
                """,
                (token_hash(token),),
            ).fetchone()
            if (
                not row
                or row["status"] != "active"
                or parse_time(row["expires_at"]) <= now
            ):
                if row:
                    connection.execute(
                        "DELETE FROM sessions WHERE token_hash = ?",
                        (token_hash(token),),
                    )
                return None
            connection.execute(
                "UPDATE sessions SET last_seen_at = ? WHERE token_hash = ?",
                (iso_time(now), token_hash(token)),
            )
        return SessionIdentity(
            user=AuthUser(
                user_id=row["user_id"],
                email=row["email"],
                display_name=row["display_name"],
                status=row["status"],
                role=row["role"],
                retention_days=int(row["retention_days"]),
                monthly_model_quota=int(row["monthly_model_quota"]),
            ),
            csrf_token=row["csrf_token"],
            session_expires_at=row["expires_at"],
        )

    def delete_session(self, token: str) -> None:
        with self.connect() as connection:
            connection.execute(
                "DELETE FROM sessions WHERE token_hash = ?",
                (token_hash(token),),
            )

    def get_user(self, user_id: str) -> AuthUser:
        with self.connect() as connection:
            row = connection.execute(
                """
                SELECT user_id, email, display_name, status, role,
                       retention_days, monthly_model_quota
                FROM users WHERE user_id = ?
                """,
                (user_id,),
            ).fetchone()
        if not row:
            raise ValueError("用户不存在")
        return AuthUser(
            user_id=row["user_id"],
            email=row["email"],
            display_name=row["display_name"],
            status=row["status"],
            role=row["role"],
            retention_days=int(row["retention_days"]),
            monthly_model_quota=int(row["monthly_model_quota"]),
        )

    def user_summary(self, user: AuthUser, csrf_token: str | None = None) -> dict[str, object]:
        period_start = utc_now().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        with self.connect() as connection:
            used = connection.execute(
                """
                SELECT COUNT(*) AS value FROM model_usage
                WHERE user_id = ? AND source = 'server'
                  AND created_at >= ?
                """,
                (user.user_id, iso_time(period_start)),
            ).fetchone()["value"]
            active_jobs = connection.execute(
                """
                SELECT COUNT(*) AS value FROM jobs
                WHERE user_id = ? AND status IN ('queued', 'running')
                """,
                (user.user_id,),
            ).fetchone()["value"]
        result: dict[str, object] = {
            "user_id": user.user_id,
            "email": user.email,
            "display_name": user.display_name,
            "role": user.role,
            "retention_days": user.retention_days,
            "monthly_model_quota": user.monthly_model_quota,
            "monthly_model_used": int(used),
            "monthly_model_remaining": max(0, user.monthly_model_quota - int(used)),
            "active_jobs": int(active_jobs),
        }
        if csrf_token:
            result["csrf_token"] = csrf_token
        return result

    def register_resource(
        self,
        *,
        kind: str,
        resource_id: str,
        user: AuthUser,
    ) -> None:
        if kind not in {"upload", "plan"}:
            raise ValueError("不支持的资源类型")
        with self.connect() as connection:
            connection.execute(
                """
                INSERT OR REPLACE INTO resources(
                    kind, resource_id, user_id, created_at, expires_at
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (
                    kind,
                    resource_id,
                    user.user_id,
                    iso_time(),
                    iso_time(utc_now() + timedelta(days=user.retention_days)),
                ),
            )

    def owns_resource(self, *, kind: str, resource_id: str, user_id: str) -> bool:
        with self.connect() as connection:
            row = connection.execute(
                """
                SELECT 1 FROM resources
                WHERE kind = ? AND resource_id = ? AND user_id = ?
                """,
                (kind, resource_id, user_id),
            ).fetchone()
        return bool(row)

    def forget_resource(self, *, kind: str, resource_id: str) -> None:
        with self.connect() as connection:
            connection.execute(
                "DELETE FROM resources WHERE kind = ? AND resource_id = ?",
                (kind, resource_id),
            )

    def list_expired_resources(self, limit: int = 200) -> list[dict[str, str]]:
        with self.connect() as connection:
            rows = connection.execute(
                """
                SELECT kind, resource_id, user_id FROM resources
                WHERE expires_at <= ?
                ORDER BY expires_at
                LIMIT ?
                """,
                (iso_time(), limit),
            ).fetchall()
        return [dict(row) for row in rows]

    def reserve_model_call(
        self,
        *,
        user: AuthUser,
        provider: str,
        use_server_key: bool,
    ) -> str:
        source = "server" if use_server_key else "user"
        usage_id = str(uuid.uuid4())
        period_start = utc_now().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        with self.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            if use_server_key:
                used = connection.execute(
                    """
                    SELECT COUNT(*) AS value FROM model_usage
                    WHERE user_id = ? AND source = 'server' AND created_at >= ?
                    """,
                    (user.user_id, iso_time(period_start)),
                ).fetchone()["value"]
                if int(used) >= user.monthly_model_quota:
                    connection.execute("ROLLBACK")
                    raise ValueError(
                        "本月共享模型额度已用完；可以填写自己的 API Key 后继续解读"
                    )
            connection.execute(
                """
                INSERT INTO model_usage(
                    usage_id, user_id, source, status, provider, created_at
                ) VALUES (?, ?, ?, 'started', ?, ?)
                """,
                (usage_id, user.user_id, source, provider[:80], iso_time()),
            )
            connection.execute("COMMIT")
        return usage_id

    def finish_model_call(self, usage_id: str, *, succeeded: bool) -> None:
        with self.connect() as connection:
            connection.execute(
                """
                UPDATE model_usage SET status = ?, finished_at = ?
                WHERE usage_id = ?
                """,
                ("succeeded" if succeeded else "failed", iso_time(), usage_id),
            )

    def active_job_count(self, user_id: str) -> int:
        with self.connect() as connection:
            return int(
                connection.execute(
                    """
                    SELECT COUNT(*) AS value FROM jobs
                    WHERE user_id = ? AND status IN ('queued', 'running')
                    """,
                    (user_id,),
                ).fetchone()["value"]
            )

    def create_job(self, *, task_id: str, plan_id: str, user_id: str) -> None:
        with self.connect() as connection:
            connection.execute(
                """
                INSERT INTO jobs(
                    task_id, plan_id, user_id, status, created_at, updated_at
                ) VALUES (?, ?, ?, 'queued', ?, ?)
                """,
                (task_id, plan_id, user_id, iso_time(), iso_time()),
            )

    def update_job(
        self,
        task_id: str,
        *,
        status: str,
        error: str | None = None,
    ) -> None:
        with self.connect() as connection:
            connection.execute(
                """
                UPDATE jobs SET status = ?, updated_at = ?, error = ?
                WHERE task_id = ?
                """,
                (status, iso_time(), error[:1000] if error else None, task_id),
            )

    def job_status(self, *, plan_id: str, user_id: str) -> dict[str, str] | None:
        with self.connect() as connection:
            row = connection.execute(
                """
                SELECT task_id, plan_id, status, created_at, updated_at, error
                FROM jobs WHERE plan_id = ? AND user_id = ?
                ORDER BY created_at DESC LIMIT 1
                """,
                (plan_id, user_id),
            ).fetchone()
        return dict(row) if row else None

    def cancel_user_jobs(self, user_id: str) -> list[str]:
        with self.connect() as connection:
            rows = connection.execute(
                """
                SELECT task_id FROM jobs
                WHERE user_id = ? AND status IN ('queued', 'running')
                """,
                (user_id,),
            ).fetchall()
            connection.execute(
                """
                UPDATE jobs SET status = 'cancel_requested', updated_at = ?
                WHERE user_id = ? AND status IN ('queued', 'running')
                """,
                (iso_time(), user_id),
            )
        return [row["task_id"] for row in rows]

    def is_job_cancelled(self, task_id: str) -> bool:
        with self.connect() as connection:
            row = connection.execute(
                "SELECT status FROM jobs WHERE task_id = ?",
                (task_id,),
            ).fetchone()
        return bool(row and row["status"] in {"cancel_requested", "cancelled"})

    def purge_user_data_records(self, user_id: str) -> None:
        with self.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute("DELETE FROM resources WHERE user_id = ?", (user_id,))
            connection.execute("DELETE FROM model_usage WHERE user_id = ?", (user_id,))
            connection.execute(
                "DELETE FROM jobs WHERE user_id = ? AND status NOT IN ('running', 'cancel_requested')",
                (user_id,),
            )
            connection.execute("COMMIT")

    def delete_account(self, user_id: str) -> None:
        anonymized = f"deleted-{uuid.uuid4()}@invalid.local"
        with self.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute("DELETE FROM sessions WHERE user_id = ?", (user_id,))
            connection.execute("DELETE FROM resources WHERE user_id = ?", (user_id,))
            connection.execute("DELETE FROM model_usage WHERE user_id = ?", (user_id,))
            connection.execute("DELETE FROM jobs WHERE user_id = ?", (user_id,))
            connection.execute(
                """
                UPDATE users
                SET email = ?, display_name = '已删除用户', status = 'deleted',
                    password_hash = ?, password_salt = ?
                WHERE user_id = ?
                """,
                (anonymized, secrets.token_hex(32), secrets.token_hex(16), user_id),
            )
            connection.execute("COMMIT")

    def cleanup_sessions(self) -> int:
        with self.connect() as connection:
            cursor = connection.execute(
                "DELETE FROM sessions WHERE expires_at <= ?",
                (iso_time(),),
            )
        return int(cursor.rowcount)

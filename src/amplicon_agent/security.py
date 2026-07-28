from __future__ import annotations

import hashlib
import os
import uuid
from contextlib import contextmanager
from contextvars import ContextVar
from pathlib import Path
from typing import Iterator


class PathSecurityError(ValueError):
    pass


_workspace_override: ContextVar[Path | None] = ContextVar(
    "amplicon_workspace_override",
    default=None,
)


def global_workspace_root() -> Path:
    root = Path(os.environ.get("AMPLICON_WORKSPACE", Path.cwd())).resolve()
    root.mkdir(parents=True, exist_ok=True)
    return root


def workspace_root() -> Path:
    root = _workspace_override.get() or global_workspace_root()
    root.mkdir(parents=True, exist_ok=True)
    return root


def user_workspace(user_id: str) -> Path:
    normalized = str(uuid.UUID(user_id))
    root = global_workspace_root()
    path = (root / "users" / normalized).resolve()
    path.relative_to(root)
    return path


@contextmanager
def workspace_scope(path: Path) -> Iterator[Path]:
    resolved = path.resolve()
    global_root = global_workspace_root()
    try:
        resolved.relative_to(global_root)
    except ValueError as exc:
        raise PathSecurityError(
            f"User workspace is outside AMPLICON_WORKSPACE: {resolved}"
        ) from exc
    resolved.mkdir(parents=True, exist_ok=True)
    token = _workspace_override.set(resolved)
    try:
        yield resolved
    finally:
        _workspace_override.reset(token)


def secure_path(value: str | Path, *, must_exist: bool = True) -> Path:
    root = workspace_root()
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = root / candidate
    candidate = candidate.resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise PathSecurityError(f"Path is outside AMPLICON_WORKSPACE: {candidate}") from exc
    if must_exist and not candidate.exists():
        raise FileNotFoundError(candidate)
    return candidate


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()

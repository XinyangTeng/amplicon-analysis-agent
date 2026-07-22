from __future__ import annotations

import hashlib
import os
from pathlib import Path


class PathSecurityError(ValueError):
    pass


def workspace_root() -> Path:
    root = Path(os.environ.get("AMPLICON_WORKSPACE", Path.cwd())).resolve()
    root.mkdir(parents=True, exist_ok=True)
    return root


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


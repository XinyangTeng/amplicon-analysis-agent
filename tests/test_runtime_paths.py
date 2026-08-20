from __future__ import annotations

from pathlib import Path

import pytest

from amplicon_agent.runtime_paths import resolve_r_root


def test_explicit_r_root_is_used(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    r_root = tmp_path / "r"
    r_root.mkdir()
    (r_root / "run_analysis.R").write_text("# test\n", encoding="utf-8")
    monkeypatch.setenv("AMPLICON_R_ROOT", str(r_root))
    assert resolve_r_root() == r_root.resolve()


def test_invalid_explicit_r_root_fails_loudly(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("AMPLICON_R_ROOT", str(tmp_path / "missing"))
    with pytest.raises(RuntimeError, match="does not contain run_analysis.R"):
        resolve_r_root()

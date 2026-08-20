from __future__ import annotations

import os
from pathlib import Path


def resolve_r_root() -> Path:
    """Locate the bundled R runtime in source checkouts and built images."""
    configured = os.environ.get("AMPLICON_R_ROOT", "").strip()
    if configured:
        root = Path(configured).expanduser().resolve()
        if not (root / "run_analysis.R").is_file():
            raise RuntimeError(
                f"AMPLICON_R_ROOT does not contain run_analysis.R: {root}"
            )
        return root

    candidates = (
        Path(__file__).resolve().parents[2] / "r",
        Path.cwd().resolve() / "r",
        Path("/app/r"),
    )
    for root in candidates:
        if (root / "run_analysis.R").is_file():
            return root.resolve()
    searched = ", ".join(str(path) for path in candidates)
    raise RuntimeError(
        "Could not locate the R analysis runtime. Set AMPLICON_R_ROOT. "
        f"Searched: {searched}"
    )


R_ROOT = resolve_r_root()

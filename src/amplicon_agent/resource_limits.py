from __future__ import annotations

import os
from typing import Any


def analysis_timeout_seconds() -> int:
    return max(60, int(os.getenv("AMPLICON_ANALYSIS_TIMEOUT_SECONDS", "3600")))


def subprocess_timeout_seconds() -> int:
    return max(
        60,
        min(
            int(os.getenv("AMPLICON_R_TIMEOUT_SECONDS", "1800")),
            analysis_timeout_seconds(),
        ),
    )


def subprocess_limit_kwargs() -> dict[str, Any]:
    """Apply best-effort POSIX limits; Docker remains the production boundary."""
    if os.name == "nt":
        return {}

    import resource

    memory_mb = max(512, int(os.getenv("AMPLICON_WORKER_MEMORY_MB", "6144")))
    cpu_seconds = max(
        60,
        int(os.getenv("AMPLICON_PROCESS_CPU_SECONDS", str(analysis_timeout_seconds()))),
    )

    def apply_limits() -> None:
        memory_bytes = memory_mb * 1024 * 1024
        resource.setrlimit(resource.RLIMIT_AS, (memory_bytes, memory_bytes))
        resource.setrlimit(resource.RLIMIT_CPU, (cpu_seconds, cpu_seconds + 30))
        resource.setrlimit(resource.RLIMIT_NOFILE, (1024, 1024))

    return {"preexec_fn": apply_limits}


from __future__ import annotations

import os
import subprocess
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


def _process_group_kwargs() -> dict[str, Any]:
    """Start the child in its own process group/session so the whole tree can
    be killed on timeout instead of only the direct child."""
    if os.name == "nt":
        return {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP}
    return {"start_new_session": True}


def _kill_process_tree(process: "subprocess.Popen[str]") -> None:
    """Best-effort kill of the subprocess and any children it spawned."""
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/F", "/T", "/PID", str(process.pid)],
            capture_output=True,
            check=False,
        )
        return
    import signal

    try:
        pgid = os.getpgid(process.pid)
    except ProcessLookupError:
        return
    try:
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def run_subprocess(
    command: list[str],
    *,
    timeout: int,
    cwd: str | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess:
    """``subprocess.run`` with a timeout that kills the whole process tree.

    ``subprocess.run(..., timeout=...)`` only terminates the direct child. If R
    spawns further child processes (``system()`` calls, parallel workers), those
    become orphans that keep consuming CPU/memory after the timeout fires. This
    starts the child in its own process group/session and, on timeout, kills
    that whole group/tree before re-raising ``TimeoutExpired`` so callers see
    the same exception they did before.
    """
    process = subprocess.Popen(
        command,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        **_process_group_kwargs(),
        **subprocess_limit_kwargs(),
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        _kill_process_tree(process)
        stdout, stderr = process.communicate()
        raise subprocess.TimeoutExpired(command, timeout, output=stdout, stderr=stderr)
    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)

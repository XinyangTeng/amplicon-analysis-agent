#!/usr/bin/env bash
set -Eeuo pipefail

# Render does not provide a shared filesystem between a web service and a
# separate worker. Running the web process, one Celery worker, and Celery Beat
# in the same service keeps uploads and results on the same mounted disk.
celery -A amplicon_agent.tasks:celery_app worker \
  --loglevel=INFO --concurrency=1 --max-tasks-per-child=1 &
worker_pid=$!

celery -A amplicon_agent.tasks:celery_app beat --loglevel=INFO &
beat_pid=$!

amplicon-web &
web_pid=$!

shutdown() {
  kill -TERM "${web_pid}" "${worker_pid}" "${beat_pid}" 2>/dev/null || true
  wait "${web_pid}" "${worker_pid}" "${beat_pid}" 2>/dev/null || true
}
trap shutdown EXIT INT TERM

# If any required process exits, stop the service so Render can restart it.
wait -n "${web_pid}" "${worker_pid}" "${beat_pid}"

#!/usr/bin/env bash
set -euo pipefail

# Web entrypoint: collect static, then start gunicorn immediately.
# Migrations should be run separately (Render Shell/Job/Worker) to avoid long startup and lock pressure.

echo "Collecting static files..."
python manage.py collectstatic --noinput

echo "Starting gunicorn on PORT=${PORT:-10000}..."
exec gunicorn config.wsgi:application \
  --bind 0.0.0.0:${PORT:-10000} \
  --workers ${GUNICORN_WORKERS:-3} \
  --threads ${GUNICORN_THREADS:-2} \
  --timeout ${GUNICORN_TIMEOUT:-120}



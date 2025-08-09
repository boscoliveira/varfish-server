#!/usr/bin/env bash
set -euo pipefail

# Simple startup for Render
# 1) wait for Postgres/Redis via WAIT_HOSTS (handled by base image)
# 2) run migrations and collectstatic
# 3) start gunicorn

echo "Applying migrations..."
python manage.py migrate --noinput

echo "Collecting static files..."
python manage.py collectstatic --noinput

echo "Starting gunicorn..."
# Default Django wsgi app path for varfish-server image
exec gunicorn config.wsgi:application \
  --bind 0.0.0.0:8080 \
  --workers ${GUNICORN_WORKERS:-3} \
  --threads ${GUNICORN_THREADS:-2} \
  --timeout ${GUNICORN_TIMEOUT:-120}



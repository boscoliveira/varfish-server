#!/usr/bin/env bash
set -euo pipefail

# Simple startup for Render
# 1) wait for Postgres/Redis via WAIT_HOSTS (handled by base image)
# 2) run migrations and collectstatic
# 3) start gunicorn

echo "Applying migrations (with retries if DB not ready)..."
ATTEMPTS=${DB_WAIT_ATTEMPTS:-60}
SLEEP_SECS=${DB_WAIT_SLEEP_SECONDS:-5}

set +e
for i in $(seq 1 "$ATTEMPTS"); do
  python manage.py migrate --noinput
  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 0 ]; then
    echo "Migrations succeeded on attempt $i."
    break
  fi
  echo "Migrations failed (attempt $i/$ATTEMPTS). Likely DB not ready. Sleeping ${SLEEP_SECS}s..."
  sleep "$SLEEP_SECS"
done
set -e

if [ $EXIT_CODE -ne 0 ]; then
  echo "ERROR: Migrations failed after $ATTEMPTS attempts. Exiting."
  exit $EXIT_CODE
fi

echo "Collecting static files..."
python manage.py collectstatic --noinput

echo "Starting gunicorn..."
# Default Django wsgi app path for varfish-server image
exec gunicorn config.wsgi:application \
  --bind 0.0.0.0:8080 \
  --workers ${GUNICORN_WORKERS:-3} \
  --threads ${GUNICORN_THREADS:-2} \
  --timeout ${GUNICORN_TIMEOUT:-120}



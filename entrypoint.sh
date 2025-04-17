#!/bin/bash
set -e

#!/bin/bash
set -e

# Check required environment variables
for var in POSTGRES_USER POSTGRES_PASSWORD POSTGRES_HOST POSTGRES_PORT POSTGRES_DB; do
  if [ -z "${!var}" ]; then
    echo "[ERROR] $var environment variable not set."
    exit 1
  fi
done

# Wait for Postgres to be ready
MAX_ATTEMPTS=20
SLEEP=3
ATTEMPT=1
until psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -p "$POSTGRES_PORT" -d "$POSTGRES_DB" -c '\q' >/dev/null 2>&1; do
  if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
    echo "[ERROR] Postgres not available after $ATTEMPT attempts. Exiting."
    exit 1
  fi
  echo "[INFO] Waiting for Postgres... (attempt $ATTEMPT/$MAX_ATTEMPTS)"
  ATTEMPT=$((ATTEMPT+1))
  sleep $SLEEP
done

echo "[INFO] Running DB schema initialization..."
psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -p "$POSTGRES_PORT" -d "$POSTGRES_DB" -f lib/database/schema.pg.sql

# Start the OCaml app and nginx
exec ./main.exe &
exec nginx -g 'daemon off;'

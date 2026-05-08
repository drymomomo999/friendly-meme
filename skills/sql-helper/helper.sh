#!/usr/bin/env bash
set -euo pipefail

DB_NAME="dmdb"
PG_USER="codespace"

ensure_pg_running() {
  if ! pg_isready -q 2>/dev/null; then
    sudo service postgresql start
    sleep 2
  fi
}

ensure_pg_role() {
  # postgresql feature creates only the `postgres` superuser. The OS user
  # `codespace` has no Postgres role until we create one.
  sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$PG_USER'" \
    | grep -q 1 || sudo -u postgres psql -c "CREATE ROLE $PG_USER LOGIN SUPERUSER;"
}

cmd_init() {
  ensure_pg_running
  ensure_pg_role
  sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" \
    | grep -q 1 || sudo -u postgres createdb -O "$PG_USER" "$DB_NAME"
  if [ -d lab-data ]; then
    for f in lab-data/*.sql; do
      [ -f "$f" ] || continue
      echo "Loading $f..."
      psql -d "$DB_NAME" -f "$f"
    done
  fi
  echo "✓ DB ready. Connect: psql -d $DB_NAME"
}

cmd_schema()  { ensure_pg_running; ensure_pg_role; psql -d "$DB_NAME" -c "\d+"; }
cmd_query()   { ensure_pg_running; ensure_pg_role; psql -d "$DB_NAME" -c "$1"; }
cmd_explain() { ensure_pg_running; ensure_pg_role; psql -d "$DB_NAME" -c "EXPLAIN ANALYZE $1"; }

case "${1:-}" in
  init)    cmd_init ;;
  schema)  cmd_schema ;;
  query)   cmd_query "${2:?query required}" ;;
  explain) cmd_explain "${2:?query required}" ;;
  *)       echo "usage: helper.sh {init|schema|query|explain} [SQL]" >&2; exit 2 ;;
esac

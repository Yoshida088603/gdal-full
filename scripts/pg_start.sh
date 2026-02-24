#!/usr/bin/env bash
# gdal-full 内の PostgreSQL（pg-install / pg-data）を起動する。
# pg-data が無い場合は initdb してから起動する。
# 使い方: ./scripts/pg_start.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PG_INSTALL="$PROJECT_ROOT/pg-install"
PG_DATA="$PROJECT_ROOT/pg-data"

if [[ ! -f "$PG_INSTALL/bin/pg_ctl" ]]; then
  echo "Error: pg-install が見つかりません。先に ./build_postgresql.sh を実行してください。" >&2
  exit 1
fi

export PATH="$PG_INSTALL/bin:$PATH"

if [[ ! -d "$PG_DATA" ]] || [[ ! -f "$PG_DATA/PG_VERSION" ]]; then
  echo "pg-data がありません。initdb を実行します..."
  "$PG_INSTALL/bin/initdb" -D "$PG_DATA"
fi

if "$PG_INSTALL/bin/pg_ctl" -D "$PG_DATA" status 2>/dev/null | grep -q "running"; then
  echo "PostgreSQL は既に起動しています。"
  exit 0
fi

echo "PostgreSQL を起動しています..."
"$PG_INSTALL/bin/pg_ctl" -D "$PG_DATA" -l "$PG_DATA/logfile" start
echo "起動しました。接続例: psql -h localhost -p 5432 -U \$(whoami) -d postgres"

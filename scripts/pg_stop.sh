#!/usr/bin/env bash
# gdal-full 内の PostgreSQL（pg-data）を停止する。
# 使い方: ./scripts/pg_stop.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PG_INSTALL="$PROJECT_ROOT/pg-install"
PG_DATA="$PROJECT_ROOT/pg-data"

if [[ ! -f "$PG_INSTALL/bin/pg_ctl" ]]; then
  echo "Error: pg-install が見つかりません。" >&2
  exit 1
fi

export PATH="$PG_INSTALL/bin:$PATH"
"$PG_INSTALL/bin/pg_ctl" -D "$PG_DATA" stop
echo "PostgreSQL を停止しました。"

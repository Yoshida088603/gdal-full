#!/usr/bin/env bash
# PostgreSQL/PostGIS ダンプのリストア（プレーン SQL / カスタム形式対応）
# 使い方: ./scripts/restore_pg_dump.sh <ダンプファイルのパス> <DB名>
# 例: ./scripts/restore_pg_dump.sh input_data/gaiku_full20250220/gaiku_full20250220.dmp gaiku_export
# 前提: PostgreSQL が起動しており、createdb / psql / pg_restore が利用できること。

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# gdal-full 内に pg-install がある場合はその bin を優先（閉じ込め運用）
if [[ -d "$PROJECT_ROOT/pg-install/bin" ]]; then
  export PATH="$PROJECT_ROOT/pg-install/bin:$PATH"
fi

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <dump_file> <db_name>" >&2
  echo "  dump_file: path to .sql, .dmp, or .backup (plain SQL or custom format)" >&2
  echo "  db_name:  target database name (created if not exists)" >&2
  exit 1
fi

DUMP_FILE="$1"
DB_NAME="$2"

if [[ ! -f "$DUMP_FILE" ]]; then
  echo "Error: Dump file not found: $DUMP_FILE" >&2
  exit 1
fi

# DB が存在しなければ作成
if ! psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
  echo "Creating database: $DB_NAME"
  createdb "$DB_NAME"
fi

# PostGIS 拡張を有効化（既に存在する場合は無視される）
echo "Enabling PostGIS extension..."
psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS postgis;" 2>/dev/null || true

# ダンプの形式に応じてリストア（.backup は pg_dump -Fc のカスタム形式、.sql / .dmp 等はプレーン SQL）
case "$DUMP_FILE" in
  *.backup)
    echo "Restoring custom format dump: $DUMP_FILE"
    pg_restore -d "$DB_NAME" "$DUMP_FILE" 2>/dev/null || true
    ;;
  *)
    echo "Restoring plain SQL dump: $DUMP_FILE"
    psql -d "$DB_NAME" -f "$DUMP_FILE"
    ;;
esac

echo "Done. Connect with: psql -d $DB_NAME"
echo "Then run: PG_CONNECTION='PG:\"dbname=$DB_NAME host=localhost port=5432 user=postgres\"' ./scripts/run_pipeline_pg.sh"

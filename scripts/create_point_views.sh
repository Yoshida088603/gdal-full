#!/usr/bin/env bash
# gaiku ダンプリストア後に、x/y を属性に持つ点ジオメトリ VIEW（*_pt）を作成する。
# 使い方: ./scripts/create_point_views.sh <DB名>
# 例: ./scripts/create_point_views.sh gaiku_export
# 前提: PostgreSQL が起動しており、リストア済みの DB に kanri / tosikanmin の対象テーブルがあること。

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SQL_FILE="$PROJECT_ROOT/scripts/sql/create_point_views.sql"

# gdal-full 内に pg-install がある場合はその bin を優先（閉じ込め運用）
if [[ -d "$PROJECT_ROOT/pg-install/bin" ]]; then
  export PATH="$PROJECT_ROOT/pg-install/bin:$PATH"
fi

if [[ $# -lt 1 ]] && [[ -z "${PGDATABASE:-}" ]]; then
  echo "Usage: $0 <db_name>" >&2
  echo "  db_name: target database (e.g. gaiku_export). Or set PGDATABASE." >&2
  exit 1
fi

DB_NAME="${1:-$PGDATABASE}"
if [[ -z "$DB_NAME" ]]; then
  echo "Error: DB name required. Pass as first argument or set PGDATABASE." >&2
  exit 1
fi

if [[ ! -f "$SQL_FILE" ]]; then
  echo "Error: SQL file not found: $SQL_FILE" >&2
  exit 1
fi

echo "Creating point views in database: $DB_NAME"
psql -d "$DB_NAME" -f "$SQL_FILE"
echo "Done. Run pipeline with PG_CONNECTION including schemas=kanri,tosikanmin to export *_pt layers."

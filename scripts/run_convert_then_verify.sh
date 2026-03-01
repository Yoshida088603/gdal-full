#!/usr/bin/env bash
# 全 CSV を GeoParquet に変換してから、件数検証を行う。
# 前提: build_gdal_full.sh 実行済み。実行前に source env.sh は不要（このスクリプト内で source する）。
# 使い方: ./scripts/run_convert_then_verify.sh
#         ./scripts/run_convert_then_verify.sh -s   # 既存 parquet はスキップして変換、その後検証

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

if [[ ! -f "$PROJECT_ROOT/env.sh" ]]; then
  echo "Error: env.sh not found at $PROJECT_ROOT/env.sh" >&2
  exit 1
fi
echo "run_convert_then_verify: PROJECT_ROOT=$PROJECT_ROOT" >&2
source "$PROJECT_ROOT/env.sh" || { echo "Error: source env.sh failed (GDAL not built?)" >&2; exit 1; }

echo "===== 1. 変換（CSV → GeoParquet） ====="
if [[ "$1" == "-s" ]]; then
  "$SCRIPT_DIR/csv_to_geoparquet.sh" -s
else
  "$SCRIPT_DIR/csv_to_geoparquet.sh"
fi

echo ""
echo "===== 2. 検証（CSV 件数 vs Parquet Feature Count） ====="
python3 "$SCRIPT_DIR/verify_csv_geoparquet.py"
exit $?

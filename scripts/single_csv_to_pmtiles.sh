#!/usr/bin/env bash
# 国土数値情報 CSV の **1個** を GPKG → PMTiles まで変換する（土地活用・街区基準点等の両方に対応）。
# 使い方（gdal-full をカレントに）:
#   source env.sh
#   bash scripts/single_csv_to_pmtiles.sh "inputfile/.../データ_origin/土地活用推進調査/TH_23521.csv"
#   bash scripts/single_csv_to_pmtiles.sh "inputfile/.../データ_origin/街区基準点等データ/H_01101.csv"
# 出力: データ_geopackage_marged/<ベース名>.gpkg と .pmtiles

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_PARENT="$PROJECT_ROOT/inputfile/20260219昨年納品DVD/05ホームページ公開用データ及びプログラム"
OUT_DIR="$DATA_PARENT/データ_geopackage_marged"
TOCHI_PY="$SCRIPT_DIR/csv_to_geoparquet_tochi.py"

CSV="${1:?Usage: bash single_csv_to_pmtiles.sh <path/to/xxx.csv>}"
if [[ ! -f "$CSV" ]]; then
  echo "Error: CSV not found: $CSV" >&2
  exit 1
fi

BASE=$(basename "$CSV" .csv)
TMP_CSV="${TMPDIR:-/tmp}/csv_single_${BASE}.csv"
GPKG="$OUT_DIR/${BASE}.gpkg"

cd "$PROJECT_ROOT"
mkdir -p "$OUT_DIR"

echo "[1/4] Preprocess CSV: $CSV -> $TMP_CSV"
ZONE=$(python3 "$TOCHI_PY" "$CSV" "$TMP_CSV" --print-zukei 2>/dev/null | tail -1)
if ! [[ "$ZONE" =~ ^[0-9]+$ ]] || (( ZONE < 1 || ZONE > 19 )); then
  echo "Error: 座標系(系番号 1-19) could not be read: '$ZONE'" >&2
  exit 1
fi
EPSG=$((6668 + ZONE))
echo "[2/4] Zone=$ZONE -> EPSG:$EPSG, GPKG: $GPKG"

# 街区基準点等はヘッダに X座標/Y座標、土地活用は x/y
if head -1 "$TMP_CSV" | grep -q "X座標"; then
  X_Y_OO="-oo X_POSSIBLE_NAMES=X座標 -oo Y_POSSIBLE_NAMES=Y座標"
else
  X_Y_OO="-oo X_POSSIBLE_NAMES=x -oo Y_POSSIBLE_NAMES=y"
fi

ogr2ogr -skipfailures -f GPKG -nln merged \
  -s_srs "EPSG:$EPSG" -t_srs EPSG:3857 \
  $X_Y_OO \
  "$GPKG" "$TMP_CSV"
rm -f "$TMP_CSV"

echo "[3/4] PMTiles: $GPKG -> $OUT_DIR/${BASE}.pmtiles"
bash "$SCRIPT_DIR/gpkg_to_pmtiles.sh" "$GPKG"

echo "[4/4] Done. PMTiles: $OUT_DIR/${BASE}.pmtiles"

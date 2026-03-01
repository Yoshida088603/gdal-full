#!/usr/bin/env bash
# 土地活用推進調査の **1個の CSV** だけを GPKG → PMTiles まで変換する（動作確認・位置確認用）。
# 使い方（gdal-full をカレントに）:
#   source env.sh
#   bash scripts/single_csv_to_pmtiles.sh "inputfile/.../データ_origin/土地活用推進調査/TH_23521.csv"
# 出力: データ_geopackage_marged/TH_23521.gpkg と TH_23521.pmtiles

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
TMP_CSV="${TMPDIR:-/tmp}/tochi_single_${BASE}.csv"
GPKG="$OUT_DIR/${BASE}.gpkg"

cd "$PROJECT_ROOT"
mkdir -p "$OUT_DIR"

echo "[1/4] Preprocess CSV: $CSV -> $TMP_CSV"
python3 "$TOCHI_PY" "$CSV" "$TMP_CSV"

# 先頭データ行の col5（0-based で5列目＝6列目）から系番号 1～19 を取得
ZONE=$(awk -F',' 'NR==2 {print $6}' "$TMP_CSV")
if ! [[ "$ZONE" =~ ^[0-9]+$ ]] || (( ZONE < 1 || ZONE > 19 )); then
  echo "Error: col5 (座標系) could not be read or is not 1-19: '$ZONE'" >&2
  exit 1
fi
EPSG=$((6668 + ZONE))
echo "[2/4] Zone=$ZONE -> EPSG:$EPSG, GPKG: $GPKG"

ogr2ogr -skipfailures -f GPKG -nln tochi_merged \
  -s_srs "EPSG:$EPSG" -t_srs EPSG:3857 \
  -oo X_POSSIBLE_NAMES=x -oo Y_POSSIBLE_NAMES=y \
  "$GPKG" "$TMP_CSV"
rm -f "$TMP_CSV"

echo "[3/4] PMTiles: $GPKG -> $OUT_DIR/${BASE}.pmtiles"
bash "$SCRIPT_DIR/gpkg_to_pmtiles.sh" "$GPKG"

echo "[4/4] Done. PMTiles: $OUT_DIR/${BASE}.pmtiles"
echo "地図で表示するには main.js の土地活用レイヤをこのファイルを指すようにするか、TH_23521 用レイヤを追加してください。"

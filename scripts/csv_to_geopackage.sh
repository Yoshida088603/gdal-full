#!/usr/bin/env bash
# データ（14条地図除く）4フォルダの CSV を 1 CSV → 1 GeoPackage にストレート変換する。
# 使い方（gdal-full をカレントに）:
#   bash scripts/csv_to_geopackage.sh [入力ルート]   … 推奨
#   ./scripts/csv_to_geopackage.sh [入力ルート]     … 要 chmod +x
#  -s で既存 .gpkg をスキップ。入力未指定時は inputfile/.../データ_origin を使用。
# 前提: source env.sh で GDAL が使えること。

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONVERT_LOG="${PROJECT_ROOT}/convert_log_gpkg.txt"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$CONVERT_LOG" >&2; }

DATA_PARENT="$PROJECT_ROOT/inputfile/20260219昨年納品DVD/05ホームページ公開用データ及びプログラム"
INPUT_ROOT="${DATA_PARENT}/データ_origin"
SKIP_EXISTING=false
for arg in "$@"; do
  if [[ "$arg" == "-s" ]]; then
    SKIP_EXISTING=true
  else
    INPUT_ROOT="$arg"
  fi
done
OUTPUT_ROOT="$(dirname "$INPUT_ROOT")/データ_geopackage_converted"

export LANG=C.UTF-8
cd "$PROJECT_ROOT"

: > "$CONVERT_LOG"
log "csv_to_geopackage: PROJECT_ROOT=$PROJECT_ROOT"
log "csv_to_geopackage: INPUT_ROOT=$INPUT_ROOT"
log "csv_to_geopackage: OUTPUT_ROOT=$OUTPUT_ROOT"

if [[ ! -f "$PROJECT_ROOT/env.sh" ]]; then
  echo "Error: env.sh not found at $PROJECT_ROOT/env.sh" >&2
  exit 1
fi
source "$PROJECT_ROOT/env.sh" || { echo "Error: source env.sh failed" >&2; exit 1; }

if [[ ! -d "$INPUT_ROOT" ]]; then
  log "Error: Input root not found: $INPUT_ROOT"
  exit 1
fi
log "csv_to_geopackage: Starting conversion (skip_existing=$SKIP_EXISTING)"

mkdir -p "$OUTPUT_ROOT"
FAILED=0

TMPDIR="${TMPDIR:-/tmp}/csv_to_geopackage_$$"
mkdir -p "$TMPDIR"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

# ---- 街区基準点等データ（共通 Python で UTF-8 化・系番号取得し -s_srs 付きで GPKG 化） ----
FOLDER="街区基準点等データ"
IN_DIR="$INPUT_ROOT/$FOLDER"
OUT_DIR="$OUTPUT_ROOT/$FOLDER"
if [[ -d "$IN_DIR" ]]; then
  mkdir -p "$OUT_DIR"
  GAIKU_PY="$PROJECT_ROOT/scripts/csv_to_geoparquet_tochi.py"
  for csv in "$IN_DIR"/*.csv; do
    [[ -f "$csv" ]] || continue
    base=$(basename "$csv" .csv)
    out="$OUT_DIR/${base}.gpkg"
    if [[ "$SKIP_EXISTING" == true && -f "$out" ]]; then
      echo "[SKIP] $FOLDER/$base.csv"
      continue
    fi
    echo "[街区] $base.csv"
    tmp_csv="$TMPDIR/gaiku_${base}.csv"
    ZONE=$(python3 "$GAIKU_PY" "$csv" "$tmp_csv" --print-zukei 2>/dev/null | tail -1)
    if ! [[ "$ZONE" =~ ^[0-9]+$ ]] || (( ZONE < 1 || ZONE > 19 )); then
      echo "Warning: $FOLDER/$base.csv 座標系 1-19 が取得できません (ZONE=$ZONE)" >&2
      FAILED=1
      continue
    fi
    EPSG=$((6668 + ZONE))
    if ! ogr2ogr -skipfailures -f GPKG -nlt POINT \
      -s_srs "EPSG:$EPSG" -t_srs EPSG:3857 \
      -oo X_POSSIBLE_NAMES=X座標 \
      -oo Y_POSSIBLE_NAMES=Y座標 \
      "$out" "$tmp_csv" 2>&1; then
      echo "Warning: $FOLDER/$base.csv failed" >&2
      FAILED=1
    fi
  done
fi

# ---- 都市部官民基準点等データ（共通 Python で UTF-8 化・系番号取得し -s_srs 付きで GPKG 化） ----
FOLDER="都市部官民基準点等データ"
IN_DIR="$INPUT_ROOT/$FOLDER"
OUT_DIR="$OUTPUT_ROOT/$FOLDER"
if [[ -d "$IN_DIR" ]]; then
  mkdir -p "$OUT_DIR"
  TOSHI_PY="$PROJECT_ROOT/scripts/csv_to_geoparquet_tochi.py"
  for csv in "$IN_DIR"/*.csv; do
    [[ -f "$csv" ]] || continue
    base=$(basename "$csv" .csv)
    out="$OUT_DIR/${base}.gpkg"
    if [[ "$SKIP_EXISTING" == true && -f "$out" ]]; then
      echo "[SKIP] $FOLDER/$base.csv"
      continue
    fi
    echo "[都市部] $base.csv"
    tmp_csv="$TMPDIR/toshi_${base}.csv"
    ZONE=$(python3 "$TOSHI_PY" "$csv" "$tmp_csv" --print-zukei 2>/dev/null | tail -1)
    if ! [[ "$ZONE" =~ ^[0-9]+$ ]] || (( ZONE < 1 || ZONE > 19 )); then
      echo "Warning: $FOLDER/$base.csv 座標系 1-19 が取得できません (ZONE=$ZONE)" >&2
      FAILED=1
      continue
    fi
    EPSG=$((6668 + ZONE))
    if ! ogr2ogr -skipfailures -f GPKG -nlt POINT \
      -s_srs "EPSG:$EPSG" -t_srs EPSG:3857 \
      -oo X_POSSIBLE_NAMES=X座標 \
      -oo Y_POSSIBLE_NAMES=Y座標 \
      "$out" "$tmp_csv" 2>&1; then
      echo "Warning: $FOLDER/$base.csv failed" >&2
      FAILED=1
    fi
  done
fi

# ---- 土地活用推進調査（Python で仮ヘッダ付き UTF-8 CSV を生成してから ogr2ogr） ----
FOLDER="土地活用推進調査"
IN_DIR="$INPUT_ROOT/$FOLDER"
OUT_DIR="$OUTPUT_ROOT/$FOLDER"
if [[ -d "$IN_DIR" ]]; then
  mkdir -p "$OUT_DIR"
  TOCHI_PY="$PROJECT_ROOT/scripts/csv_to_geoparquet_tochi.py"
  for csv in "$IN_DIR"/*.csv; do
    [[ -f "$csv" ]] || continue
    base=$(basename "$csv" .csv)
    out="$OUT_DIR/${base}.gpkg"
    if [[ "$SKIP_EXISTING" == true && -f "$out" ]]; then
      echo "[SKIP] $FOLDER/$base.csv"
      continue
    fi
    echo "[土地活用] $base.csv"
    tmp_csv="$TMPDIR/${base}_tochi.csv"
    if ! python3 "$TOCHI_PY" "$csv" "$tmp_csv"; then
      echo "Warning: $FOLDER/$base.csv preprocess failed" >&2
      FAILED=1
      continue
    fi
    if ! ogr2ogr -skipfailures -f GPKG \
      -oo X_POSSIBLE_NAMES=x \
      -oo Y_POSSIBLE_NAMES=y \
      "$out" "$tmp_csv" 2>&1; then
      echo "Warning: $FOLDER/$base.csv ogr2ogr failed" >&2
      FAILED=1
    fi
  done
fi

# ---- 公図と現況のずれデータ（Python で WKT 付き CSV を生成してから ogr2ogr） ----
FOLDER="公図と現況のずれデータ"
IN_DIR="$INPUT_ROOT/$FOLDER"
OUT_DIR="$OUTPUT_ROOT/$FOLDER"
if [[ -d "$IN_DIR" ]]; then
  mkdir -p "$OUT_DIR"
  KOZU_PY="$PROJECT_ROOT/scripts/csv_to_geoparquet_kozu.py"
  for subdir in "$IN_DIR"/*/; do
    [[ -d "$subdir" ]] || continue
    subname=$(basename "$subdir")
    csv="$subdir/配置テキスト.csv"
    [[ -f "$csv" ]] || continue
    base="${subname}_配置テキスト"
    out="$OUT_DIR/${base}.gpkg"
    if [[ "$SKIP_EXISTING" == true && -f "$out" ]]; then
      echo "[SKIP] $FOLDER/$subname/配置テキスト.csv"
      continue
    fi
    echo "[公図] $subname/配置テキスト.csv"
    tmp_csv="$TMPDIR/kozu_${subname}.csv"
    if ! python3 "$KOZU_PY" "$csv" "$tmp_csv"; then
      echo "Warning: $FOLDER/$subname/配置テキスト.csv preprocess failed" >&2
      FAILED=1
      continue
    fi
    if ! ogr2ogr -skipfailures -f GPKG "$out" "$tmp_csv" 2>&1; then
      echo "Warning: $FOLDER/$subname/配置テキスト.csv ogr2ogr failed" >&2
      FAILED=1
    fi
  done
  for csv in "$IN_DIR"/*.csv; do
    [[ -f "$csv" ]] || continue
    base=$(basename "$csv" .csv)
    out="$OUT_DIR/${base}.gpkg"
    if [[ "$SKIP_EXISTING" == true && -f "$out" ]]; then
      echo "[SKIP] $FOLDER/$base.csv"
      continue
    fi
    echo "[公図] $base.csv"
    tmp_csv="$TMPDIR/kozu_${base}.csv"
    if ! python3 "$KOZU_PY" "$csv" "$tmp_csv"; then
      echo "Warning: $FOLDER/$base.csv preprocess failed" >&2
      FAILED=1
      continue
    fi
    if ! ogr2ogr -skipfailures -f GPKG "$out" "$tmp_csv" 2>&1; then
      echo "Warning: $FOLDER/$base.csv ogr2ogr failed" >&2
      FAILED=1
    fi
  done
fi

[[ $FAILED -eq 0 ]] || { log "一部でエラーがありました。上記を確認してください。"; true; }
log "Done. Outputs in $OUTPUT_ROOT"

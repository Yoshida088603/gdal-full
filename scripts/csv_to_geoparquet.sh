#!/usr/bin/env bash
# データ（14条地図除く）4フォルダの CSV を 1 CSV → 1 GeoParquet にストレート変換する（第1段階）。
# 使い方（gdal-full をカレントに）:
#   bash scripts/csv_to_geoparquet.sh [入力ルート]   … 推奨（実行権限不要）
#   ./scripts/csv_to_geoparquet.sh [入力ルート]      … 要 chmod +x
#  -s で既存 parquet をスキップ。入力未指定時は inputfile/.../データ_origin を使用。
# 前提: build_gdal_full.sh 実行済み。Parquet ドライバは Arrow/Parquet 検出時に有効。

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONVERT_LOG="${PROJECT_ROOT}/convert_log.txt"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$CONVERT_LOG" >&2; }

# 入力ルート: 引数またはデフォルト（データ_origin）。-s で既存 parquet をスキップ。
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
OUTPUT_ROOT="$(dirname "$INPUT_ROOT")/データ_geoparquet_converted"

export LANG=C.UTF-8
cd "$PROJECT_ROOT"

# 起動メッセージ（表示＋ログファイルに追記）
: > "$CONVERT_LOG"  # 新規実行でログをリセット
log "csv_to_geoparquet: PROJECT_ROOT=$PROJECT_ROOT"
log "csv_to_geoparquet: INPUT_ROOT=$INPUT_ROOT"
log "csv_to_geoparquet: OUTPUT_ROOT=$OUTPUT_ROOT"

# gdal-full の GDAL を有効化
if [[ ! -f "$PROJECT_ROOT/env.sh" ]]; then
  echo "Error: env.sh not found at $PROJECT_ROOT/env.sh" >&2
  exit 1
fi
source "$PROJECT_ROOT/env.sh" || { echo "Error: source env.sh failed (GDAL not built?)" >&2; exit 1; }

# Parquet ドライバの確認
if ! ogrinfo --formats 2>/dev/null | grep -q "Parquet"; then
  echo "Error: GDAL Parquet driver is not available. See docs/parquet_build.md" >&2
  exit 1
fi
log "csv_to_geoparquet: GDAL Parquet driver OK"

if [[ ! -d "$INPUT_ROOT" ]]; then
  log "Error: Input root not found: $INPUT_ROOT"
  exit 1
fi
log "csv_to_geoparquet: Starting conversion (skip_existing=$SKIP_EXISTING)"

mkdir -p "$OUTPUT_ROOT"
FAILED=0

# 一時ディレクトリ（都市部・土地活用・公図の前処理用）
TMPDIR="${TMPDIR:-/tmp}/csv_to_geoparquet_$$"
mkdir -p "$TMPDIR"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

# ---- 街区基準点等データ ----
FOLDER="街区基準点等データ"
IN_DIR="$INPUT_ROOT/$FOLDER"
OUT_DIR="$OUTPUT_ROOT/$FOLDER"
if [[ -d "$IN_DIR" ]]; then
  mkdir -p "$OUT_DIR"
  for csv in "$IN_DIR"/*.csv; do
    [[ -f "$csv" ]] || continue
    base=$(basename "$csv" .csv)
    out="$OUT_DIR/${base}.parquet"
    if [[ "$SKIP_EXISTING" == true && -f "$out" ]]; then
      echo "[SKIP] $FOLDER/$base.csv"
      continue
    fi
    echo "[街区] $base.csv"
    if ! ogr2ogr -skipfailures -f Parquet -lco GEOMETRY_ENCODING=WKB \
      -oo X_POSSIBLE_NAMES=X座標 \
      -oo Y_POSSIBLE_NAMES=Y座標 \
      "$out" "$csv" 2>&1; then
      echo "Warning: $FOLDER/$base.csv failed" >&2
      FAILED=1
    fi
  done
fi

# ---- 都市部官民基準点等データ（iconv で UTF-8 化してから ogr2ogr） ----
FOLDER="都市部官民基準点等データ"
IN_DIR="$INPUT_ROOT/$FOLDER"
OUT_DIR="$OUTPUT_ROOT/$FOLDER"
if [[ -d "$IN_DIR" ]]; then
  mkdir -p "$OUT_DIR"
  for csv in "$IN_DIR"/*.csv; do
    [[ -f "$csv" ]] || continue
    base=$(basename "$csv" .csv)
    out="$OUT_DIR/${base}.parquet"
    if [[ "$SKIP_EXISTING" == true && -f "$out" ]]; then
      echo "[SKIP] $FOLDER/$base.csv"
      continue
    fi
    echo "[都市部] $base.csv"
    tmp_csv="$TMPDIR/${base}_utf8.csv"
    if ! iconv -f CP932 -t UTF-8 "$csv" > "$tmp_csv" 2>/dev/null; then
      # CP932 で失敗した場合はそのまま使用（UTF-8 の可能性）
      cp "$csv" "$tmp_csv"
    fi
    if ! ogr2ogr -skipfailures -f Parquet -lco GEOMETRY_ENCODING=WKB \
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
    out="$OUT_DIR/${base}.parquet"
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
    if ! ogr2ogr -skipfailures -f Parquet -lco GEOMETRY_ENCODING=WKB \
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
    # 出力名は一意に（サブフォルダ名_配置テキスト.parquet）
    base="${subname}_配置テキスト"
    out="$OUT_DIR/${base}.parquet"
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
    if ! ogr2ogr -skipfailures -f Parquet -lco GEOMETRY_ENCODING=WKB \
      "$out" "$tmp_csv" 2>&1; then
      echo "Warning: $FOLDER/$subname/配置テキスト.csv ogr2ogr failed" >&2
      FAILED=1
    fi
  done
  # サブフォルダ以外の配置テキスト.csv（ルート直下など）
  for csv in "$IN_DIR"/*.csv; do
    [[ -f "$csv" ]] || continue
    base=$(basename "$csv" .csv)
    out="$OUT_DIR/${base}.parquet"
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
    if ! ogr2ogr -skipfailures -f Parquet -lco GEOMETRY_ENCODING=WKB \
      "$out" "$tmp_csv" 2>&1; then
      echo "Warning: $FOLDER/$base.csv ogr2ogr failed" >&2
      FAILED=1
    fi
  done
fi

[[ $FAILED -eq 0 ]] || { log "一部でエラーがありました。上記を確認してください。"; true; }
log "Done. Outputs in $OUTPUT_ROOT"

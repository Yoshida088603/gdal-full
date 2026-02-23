#!/usr/bin/env bash
# SHP → GeoParquet → FGB / PMTiles パイプライン（gdal-full の GDAL 使用）
# 使い方: ./scripts/run_pipeline.sh または bash scripts/run_pipeline.sh
# 前提: build_gdal_full.sh 実行済み。Parquet ドライバは Arrow/Parquet 検出時に有効。

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INPUT_DIR="$PROJECT_ROOT/input_data"
OUTPUT_DIR="$PROJECT_ROOT/output_data"

export LANG=C.UTF-8
cd "$PROJECT_ROOT"

# gdal-full の GDAL を有効化
if [[ -f "$PROJECT_ROOT/env.sh" ]]; then
  source "$PROJECT_ROOT/env.sh"
else
  echo "Error: env.sh not found. Run from gdal-full directory." >&2
  exit 1
fi

# 必須ドライバの確認
FORMATS=$(ogrinfo --formats 2>/dev/null || true)
for drv in Parquet FlatGeobuf PMTiles; do
  if ! echo "$FORMATS" | grep -q "$drv"; then
    echo "Error: GDAL driver '$drv' is not available." >&2
    if echo "$drv" | grep -q Parquet; then
      echo "Parquet requires Apache Arrow/Parquet C++. See README and docs/parquet_build.md" >&2
    fi
    exit 1
  fi
done

mkdir -p "$OUTPUT_DIR"

shopt -s nullglob
FAILED=0
for shp in "$INPUT_DIR"/*.shp; do
  base=$(basename "$shp" .shp)
  echo "=== $base ==="
  if ! ogr2ogr -skipfailures -f Parquet -lco GEOMETRY_ENCODING=WKB \
    "$OUTPUT_DIR/${base}.parquet" "$shp" 2>&1; then
    echo "Warning: $base SHP→Parquet でエラー（スキップして続行）" >&2
    FAILED=1
    continue
  fi
  [[ -f "$OUTPUT_DIR/${base}.parquet" ]] || continue
  ogr2ogr -f FlatGeobuf "$OUTPUT_DIR/${base}.fgb" "$OUTPUT_DIR/${base}.parquet" 2>&1 || true
  ogr2ogr -skipfailures -dsco MINZOOM=0 -dsco MAXZOOM=15 -f "PMTiles" \
    "$OUTPUT_DIR/${base}.pmtiles" "$OUTPUT_DIR/${base}.parquet" 2>&1 || true
done
[[ $FAILED -eq 0 ]] || { echo "一部レイヤでエラーがありました。上記を確認してください。" >&2; true; }

echo "Done. Outputs in $OUTPUT_DIR"

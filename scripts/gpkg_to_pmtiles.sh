#!/usr/bin/env bash
# GeoPackage を PMTiles に変換する。同じディレクトリに .pmtiles を出力する。
# run_pipeline.sh と同じく GeoParquet を経由する（Parquet → PMTiles は既存パイプラインで実績あり）。
# 使い方（gdal-full をカレントに）:
#   source env.sh
#   ./scripts/gpkg_to_pmtiles.sh [入力.gpkg]
# 未指定時は データ_geopackage_marged/土地活用推進調査_merged.gpkg を使用。

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_PARENT="$PROJECT_ROOT/inputfile/20260219昨年納品DVD/05ホームページ公開用データ及びプログラム"
DEFAULT_GPKG="$DATA_PARENT/データ_geopackage_marged/土地活用推進調査_merged.gpkg"

GPKG="${1:-$DEFAULT_GPKG}"
if [[ ! -f "$GPKG" ]]; then
  echo "Error: GeoPackage not found: $GPKG" >&2
  exit 1
fi

DIR="$(dirname "$GPKG")"
BASE="$(basename "$GPKG" .gpkg)"
OUT_PMTILES="$DIR/${BASE}.pmtiles"
OUT_PARQUET="$DIR/${BASE}.parquet"

cd "$PROJECT_ROOT"

# 出力は Web メルカトル(EPSG:3857) に統一（位置ずれ防止）
T_SRS="-t_srs EPSG:3857"

# 1) 直接 GPKG → PMTiles を試す
echo "Converting: $GPKG -> $OUT_PMTILES"
err=$(ogr2ogr -skipfailures -nlt PROMOTE_TO_MULTI $T_SRS -dsco MINZOOM=0 -dsco MAXZOOM=15 \
  -f "PMTiles" "$OUT_PMTILES" "$GPKG" 2>&1) || true
if [[ -f "$OUT_PMTILES" ]]; then
  echo "Done. Output: $OUT_PMTILES"
  exit 0
fi
if echo "$err" | grep -q "does not support data source creation"; then
  echo "PMTiles 直接出力は非対応のため、GeoParquet を経由します（run_pipeline.sh と同じ経路）。" >&2
else
  echo "$err" >&2
fi

# 2) GPKG → GeoParquet（CRS を 3857 で明示）
echo "Writing GeoParquet: $OUT_PARQUET"
if ! ogr2ogr -skipfailures $T_SRS -f Parquet -lco GEOMETRY_ENCODING=WKB "$OUT_PARQUET" "$GPKG" 2>&1; then
  echo "Error: GeoParquet の作成に失敗しました。" >&2
  exit 1
fi
[[ -f "$OUT_PARQUET" ]] || { echo "Error: Parquet が生成されませんでした。" >&2; exit 1; }

# 3) GeoParquet → PMTiles（入力も 3857 と明示して位置ずれ防止）
echo "Writing PMTiles: $OUT_PMTILES"
pmt_err=$(ogr2ogr -skipfailures -s_srs EPSG:3857 $T_SRS -dsco MINZOOM=0 -dsco MAXZOOM=15 -f "PMTiles" \
  "$OUT_PMTILES" "$OUT_PARQUET" 2>&1) || true

if [[ -f "$OUT_PMTILES" ]]; then
  rm -f "$OUT_PARQUET"
  echo "Done. Output: $OUT_PMTILES"
  exit 0
fi

# PMTiles が作成されなかった場合
if echo "$pmt_err" | grep -q "does not support data source creation"; then
  echo "" >&2
  echo "この GDAL ビルドでは PMTiles の書き込みが無効です（ドライバは読み取り専用）。" >&2
  echo "GeoParquet は出力済みです: $OUT_PARQUET" >&2
  echo "PMTiles が必要な場合:" >&2
  echo "  - GDAL を PMTiles 書き込み対応で再ビルドする、または" >&2
  echo "  - rm -rf gdal-build gdal-src のあと ./build_gdal_full.sh でまっさら再ビルドする、" >&2
  echo "  - それでも不可なら GDAL_VERSION=3.9.0 で再ビルドする。" >&2
else
  echo "$pmt_err" >&2
  echo "Parquet は残しています: $OUT_PARQUET" >&2
fi
exit 1

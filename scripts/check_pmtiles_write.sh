#!/usr/bin/env bash
# この GDAL ビルドで PMTiles の書き出しが可能か確認する。
# 使い方（gdal-full をカレントに）: source env.sh && ./scripts/check_pmtiles_write.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== PMTiles 書き出し可否の確認 ==="
echo "GDAL: $(ogr2ogr --version 2>/dev/null || true)"
echo ""

# 1) ドライバが登録されているか
if ! ogrinfo --formats 2>/dev/null | grep -q "PMTiles"; then
  echo "結果: 不可（PMTiles ドライバが登録されていません）"
  exit 1
fi
echo "1) PMTiles ドライバ: 登録あり"

# 2) 最小の GeoPackage を用意（1 点のみ、EPSG:4326）
TMP_DIR="${TMPDIR:-/tmp}"
MIN_GPKG="$TMP_DIR/check_pmtiles_minimal_$$.gpkg"
OUT_PMTILES="$TMP_DIR/check_pmtiles_out_$$.pmtiles"
trap 'rm -f "$MIN_GPKG" "$OUT_PMTILES"' EXIT

GEOJSON='{"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[139.7,35.6]},"properties":{}}]}'
echo "$GEOJSON" > "$TMP_DIR/check_pmtiles_minimal_$$.geojson"
MIN_GEOJSON="$TMP_DIR/check_pmtiles_minimal_$$.geojson"
trap 'rm -f "$MIN_GPKG" "$OUT_PMTILES" "$MIN_GEOJSON"' EXIT

if ! ogr2ogr -f GPKG "$MIN_GPKG" "$MIN_GEOJSON" -nln p 2>/dev/null; then
  echo "2) 最小 GPKG の作成: スキップ（GeoJSON から作成失敗）"
  echo "   既存の .gpkg で試します..."
  # 既存の小さな gpkg があれば使う（1 レイヤのみ）
  EXISTING=$(find "$PROJECT_ROOT" -name "*.gpkg" -type f 2>/dev/null | head -1)
  if [[ -z "$EXISTING" || ! -f "$EXISTING" ]]; then
    echo "結果: 確認できず（テスト用 GPKG がありません）"
    exit 2
  fi
  MIN_GPKG="$EXISTING"
fi

# 3) PMTiles 書き出しを試行
echo "2) 最小 GPKG: 用意済み"
echo "3) PMTiles 書き出しを試行: $OUT_PMTILES"
err=$(ogr2ogr -skipfailures -dsco MINZOOM=0 -dsco MAXZOOM=5 \
  -f "PMTiles" "$OUT_PMTILES" "$MIN_GPKG" 2>&1) || true

if echo "$err" | grep -q "does not support data source creation"; then
  echo ""
  echo "結果: 不可（PMTiles の書き込みはこのビルドでは無効です）"
  echo "      メッセージ: driver does not support data source creation"
  echo ""
  echo "対処: ビルドログで 'Could NOT find GEOS' なら libgeos-dev を入れて再ビルド:"
  echo "      sudo apt install libgeos-dev"
  echo "      rm -rf gdal-build gdal-src && ./build_gdal_full.sh"
  echo "      それでも不可なら GDAL_VERSION=3.9.0 で再ビルドを試してください。"
  exit 1
fi

if [[ -f "$OUT_PMTILES" ]]; then
  echo ""
  echo "結果: 可（PMTiles を書き出せます）"
  echo "      テスト出力: $OUT_PMTILES"
  exit 0
fi

echo ""
echo "結果: 不明（ファイルは作成されませんでした）"
echo "      stderr: $err"
exit 2

#!/usr/bin/env bash
# 14条地図 配下の全 Shapefile を 1 つの GeoPackage にマージし、1 つの PMTiles に変換する。
# 使い方: ./scripts/run_pipeline_14jyo.sh
# 前提: env.sh で GDAL が有効になること。出力: output_data/14条地図.pmtiles

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INPUT_14JYO="$PROJECT_ROOT/input_data/14条地図"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/output_data}"
MERGE_GPKG="$OUTPUT_DIR/14条地図_merge.gpkg"
OUTPUT_PMTILES="$OUTPUT_DIR/14条地図.pmtiles"
LAYER_NAME="14条地図"

export LANG=C.UTF-8
cd "$PROJECT_ROOT"

if [[ ! -f "$PROJECT_ROOT/env.sh" ]]; then
  echo "Error: env.sh not found. Run from gdal-full directory." >&2
  exit 1
fi
source "$PROJECT_ROOT/env.sh"

# 必須ドライバ: GeoPackage（マージ用）, PMTiles（出力用）
FORMATS=$(ogrinfo --formats 2>/dev/null || true)
for drv in GPKG PMTiles; do
  if ! echo "$FORMATS" | grep -q "$drv"; then
    echo "Error: GDAL driver '$drv' is not available." >&2
    exit 1
  fi
done

if [[ ! -d "$INPUT_14JYO" ]]; then
  echo "Error: Input directory not found: $INPUT_14JYO" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# 全 .shp をソートしてリスト（順序を固定）
SHPS=()
while IFS= read -r -d '' f; do
  SHPS+=( "$f" )
done < <(find "$INPUT_14JYO" -name "*.shp" -print0 | sort -z)
NUM_SHPS=${#SHPS[@]}

if [[ $NUM_SHPS -eq 0 ]]; then
  echo "Error: No .shp files found under $INPUT_14JYO" >&2
  exit 1
fi

echo "Found $NUM_SHPS shapefile(s). Merging into one GeoPackage, then writing PMTiles."

# 既存マージ成果物があれば削除（再実行時はクリーンに）
rm -f "$MERGE_GPKG"

# 座標系: 14条地図は1系〜15系でCRSが異なるため、マージ時に WGS84 (EPSG:4326) に統一する。
# 入力 SHP に .prj が無い場合があるため、パス中の "N系" から JGD2011 平面直角N系 (EPSG:6668+N) を -s_srs で指定する。
# GeoParquet/GeoPackage は1レイヤあたり1つのCRSを前提としており、混在は想定されていない。
T_SRS="${T_SRS:-EPSG:4326}"

# パスから平面直角の系番号を取得し、EPSG を返す。例: .../10系/... -> EPSG:6678 (JGD2011 10系)
get_s_srs_for_shp() {
  local path="$1"
  if [[ "$path" =~ ([0-9]+)系 ]]; then
    local n="${BASH_REMATCH[1]}"
    if [[ "$n" -ge 1 && "$n" -le 19 ]]; then
      echo "EPSG:$((6668 + n))"
      return
    fi
  fi
  echo ""  # 判別できない場合は空（-s_srs なしで実行し .prj に任せる）
}

# 1 件目: 新規 GeoPackage 作成
S_SRS0=$(get_s_srs_for_shp "${SHPS[0]}")
echo "=== 1/$NUM_SHPS: ${SHPS[0]} (s_srs=${S_SRS0:-<from .prj>}) ==="
if [[ -n "$S_SRS0" ]]; then
  if ! ogr2ogr -skipfailures -s_srs "$S_SRS0" -t_srs "$T_SRS" -f GPKG -nln "$LAYER_NAME" "$MERGE_GPKG" "${SHPS[0]}" 2>&1; then
    echo "Error: Failed to create merge GPKG from first file." >&2
    exit 1
  fi
else
  if ! ogr2ogr -skipfailures -t_srs "$T_SRS" -f GPKG -nln "$LAYER_NAME" "$MERGE_GPKG" "${SHPS[0]}" 2>&1; then
    echo "Error: Failed to create merge GPKG from first file." >&2
    exit 1
  fi
fi

# 2 件目以降: 同一 GPKG の同一レイヤに append
for (( i=1; i<NUM_SHPS; i++ )); do
  S_SRS=$(get_s_srs_for_shp "${SHPS[$i]}")
  echo "=== $((i+1))/$NUM_SHPS: ${SHPS[$i]} (s_srs=${S_SRS:-<from .prj>}) ==="
  if [[ -n "$S_SRS" ]]; then
    ogr2ogr -skipfailures -s_srs "$S_SRS" -t_srs "$T_SRS" -update -append -nln "$LAYER_NAME" "$MERGE_GPKG" "${SHPS[$i]}" 2>&1 || true
  else
    ogr2ogr -skipfailures -t_srs "$T_SRS" -update -append -nln "$LAYER_NAME" "$MERGE_GPKG" "${SHPS[$i]}" 2>&1 || true
  fi
done

if [[ ! -f "$MERGE_GPKG" ]]; then
  echo "Error: Merge GPKG was not created." >&2
  exit 1
fi

# マージ済み GPKG → PMTiles（既存パイプラインと同様のオプション）
echo "=== Writing PMTiles: $OUTPUT_PMTILES ==="
if ! ogr2ogr -skipfailures -nlt PROMOTE_TO_MULTI -dsco MINZOOM=0 -dsco MAXZOOM=15 -f "PMTiles" \
  "$OUTPUT_PMTILES" "$MERGE_GPKG" "$LAYER_NAME" 2>&1; then
  echo "Warning: PMTiles conversion had errors. Check output." >&2
fi

if [[ -f "$OUTPUT_PMTILES" ]]; then
  echo "Done. Output: $OUTPUT_PMTILES"
else
  echo "Error: PMTiles file was not created." >&2
  exit 1
fi

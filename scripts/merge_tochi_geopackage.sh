#!/usr/bin/env bash
# データ_geopackage_converted/土地活用推進調査 内の全 .gpkg を
# Web メルカトル（EPSG:3857）に変換して 1 本にマージする。
# 推奨: 属性の「座標系」でファイルごとに CRS を切り替える Python 版を使うこと。
#   source env.sh && python3 scripts/merge_tochi_geopackage.py
# 本スクリプトは全ファイルを単一 CRS（デフォルト IX 系）で変換する。九州等が混在する場合は誤った位置になる。
# 使い方: source env.sh && bash scripts/merge_tochi_geopackage.sh
# 出力: データ_geopackage_converted/土地活用推進調査_merged.gpkg

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_PARENT="$PROJECT_ROOT/inputfile/20260219昨年納品DVD/05ホームページ公開用データ及びプログラム"
INPUT_DIR="${DATA_PARENT}/データ_geopackage_converted/土地活用推進調査"
OUTPUT_FILE="${DATA_PARENT}/データ_geopackage_converted/土地活用推進調査_merged.gpkg"

# 土地活用の元 CSV は平面直角座標（メートル）。 zone 未指定のため IX 系（関東）を仮定。他系の場合は SRC_SRS を変更すること。
SRC_SRS="${SRC_SRS:-EPSG:6674}"
TGT_SRS="EPSG:3857"

export LANG=C.UTF-8
cd "$PROJECT_ROOT"

if [[ ! -f "$PROJECT_ROOT/env.sh" ]]; then
  echo "Error: env.sh not found" >&2
  exit 1
fi
source "$PROJECT_ROOT/env.sh" || exit 1

if [[ ! -d "$INPUT_DIR" ]]; then
  echo "Error: input directory not found: $INPUT_DIR" >&2
  exit 1
fi

shopt -s nullglob
gpkgs=("$INPUT_DIR"/*.gpkg)
if [[ ${#gpkgs[@]} -eq 0 ]]; then
  echo "Error: no .gpkg files in $INPUT_DIR" >&2
  exit 1
fi

echo "Merge 土地活用推進調査: ${#gpkgs[@]} files -> Web Mercator ($TGT_SRS) -> $OUTPUT_FILE" >&2
first=true
merged=0
for gpkg in "${gpkgs[@]}"; do
  base=$(basename "$gpkg" .gpkg)
  if [[ "$first" == true ]]; then
    ogr2ogr -f GPKG -nln tochi_merged \
      -s_srs "$SRC_SRS" -t_srs "$TGT_SRS" \
      "$OUTPUT_FILE" "$gpkg" || { echo "Warning: failed $base" >&2; continue; }
    first=false
    ((merged++)) || true
  else
    ogr2ogr -update -append -nln tochi_merged \
      -s_srs "$SRC_SRS" -t_srs "$TGT_SRS" \
      "$OUTPUT_FILE" "$gpkg" || { echo "Warning: failed $base" >&2; continue; }
    ((merged++)) || true
  fi
  if [[ $((merged % 100)) -eq 0 ]]; then
    echo "Progress: $merged files merged ..." >&2
  fi
done

echo "Merged: $merged files. Output: $OUTPUT_FILE" >&2
if [[ $merged -eq 0 ]]; then
  echo "Error: no files were merged." >&2
  exit 1
fi
echo "Done." >&2

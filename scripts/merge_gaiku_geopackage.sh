#!/usr/bin/env bash
# データ_geopackage_converted/街区基準点等データ 内の全 .gpkg を 1 本にマージする。
# 各 GPKG は csv_to_geopackage.sh で既に EPSG:3857 になっているため SRS 変換は不要。
# 使い方: source env.sh && bash scripts/merge_gaiku_geopackage.sh
# 出力: データ_geopackage_marged/街区基準点等_merged.gpkg（レイヤ名: gaiku_merged）

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_PARENT="$PROJECT_ROOT/inputfile/20260219昨年納品DVD/05ホームページ公開用データ及びプログラム"
INPUT_DIR="${DATA_PARENT}/データ_geopackage_converted/街区基準点等データ"
OUTPUT_FILE="${DATA_PARENT}/データ_geopackage_marged/街区基準点等_merged.gpkg"

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

mkdir -p "$(dirname "$OUTPUT_FILE")"
echo "Merge 街区基準点等: ${#gpkgs[@]} files -> $OUTPUT_FILE" >&2
first=true
merged=0
for gpkg in "${gpkgs[@]}"; do
  base=$(basename "$gpkg" .gpkg)
  if [[ "$first" == true ]]; then
    ogr2ogr -f GPKG -nln gaiku_merged \
      "$OUTPUT_FILE" "$gpkg" || { echo "Warning: failed $base" >&2; continue; }
    first=false
    ((merged++)) || true
  else
    ogr2ogr -update -append -nln gaiku_merged \
      "$OUTPUT_FILE" "$gpkg" || { echo "Warning: failed $base" >&2; continue; }
    ((merged++)) || true
  fi
  if [[ $((merged % 500)) -eq 0 ]]; then
    echo "Progress: $merged files merged ..." >&2
  fi
done

echo "Merged: $merged files. Output: $OUTPUT_FILE" >&2
if [[ $merged -eq 0 ]]; then
  echo "Error: no files were merged." >&2
  exit 1
fi
echo "Done." >&2

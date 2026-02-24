#!/usr/bin/env bash
# PostgreSQL → GeoParquet → FGB / PMTiles パイプライン（gdal-full の GDAL 使用）
# 使い方: PG_CONNECTION を設定するか第1引数で接続文字列を渡して ./scripts/run_pipeline_pg.sh
# 前提: ダンプをリストアした PostgreSQL/PostGIS が起動していること。詳細は docs/pipeline_pg.md 参照。

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/output_data}"

export LANG=C.UTF-8
cd "$PROJECT_ROOT"

# gdal-full の GDAL を有効化
if [[ -f "$PROJECT_ROOT/env.sh" ]]; then
  source "$PROJECT_ROOT/env.sh"
else
  echo "Error: env.sh not found. Run from gdal-full directory." >&2
  exit 1
fi

# 接続文字列: 環境変数 PG_CONNECTION または第1引数（デフォルトは書かない）
if [[ -n "${PG_CONNECTION:-}" ]]; then
  : # 使用
elif [[ -n "${1:-}" ]]; then
  export PG_CONNECTION="$1"
else
  echo "Error: Set PG_CONNECTION or pass connection string as first argument. Example: PG:\"dbname=gis_export host=localhost port=5432 user=postgres\"" >&2
  exit 1
fi

# 必須ドライバの確認（Parquet / FlatGeobuf / PMTiles / PostgreSQL）
FORMATS=$(ogrinfo --formats 2>/dev/null || true)
for drv in Parquet FlatGeobuf PMTiles PostgreSQL; do
  if ! echo "$FORMATS" | grep -q "$drv"; then
    echo "Error: GDAL driver '$drv' is not available." >&2
    if [[ "$drv" == "PostgreSQL" ]]; then
      echo "PostgreSQL requires libpq. See docs/pipeline_pg.md for enabling." >&2
    fi
    exit 1
  fi
done

# 対象レイヤ一覧を取得（"Layer name:" または "N: name (Type)" 形式の両方に対応）
export PG_LIST_ALL_TABLES=YES
LAYERS=$(ogrinfo -so "$PG_CONNECTION" 2>/dev/null | sed -n -e 's/^Layer name: *//p' -e 's/^[0-9]*: *\([^ (]*\).*/\1/p' | grep -v '^$' | sort -u || true)
if [[ -z "$LAYERS" ]]; then
  echo "Error: No layers found for $PG_CONNECTION" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
FAILED=0

while IFS= read -r layer; do
  [[ -z "$layer" ]] && continue
  # ファイル名用: スキーマ.テーブル → スキーマ_テーブル
  safe_name="${layer//./_}"
  safe_name="${safe_name//\//_}"
  echo "=== $layer → $safe_name ==="
  if ! ogr2ogr -skipfailures -f Parquet -lco GEOMETRY_ENCODING=WKB \
    "$OUTPUT_DIR/${safe_name}.parquet" "$PG_CONNECTION" "$layer" 2>&1; then
    echo "Warning: $layer PG→Parquet でエラー（スキップして続行）" >&2
    FAILED=1
    continue
  fi
  [[ -f "$OUTPUT_DIR/${safe_name}.parquet" ]] || continue
  # ジオメトリがある場合のみ FGB / PMTiles を出力（Geometry: None のレイヤはスキップ）
  HAS_GEOM=$(ogrinfo -so "$OUTPUT_DIR/${safe_name}.parquet" 2>/dev/null | sed -n 's/^Geometry: *//p' | head -1)
  if [[ -n "$HAS_GEOM" && "$HAS_GEOM" != "None" ]]; then
    ogr2ogr -f FlatGeobuf -nlt PROMOTE_TO_MULTI -lco SPATIAL_INDEX=NO \
      "$OUTPUT_DIR/${safe_name}.fgb" "$OUTPUT_DIR/${safe_name}.parquet" 2>&1 || true
    ogr2ogr -skipfailures -dsco MINZOOM=0 -dsco MAXZOOM=15 -f "PMTiles" \
      "$OUTPUT_DIR/${safe_name}.pmtiles" "$OUTPUT_DIR/${safe_name}.parquet" 2>&1 || true
  else
    echo "  (ジオメトリなしのため FGB/PMTiles はスキップ)"
  fi
done <<< "$LAYERS"

[[ $FAILED -eq 0 ]] || { echo "一部レイヤでエラーがありました。上記を確認してください。" >&2; true; }
echo "Done. Outputs in $OUTPUT_DIR"

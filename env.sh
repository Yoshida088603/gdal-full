# gdal-full でビルドした GDAL を使うための環境設定
# 使い方: source /home/ubuntu/projects/gdal-full/env.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
LOCAL="$SCRIPT_DIR/local"

if [[ ! -x "$LOCAL/bin/ogr2ogr" ]]; then
  echo "GDAL がまだビルドされていません。先に $SCRIPT_DIR/build_gdal_full.sh を実行してください." >&2
  echo "  (参照: $LOCAL/bin/ogr2ogr が存在しません)" >&2
  return 1 2>/dev/null || exit 1
fi

export PATH="$LOCAL/bin:$PATH"
# Arrow/Parquet を arrow-install でビルドした場合は実行時に必要
if [[ -d "$SCRIPT_DIR/arrow-install/lib" ]]; then
  export LD_LIBRARY_PATH="$SCRIPT_DIR/arrow-install/lib:$LOCAL/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
else
  export LD_LIBRARY_PATH="$LOCAL/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export GDAL_DATA="$LOCAL/share/gdal"

# Python バインド（build_gdal_full.sh で BUILD_PYTHON_BINDINGS=ON の場合に local にインストールされる）
for _p in "$LOCAL"/lib/python*/site-packages; do
  if [[ -d "$_p" ]]; then
    export PYTHONPATH="$_p${PYTHONPATH:+:$PYTHONPATH}"
    break
  fi
done

echo "GDAL (gdal-full): $(ogr2ogr --version 2>/dev/null || true)"

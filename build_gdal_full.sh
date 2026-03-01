#!/usr/bin/env bash
# フル機能 GDAL（Parquet / FlatGeobuf / PMTiles 等）を gdal-full 直下に隔離ビルドする。
# このディレクトリを削除すればインストールもすべて消える。

set -e
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$PROJECT_ROOT/local"
SRC_DIR="$PROJECT_ROOT/gdal-src"
BUILD_DIR="$PROJECT_ROOT/gdal-build"
GDAL_VERSION="${GDAL_VERSION:-3.8.4}"
TARBALL="gdal-${GDAL_VERSION}.tar.gz"
URL="https://github.com/OSGeo/gdal/releases/download/v${GDAL_VERSION}/${TARBALL}"

# PMTiles 書き出しに必須。GEOS が無いと MVT 生成が無効になり、PMTiles は読み取り専用になる
# pkg-config が無い環境でも動くよう、ライブラリまたはヘッダの存在で判定
GEOS_FOUND=
if pkg-config --exists geos 2>/dev/null; then
  GEOS_FOUND=1
elif ls /usr/lib/*/libgeos_c.so* /usr/lib/libgeos_c.so* 2>/dev/null | head -1 | grep -q .; then
  GEOS_FOUND=1
elif [ -d /usr/include/geos ] || [ -d /usr/local/include/geos ]; then
  GEOS_FOUND=1
fi
if [[ -z "$GEOS_FOUND" ]]; then
  echo "Error: GEOS が検出されません。PMTiles の書き出しに必要です。" >&2
  echo "  Ubuntu: sudo apt install libgeos-dev" >&2
  echo "  インストール後、このスクリプトを再実行してください。" >&2
  exit 1
fi

echo "=== GDAL フルビルド (prefix=$PREFIX) ==="
echo "オプションドライバを有効にします。Parquet は Arrow/Parquet が検出された場合のみ有効になります。"
# Python バインドは SWIG がある場合のみ有効化（ない場合は CLI のみビルド）
BUILD_PYTHON=OFF
if command -v swig &>/dev/null; then
  BUILD_PYTHON=ON
  echo "SWIG を検出しました。Python バインドを local にインストールします（python3-dev / numpy が必要）。"
else
  echo "SWIG がありません。Python バインドはスキップします（CLI のみ）。必要なら: sudo apt install swig のあと再ビルド。"
fi
echo ""

# ソース取得
if [[ ! -f "$SRC_DIR/CMakeLists.txt" ]]; then
  echo "Downloading GDAL ${GDAL_VERSION}..."
  (cd "$PROJECT_ROOT" && curl -sL -o "$TARBALL" "$URL" && tar xzf "$TARBALL" --no-same-owner && rm -rf gdal-src && mv "gdal-${GDAL_VERSION}" gdal-src && rm -f "$TARBALL")
fi

# arrow-install があれば Parquet 有効化のため CMAKE_PREFIX_PATH に追加
if [[ -d "$PROJECT_ROOT/arrow-install" ]]; then
  if [[ -n "$CMAKE_PREFIX_PATH" ]]; then
    export CMAKE_PREFIX_PATH="$PROJECT_ROOT/arrow-install:$CMAKE_PREFIX_PATH"
  else
    export CMAKE_PREFIX_PATH="$PROJECT_ROOT/arrow-install"
  fi
  echo "Arrow 検出: CMAKE_PREFIX_PATH に arrow-install を追加しました。"
  # 既存の gdal-build はキャッシュのため削除して再設定
  if [[ -d "$BUILD_DIR" ]]; then
    rm -rf "$BUILD_DIR"
    echo "gdal-build を削除して再設定します。"
  fi
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# オプションドライバを有効にしたフルビルド（Parquet は Arrow/Parquet 検出時のみ有効）
# Python バインドは SWIG がある場合のみ（local にインストールして CLI と同じ GDAL を Python から利用可能に）
CMAKE_EXTRA=()
if [[ -n "$CMAKE_PREFIX_PATH" ]]; then
  CMAKE_EXTRA+=(-DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH")
fi
CMAKE_EXTRA+=(-DBUILD_PYTHON_BINDINGS="$BUILD_PYTHON")
if [[ "$BUILD_PYTHON" == ON ]]; then
  CMAKE_EXTRA+=(-DGDAL_PYTHON_INSTALL_PREFIX="$PREFIX")
fi

cmake "$SRC_DIR" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DGDAL_BUILD_OPTIONAL_DRIVERS=ON \
  -DOGR_BUILD_OPTIONAL_DRIVERS=ON \
  -DCMAKE_BUILD_TYPE=Release \
  "${CMAKE_EXTRA[@]}"

cmake --build . -j"$(nproc)"
cmake --build . --target install

echo ""
echo "インストール先: $PREFIX"
if [[ "$BUILD_PYTHON" == ON ]]; then
  echo "Python バインド: \$PREFIX/lib/python*/site-packages (env.sh で PYTHONPATH に追加されます)"
  echo "Python 確認: source env.sh && python3 -c 'from osgeo import ogr; print(\"osgeo.ogr OK\")'"
else
  echo "Python バインド: 未ビルド（swig + python3-dev + numpy を入れて再ビルドすると有効になります）"
fi
echo "使用するときは: source $PROJECT_ROOT/env.sh"
echo "利用可能ドライバ確認: ogrinfo --formats | grep -E 'Parquet|FlatGeobuf|PMTiles'"
echo "このディレクトリ ($PROJECT_ROOT) を削除すれば GDAL もすべて消えます。"

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

echo "=== GDAL フルビルド (prefix=$PREFIX) ==="
echo "オプションドライバを有効にします。Parquet は Arrow/Parquet が検出された場合のみ有効になります。"
echo ""

# ソース取得
if [[ ! -f "$SRC_DIR/CMakeLists.txt" ]]; then
  echo "Downloading GDAL ${GDAL_VERSION}..."
  (cd "$PROJECT_ROOT" && curl -sL -o "$TARBALL" "$URL" && tar xzf "$TARBALL" && rm -rf gdal-src && mv "gdal-${GDAL_VERSION}" gdal-src && rm -f "$TARBALL")
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
CMAKE_EXTRA=()
if [[ -n "$CMAKE_PREFIX_PATH" ]]; then
  CMAKE_EXTRA+=(-DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH")
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
echo "使用するときは: source $PROJECT_ROOT/env.sh"
echo "利用可能ドライバ確認: ogrinfo --formats | grep -E 'Parquet|FlatGeobuf|PMTiles'"
echo "このディレクトリ ($PROJECT_ROOT) を削除すれば GDAL もすべて消えます。"

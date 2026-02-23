#!/usr/bin/env bash
# Apache Arrow C++（Parquet 含む）を gdal-full 直下に隔離ビルドする。
# インストール先: arrow-install。GDAL は CMAKE_PREFIX_PATH=$PROJECT_ROOT/arrow-install で再ビルドする。
# このディレクトリを削除すれば arrow-* もすべて消える。

set -e
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
ARROW_VERSION="${ARROW_VERSION:-14.0.2}"
SRC_DIR="$PROJECT_ROOT/arrow-src"
BUILD_DIR="$PROJECT_ROOT/arrow-build"
INSTALL_DIR="$PROJECT_ROOT/arrow-install"
ARCHIVE="apache-arrow-${ARROW_VERSION}.tar.gz"
# Apache archive (mirror)
URL="https://archive.apache.org/dist/arrow/arrow-${ARROW_VERSION}/${ARCHIVE}"

echo "=== Arrow C++ ビルド (prefix=$INSTALL_DIR) ==="
echo "Parquet を有効にします。"
echo ""

# 既に arrow-install に Arrow と Parquet の cmake がある場合はスキップ
if [[ -d "$INSTALL_DIR/lib/cmake/Arrow" && -d "$INSTALL_DIR/lib/cmake/Parquet" ]]; then
  echo "arrow-install に Arrow/Parquet が既にあります。スキップします。"
  echo "再ビルドする場合は rm -rf arrow-src arrow-build arrow-install のうえで再実行してください。"
  exit 0
fi

# ソース取得
if [[ ! -f "$SRC_DIR/cpp/CMakeLists.txt" ]]; then
  echo "Downloading Arrow ${ARROW_VERSION}..."
  (cd "$PROJECT_ROOT" && curl -sL -o "$ARCHIVE" "$URL" && tar xzf "$ARCHIVE" && rm -rf arrow-src && mv "apache-arrow-${ARROW_VERSION}" arrow-src && rm -f "$ARCHIVE")
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# gcc-12 があれば使用（C++20 推奨）、なければデフォルト
export CC="${CC:-gcc}"
export CXX="${CXX:-g++}"
if command -v gcc-12 >/dev/null 2>&1; then
  export CC=gcc-12 CXX=g++-12
  echo "Using gcc-12 / g++-12"
fi

# Ninja が無ければ Make を使う
GENERATOR=""
if command -v ninja >/dev/null 2>&1; then
  GENERATOR="-GNinja"
fi

cmake "$SRC_DIR/cpp" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DARROW_PARQUET=ON \
  -DARROW_WITH_SNAPPY=ON \
  -DARROW_WITH_ZLIB=ON \
  -DARROW_BUILD_STATIC=OFF \
  -DARROW_BUILD_TESTS=OFF \
  $GENERATOR

cmake --build . -j"$(nproc)"
cmake --build . --target install

echo ""
echo "インストール先: $INSTALL_DIR"
echo "GDAL を Parquet 有効でビルドするには:"
echo "  export CMAKE_PREFIX_PATH=$INSTALL_DIR"
echo "  rm -rf gdal-build"
echo "  ./build_gdal_full.sh"
echo "このディレクトリ ($PROJECT_ROOT) を削除すれば Arrow もすべて消えます。"

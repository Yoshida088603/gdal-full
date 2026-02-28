#!/usr/bin/env bash
# PostgreSQL と PostGIS を gdal-full 直下にソースビルドする。
# インストール先: pg-install。データ: pg-data（initdb で別途作成）。
# 必要な apt パッケージ: build-essential libreadline-dev zlib1g-dev libssl-dev
#   libxml2-dev libxslt-dev flex bison pkg-config
# PostGIS 用: libproj-dev libgeos-dev（推奨: libgdal-dev）
# 詳細は docs/postgresql_build.md を参照。

set -e
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
PG_VERSION="${PG_VERSION:-16.10}"
POSTGIS_VERSION="${POSTGIS_VERSION:-3.4.5}"
SRC_DIR="$PROJECT_ROOT/pg-src"
BUILD_DIR="$PROJECT_ROOT/pg-build"
INSTALL_DIR="$PROJECT_ROOT/pg-install"
PG_ARCHIVE="postgresql-${PG_VERSION}.tar.bz2"
PG_URL="https://ftp.postgresql.org/pub/source/v${PG_VERSION}/postgresql-${PG_VERSION}.tar.bz2"
POSTGIS_ARCHIVE="postgis-${POSTGIS_VERSION}.tar.gz"
POSTGIS_URL="https://download.osgeo.org/postgis/source/postgis-${POSTGIS_VERSION}.tar.gz"

echo "=== PostgreSQL + PostGIS ビルド (prefix=$INSTALL_DIR) ==="
echo ""

if [[ -f "$INSTALL_DIR/bin/postgres" ]]; then
  echo "pg-install に PostgreSQL が既にあります。スキップします。"
  echo "再ビルドする場合は rm -rf pg-src pg-build pg-install のうえで再実行してください。"
  exit 0
fi

# --- PostgreSQL ソース取得・展開 ---
if [[ ! -f "$SRC_DIR/src/bin/pg_ctl/pg_ctl.c" ]]; then
  echo "Downloading PostgreSQL ${PG_VERSION}..."
  (cd "$PROJECT_ROOT" && curl -sL -o "$PG_ARCHIVE" "$PG_URL" && tar xjf "$PG_ARCHIVE" --no-same-owner && rm -rf pg-src && mv "postgresql-${PG_VERSION}" pg-src && rm -f "$PG_ARCHIVE")
fi

# --- PostgreSQL ビルド（out-of-source） ---
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
"$SRC_DIR/configure" --prefix="$INSTALL_DIR" --without-readline
make -j"$(nproc)"
make install

# --- PostGIS ソース取得・ビルド ---
POSTGIS_SRC="$PROJECT_ROOT/postgis-src"
if [[ ! -f "$POSTGIS_SRC/configure" ]]; then
  echo "Downloading PostGIS ${POSTGIS_VERSION}..."
  (cd "$PROJECT_ROOT" && curl -sL -o "$POSTGIS_ARCHIVE" "$POSTGIS_URL" && tar xzf "$POSTGIS_ARCHIVE" --no-same-owner && rm -rf postgis-src && mv "postgis-${POSTGIS_VERSION}" postgis-src && rm -f "$POSTGIS_ARCHIVE")
fi
cd "$POSTGIS_SRC"
./configure PG_CONFIG="$INSTALL_DIR/bin/pg_config" --without-protobuf
make -j"$(nproc)"
make install

echo ""
if [[ -f "$INSTALL_DIR/bin/initdb" ]]; then
  echo "インストール完了: $INSTALL_DIR"
  echo "初回は scripts/pg_start.sh で initdb と起動が行われます。"
  echo "このディレクトリ ($PROJECT_ROOT) を削除すれば PostgreSQL/PostGIS もすべて消えます。"
else
  echo "警告: initdb が見つかりません。"
  exit 1
fi

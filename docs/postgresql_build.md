# PostgreSQL を gdal-full 内に閉じ込めるビルド

PostgreSQL と PostGIS をソースからビルドし、インストール先（`pg-install`）とデータディレクトリ（`pg-data`）を **gdal-full 直下** に置きます。このディレクトリを削除すれば PostgreSQL 一式も消えます。システムに PostgreSQL を入れずにダンプのリストアと `run_pipeline_pg.sh` を実行できます。

## 前提

- **環境**: WSL2 上の Ubuntu 22.04（[README](../README.md) と同様）。
- **ビルド依存**: 以下の apt パッケージを事前にインストールする。

  ```bash
  sudo apt-get update
  sudo apt-get install -y build-essential libreadline-dev zlib1g-dev libssl-dev \
    libxml2-dev libxslt-dev flex bison pkg-config
  ```

- **PostGIS 用**（拡張ビルドに必要）:

  ```bash
  sudo apt-get install -y libproj-dev libgeos-dev
  ```

  ラスター機能などを使う場合は `libgdal-dev` も入れるとよい（省略可）。

## ビルド手順

1. **PostgreSQL + PostGIS のビルド**

   ```bash
   cd /path/to/gdal-full
   chmod +x build_postgresql.sh
   ./build_postgresql.sh
   ```

   - PostgreSQL の tarball を取得して `pg-src` に展開し、`pg-build` で out-of-source ビルド。インストール先は `pg-install`。
   - 続けて PostGIS を取得・ビルドし、同じ `pg-install` に拡張としてインストール。
   - 既に `pg-install/bin/postgres` がある場合は「既にビルド済み」と表示してスキップする。再ビルドする場合は `rm -rf pg-src pg-build pg-install postgis-src` のうえで再実行。

2. **初回のみ: データベースの初期化と起動**

   初回は `scripts/pg_start.sh` を実行するだけでよい。`pg-data` が無い場合は **initdb** を実行してから **pg_ctl start** する。

   ```bash
   ./scripts/pg_start.sh
   ```

3. **停止**

   ```bash
   ./scripts/pg_stop.sh
   ```

## ディレクトリ構成（gdal-full 直下）

| パス         | 役割                                   |
|--------------|----------------------------------------|
| `pg-src/`    | PostgreSQL ソース（tarball 展開）      |
| `pg-build/`  | PostgreSQL ビルド用（out-of-source）   |
| `pg-install/`| インストール先（bin, lib, share）      |
| `pg-data/`   | データディレクトリ（initdb で作成）    |
| `postgis-src/` | PostGIS ソース（ビルド後も残る）     |

## ポート競合

デフォルトでは **5432** で待ち受ける。システムの PostgreSQL などと衝突する場合は、`pg-data` 作成後に `pg-data/postgresql.conf` を編集してポートを変更する。

```bash
# 例: 5433 にする
echo "port = 5433" >> pg-data/postgresql.conf
```

その場合は接続文字列でも `port=5433` を指定する（[pipeline_pg.md](pipeline_pg.md) 参照）。

## リストアとパイプライン

- **リストア**: `scripts/restore_pg_dump.sh` でダンプをリストアする。`pg-install` がある場合はその `psql` / `createdb` / `pg_restore` が優先される。
- **パイプライン**: リストア後、`PG_CONNECTION` を設定して `scripts/run_pipeline_pg.sh` を実行する。

手順の詳細は [pipeline_pg.md](pipeline_pg.md) の「PostgreSQL を gdal-full 内に閉じ込めて使う場合」を参照。

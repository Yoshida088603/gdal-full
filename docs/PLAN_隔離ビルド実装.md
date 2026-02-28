# gdal-full 隔離ビルド実装計画

README で想定されている GDAL と関連機能を**すべて**隔離ビルドで実装するための手順です。  
**方針: すべてのビルド成果物は `gdal-full` 直下のみに置き、システム（/usr 等）には一切インストールしない。**

---

## 隔離の保証

- 各ビルドスクリプトは `PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"` で自身のディレクトリを取得し、インストール先を `$PROJECT_ROOT/local` / `$PROJECT_ROOT/arrow-install` / `$PROJECT_ROOT/pg-install` に限定している。
- `sudo` や `make install` でシステムディレクトリへ書き込む処理は**ない**。
- **このディレクトリ（gdal-full）を削除すれば、ビルド成果物もすべて消える。**

---

## ディレクトリ構成（ビルド後）

```
gdal-full/
├── local/              # GDAL インストール先（bin, lib, share）
├── gdal-src/           # GDAL ソース
├── gdal-build/         # GDAL ビルド用
├── arrow-src/          # Arrow C++ ソース（Parquet 有効時）
├── arrow-build/        # Arrow ビルド用
├── arrow-install/      # Arrow/Parquet インストール先（Parquet 有効時）
├── pg-src/             # PostgreSQL ソース（PG 使う場合）
├── pg-build/           # PostgreSQL ビルド用
├── pg-install/         # PostgreSQL+PostGIS インストール先
├── pg-data/            # DB データ（initdb で作成、PG 使う場合）
├── postgis-src/        # PostGIS ソース
├── env.sh              # 利用時: source env.sh
├── build_arrow.sh      # 1. Arrow/Parquet ビルド
├── build_gdal_full.sh  # 2. GDAL ビルド
├── build_postgresql.sh # 3. （任意）PostgreSQL+PostGIS ビルド
├── scripts/
│   ├── run_pipeline.sh    # SHP → Parquet → FGB/PMTiles
│   ├── run_pipeline_pg.sh # PG → Parquet → FGB/PMTiles
│   ├── pg_start.sh        # PG 起動
│   └── pg_stop.sh         # PG 停止
├── input_data/         # パイプライン入力（*.shp）※ 無くても GDAL は利用可
└── output_data/        # パイプライン出力（既存の .pmtiles 等）
```

---

## 実施済み（スクリプト側の修正）

- **tar のオーナーエラー対策**: WSL 等で展開時に `Cannot change ownership` が出るため、`build_arrow.sh`・`build_gdal_full.sh`・`build_postgresql.sh` の全 `tar` に `--no-same-owner` を追加済み。
- **Arrow ソース**: `./build_arrow.sh` 初回で Arrow を取得し、`arrow-src/` への展開まで成功している。続きの cmake ビルドには **cmake のインストール** が必要。

---

## 前提（システムに入れるもの）

いずれも**パッケージのインストールのみ**で、gdal-full の外にはインストール先を広げない。

| 用途 | パッケージ |
|------|------------|
| 共通 | `build-essential` `cmake` `curl` `git` |
| Arrow（推奨） | `gcc-12` `g++-12`（未導入ならシステム gcc でビルド可） |
| PostgreSQL 用 | `libreadline-dev` `zlib1g-dev` `libssl-dev` `libxml2-dev` `libxslt-dev` `flex` `bison` `pkg-config` |
| PostGIS 用 | `libproj-dev` `libgeos-dev` |

例（Ubuntu 22.04）:

```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake curl git
sudo apt-get install -y gcc-12 g++-12   # Arrow 推奨
# PostgreSQL/PostGIS までやる場合のみ:
sudo apt-get install -y libreadline-dev zlib1g-dev libssl-dev libxml2-dev libxslt-dev flex bison pkg-config libproj-dev libgeos-dev
```

---

## 実装手順（3 段階）

### フェーズ 1: Arrow/Parquet の隔離ビルド（Parquet ドライバ用）

1. **実行**
   ```bash
   cd /home/ubuntu/work/cursor/maplibre/MapLibre-HandsOn-Beginner/05_ポリゴン表示/gdal-full
   chmod +x build_arrow.sh
   ./build_arrow.sh
   ```
2. **確認**
   - `arrow-install/lib/cmake/Arrow` と `arrow-install/lib/cmake/Parquet` が存在することを確認。
3. **失敗時**
   - Arrow のビルドエラー: C++17 以上対応のコンパイラ（gcc-12 等）を入れて再実行。
   - 再ビルド: `rm -rf arrow-src arrow-build arrow-install` のうえで `./build_arrow.sh`。

---

### フェーズ 2: GDAL の隔離ビルド（FlatGeobuf / PMTiles / Parquet）

1. **実行**
   ```bash
   chmod +x build_gdal_full.sh
   ./build_gdal_full.sh
   ```
   - `build_gdal_full.sh` は `arrow-install` が存在すれば自動で `CMAKE_PREFIX_PATH` に追加し、Parquet 有効で GDAL をビルドする。
   - インストール先: `local/`（bin, lib, share）。
2. **確認**
   ```bash
   source env.sh
   ogr2ogr --version
   ogrinfo --formats | grep -E "Parquet|FlatGeobuf|PMTiles"
   ```
   - 上記 3 つが表示されれば OK。
3. **PMTiles のレイヤ名確認（本計画の目的の一つ）**
   ```bash
   source env.sh
   ogrinfo -al -so output_data/庭園路ポリゴン.pmtiles
   ```
   - 表示されたレイヤ名を 05_ポリゴン表示の `main.js` の `source-layer` に指定すれば、青いポリゴンが表示される。

---

### フェーズ 3:（任意）PostgreSQL + PostGIS の隔離ビルド

`run_pipeline_pg.sh` で PostgreSQL ダンプから Parquet/FGB/PMTiles を出す場合のみ実施。

1. **実行**
   ```bash
   chmod +x build_postgresql.sh
   ./build_postgresql.sh
   ```
   - インストール先: `pg-install/`。データ: `pg-data/`（初回は `scripts/pg_start.sh` で initdb）。
2. **初回起動**
   ```bash
   ./scripts/pg_start.sh
   ```
3. **停止**
   ```bash
   ./scripts/pg_stop.sh
   ```
4. **詳細**
   - [docs/postgresql_build.md](postgresql_build.md) を参照。

---

## 隔離の最終確認

- 次のコマンドで、gdal-full 外に GDAL/Arrow のインストール先がないことを確認する（`source env.sh` を**しない**状態で実行）:
  ```bash
  which ogr2ogr   # 未設定なら何も出ないか、システムの別 GDAL
  echo $LD_LIBRARY_PATH  # 空または gdal-full を含まない
  ```
- `source env.sh` した**後**は、`which ogr2ogr` が `.../gdal-full/local/bin/ogr2ogr` を指し、`LD_LIBRARY_PATH` に `.../gdal-full/local/lib` および（存在すれば）`.../gdal-full/arrow-install/lib` が含まれること。

---

## パイプライン（ビルド後の利用）

- **SHP がある場合**: `input_data/*.shp` を置き、`./scripts/run_pipeline.sh` で `output_data/` に parquet / fgb / pmtiles を再生成できる。
- **PostgreSQL から変換する場合**: ダンプをリストアしたうえで `./scripts/run_pipeline_pg.sh` を使用。手順は [docs/pipeline_pg.md](pipeline_pg.md)。

---

## まとめ

| フェーズ | スクリプト | 成果物の場所 | 必須 |
|----------|------------|--------------|------|
| 1 | build_arrow.sh | arrow-src, arrow-build, **arrow-install** | Parquet を使う場合 |
| 2 | build_gdal_full.sh | gdal-src, gdal-build, **local** | 必須（PMTiles 確認用） |
| 3 | build_postgresql.sh | pg-src, pg-build, pg-install, postgis-src, **pg-data** | run_pipeline_pg のみ |

**最小で PMTiles の中身（レイヤ名）を確認するだけなら: フェーズ 1 + フェーズ 2 を実行し、`source env.sh` のあと `ogrinfo -al -so output_data/庭園路ポリゴン.pmtiles` を実行する。**

# パイプライン（PostgreSQL → GeoParquet → FGB / PMTiles）

PostgreSQL/PostGIS にリストアしたデータベースを入力とし、既存の [run_pipeline.sh](../scripts/run_pipeline.sh) と同様に **GeoParquet を中継** して FGB と PMTiles を出力する手順です。入力は **ダンプをリストアした PostgreSQL** であり、接続文字列で指定します。**Tile（PMTiles）のみが必要な場合も同一手順**で、出力の `output_data/*.pmtiles` を利用すればよい。

## PostgreSQL を gdal-full 内に閉じ込めて使う場合

システムに PostgreSQL を入れず、gdal-full 直下だけに PostgreSQL + PostGIS を置いて使う手順です。ビルド・初期化・起動の詳細は [postgresql_build.md](postgresql_build.md) を参照。

1. **ビルド**: `./build_postgresql.sh` を実行（初回のみ）。
2. **起動**: `./scripts/pg_start.sh` を実行。`pg-data` が無い場合は initdb が実行されたうえでサーバーが起動する。
3. **リストア**: `./scripts/restore_pg_dump.sh <ダンプファイル> <DB名>` でダンプをリストア。`pg-install` があるときはその `psql` / `createdb` / `pg_restore` が自動で使われる。
4. **パイプライン**: `PG_CONNECTION` を設定して `./scripts/run_pipeline_pg.sh` を実行。

ポートを 5433 などに変更している場合は、接続文字列で `port=5433` を指定する。

---

以下は「システムの PostgreSQL を使う場合」および「閉じ込め運用」の両方に共通する内容です。

## PostgreSQL ドライバの確認・有効化

- **確認**: `source env.sh` のうえで次を実行し、**PostgreSQL** が表示されることを確認する。
  ```bash
  ogrinfo --formats | grep -i postgres
  ```
  例: `PostgreSQL -vector- (rw+): PostgreSQL/PostGIS`
- **無い場合**: GDAL の PostgreSQL ドライバは **libpq** に依存する。WSL 上で次を実行し、`gdal-build` を削除してから GDAL を再ビルドする。
  ```bash
  sudo apt-get install -y libpq-dev
  rm -rf gdal-build
  ./build_gdal_full.sh
  ```
  CMake が libpq を検出すれば PostgreSQL ドライバが有効になる。

## ダンプのリストア手順（手動）

パイプラインを実行する前に、PostgreSQL/PostGIS のダンプをデータベースにリストアする。

1. **空のデータベースを作成**
   ```bash
  createdb gis_export
  ```

2. **PostGIS 拡張を有効化**
   ```bash
  psql -d gis_export -c "CREATE EXTENSION postgis;"
  ```

3. **ダンプの種類に応じてリストア**
   - **カスタム形式（.backup）**: `pg_dump -Fc` で作成した形式
     ```bash
     pg_restore -d gis_export /path/to/dump.backup
     ```
   - **プレーン SQL（.sql）**: `pg_dump` で作成した SQL ファイル
     ```bash
     psql -d gis_export -f /path/to/dump.sql
     ```

リストア後、接続できることと PostGIS のジオメトリテーブルが存在することを確認してから、次節のパイプラインを実行する。

### gaiku 系ダンプ（プレーン SQL .dmp）の例

[gaiku_full20250220.dmp](../input_data/gaiku_full20250220/gaiku_full20250220.dmp) のようなプレーン SQL ダンプ（約 485 MiB）の場合の手順例。ダンプのスキーマ・ジオメトリテーブル一覧は [gaiku_dump_parse_summary.md](gaiku_dump_parse_summary.md) を参照。

1. `createdb gaiku_export`（任意の DB 名でよい）
2. `psql -d gaiku_export -c "CREATE EXTENSION postgis;"`
3. `psql -d gaiku_export -f input_data/gaiku_full20250220/gaiku_full20250220.dmp`（所要時間は環境依存）
4. **点ジオメトリ VIEW の作成（任意）**: x/y のみで geometry 列がないテーブルから PMTiles を出す場合は、[create_point_views.sh](../scripts/create_point_views.sh) で点 geom を持つ VIEW（`*_pt`）を作成する。接続は `PGHOST=localhost` 等を必要に応じて設定。
   ```bash
   ./scripts/create_point_views.sh gaiku_export
   ```
   これにより `kanri.hojyoten_pt`, `kanri.sankakuten_pt`, `kanri.takakuten_pt`, `tosikanmin.sankakuten_pt`, `tosikanmin.takakuten_pt` が作成され、x/y および `zahyokei_cd` は属性としてそのまま保持される。`zahyokei_cd`（座標系コード 1〜19）は平面直角 1 系〜19 系に対応し、SRID は 6669（1 系）〜6687（19 系）で付与される。
5. `cd projects/gdal-full && source env.sh`
6. `export PG_CONNECTION='PG:dbname=gaiku_export host=localhost port=5432 user=ubuntu schemas=kanri,tosikanmin'`（ユーザ名は環境に合わせる。点 VIEW を使う場合は `schemas=kanri,tosikanmin` を付与）
7. `./scripts/run_pipeline_pg.sh`

出力は `output_data/` に `<スキーマ>_<テーブル>.parquet` / `.fgb` / `.pmtiles` が生成される。点 VIEW を使った場合は `kanri_hojyoten_pt.pmtiles` などが出力される。

**リストア用スクリプト（任意）**: [restore_pg_dump.sh](../scripts/restore_pg_dump.sh) で、ダンプファイルパスと DB 名を指定してリストアまで自動化できる。プレーン SQL（.sql / .dmp）は `psql -f`、カスタム形式（.backup）は `pg_restore` で実行する。例: `./scripts/restore_pg_dump.sh input_data/gaiku_full20250220/gaiku_full20250220.dmp gaiku_export`

**点 VIEW と CRS**: 1 レイヤ内で平面直角の系が混在する場合、GDAL/PMTiles が先頭行の SRID で全体を解釈する可能性がある。地理座標に統一したい場合は、パイプライン実行後に `ogr2ogr -t_srs EPSG:6668` で再変換するか、run_pipeline_pg.sh の ogr2ogr に `-t_srs EPSG:6668` を付与する運用を検討する。

**検証**: リストア後は `ogrinfo -so PG:dbname=<DB> host=localhost ... schemas=kanri,tosikanmin` でレイヤが列挙されることを確認する。点 VIEW 作成後は `*_pt` レイヤも表示される。`run_pipeline_pg.sh` 実行後は `output_data/` に `<スキーマ>_<テーブル>.parquet` / `.fgb` / `.pmtiles` が出力されるので、`ogrinfo -al -so output_data/kanri_hojyoten_pt.parquet` 等でフィーチャ数・CRS を確認する。

## run_pipeline_pg.sh の使い方

**前提**: 上記のとおりダンプをリストアした PostgreSQL が起動していること。接続情報は **環境変数または引数** で渡す（スクリプト内にデフォルトの接続文字列は書かない）。

### 接続文字列

- **環境変数**: `PG_CONNECTION` に GDAL の PG 接続文字列を設定する。
  ```bash
  export PG_CONNECTION='PG:"dbname=gis_export host=localhost port=5432 user=postgres"'
  ```
  パスワードが必要な場合は `PGPASSWORD` を別途設定する（スクリプト内には書かない）。
  ```bash
  export PGPASSWORD=yourpassword
  ```
- **引数**: 第 1 引数で接続文字列を渡すこともできる。`PG_CONNECTION` が未設定のときに使用される。

### 実行例

```bash
cd /path/to/gdal-full
export PG_CONNECTION='PG:"dbname=gis_export host=localhost port=5432 user=postgres"'
./scripts/run_pipeline_pg.sh
```

または

```bash
./scripts/run_pipeline_pg.sh 'PG:"dbname=gis_export host=localhost port=5432 user=postgres"'
```

### 対象レイヤ

- **デフォルト**: 接続先データベースにある **PostGIS ジオメトリカラムを持つテーブル（レイヤ）** を `ogrinfo -so` で自動列挙し、すべて対象とする。
- **レイヤ名とファイル名**: レイヤ名が `schemaname.tablename` の形式の場合、ファイル名では `.` を `_` に置換する（例: `public.roads` → `public_roads.parquet`）。

### 出力先

- 既定では `output_data/`。既存の SHP パイプラインと同じディレクトリである。環境変数 `OUTPUT_DIR` で上書き可能。
  ```bash
  OUTPUT_DIR=/path/to/out ./scripts/run_pipeline_pg.sh
  ```

## 既知の注意（ジオメトリ型・CRS・大容量）

- **ジオメトリ型**: PostGIS は Polygon / MultiPolygon の混在や NULL ジオメトリを許容する。本パイプラインでは SHP と同様に、FGB 出力時に **`-nlt PROMOTE_TO_MULTI`** と **`-lco SPATIAL_INDEX=NO`** を付与して 0 件問題を避けている。
- **CRS**: テーブルごとに SRID が異なる場合がある。必要に応じて `-t_srs EPSG:6674` などで出力 CRS を統一する（現行スクリプトでは未指定）。SRID が 900913（Web Mercator）のダンプで日本平面座標系（EPSG:6674 等）に揃えたい場合は、手動で `ogr2ogr -t_srs EPSG:6674 ...` を付けて再変換するか、スクリプトのオプション拡張を検討する。
- **大容量・タイムアウト**: レイヤが非常に大きい場合、メモリや接続タイムアウトで失敗することがある。その場合は対象テーブルを限定するか、WHERE 条件で範囲を絞る検討が必要（現行スクリプトでは全件取得。将来的にオプションで絞り込みを追加可能）。

## 参照

- [GDAL PostgreSQL/PostGIS ドライバ](https://gdal.org/drivers/vector/pg.html)
- [pipeline.md](pipeline.md) — SHP パイプラインの流れと FGB のオプション

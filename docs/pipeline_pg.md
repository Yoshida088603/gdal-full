# パイプライン（PostgreSQL → GeoParquet → FGB / PMTiles）

PostgreSQL/PostGIS にリストアしたデータベースを入力とし、既存の [run_pipeline.sh](../scripts/run_pipeline.sh) と同様に **GeoParquet を中継** して FGB と PMTiles を出力する手順です。入力は **ダンプをリストアした PostgreSQL** であり、接続文字列で指定します。

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
- **CRS**: テーブルごとに SRID が異なる場合がある。必要に応じて `-t_srs EPSG:6674` などで出力 CRS を統一する（現行スクリプトでは未指定。必要なら run_pipeline_pg.sh の呼び出しオプションやドキュメントで案内する）。
- **大容量・タイムアウト**: レイヤが非常に大きい場合、メモリや接続タイムアウトで失敗することがある。その場合は対象テーブルを限定するか、WHERE 条件で範囲を絞る検討が必要（現行スクリプトでは全件取得。将来的にオプションで絞り込みを追加可能）。

## 参照

- [GDAL PostgreSQL/PostGIS ドライバ](https://gdal.org/drivers/vector/pg.html)
- [pipeline.md](pipeline.md) — SHP パイプラインの流れと FGB のオプション

# gdal-full — フル機能 GDAL の隔離ビルド

Parquet / FlatGeobuf / PMTiles など、オプションドライバを含めた **GDAL のフラッグシップ機能** を利用するためのビルド用ディレクトリです。

## 動作環境

- **WSL2** 上の **Ubuntu 22.04** でビルド・動作確認済み。
- 第三者が別環境で再現する場合は、CMake やパッケージの差異に注意。
- 本プロジェクトでは Docker や Conda に依存しない構成にしている。大きな組織でこれらを使わない理由（有償契約・社内制約など）は、**projects 直下の [structure.md](../structure.md)** の「Docker / Conda を使わないことがある理由」を参照。

## 方針

- **convert_geoparquet** 側の最小構成（`build_gdal.sh`・`local/`・`test/`）は **そのまま** 残す。
- **ここ（projects/gdal-full）** で新たに GDAL をビルド・テストする。
- **フルビルドとテストが完了したら**、convert_geoparquet の従来構成は閉じ、以降は **gdal-full の GDAL を利用する**。

## 使い方

**前提**: PMTiles の書き出しを含めフル機能でビルドするには **GEOS** が必要です。Ubuntu では `sudo apt install libgeos-dev` を先に実行してください。未導入だと `build_gdal_full.sh` はエラーで終了します。

**Parquet を使う場合**は、先に [build_arrow.sh](build_arrow.sh) で Arrow/Parquet をビルドしてから GDAL をビルドする（[docs/parquet_build.md](docs/parquet_build.md) 参照）。

```bash
cd /home/ubuntu/projects/gdal-full
sudo apt install libgeos-dev   # PMTiles 書き出しに必須
chmod +x build_arrow.sh build_gdal_full.sh
./build_arrow.sh   # Parquet を使う場合のみ
./build_gdal_full.sh
source env.sh
ogr2ogr --version
ogrinfo --formats | grep -E "Parquet|FlatGeobuf|PMTiles"
# Python バインド確認（ビルド時に BUILD_PYTHON_BINDINGS=ON の場合）
python3 -c 'from osgeo import ogr; print("osgeo.ogr OK")'
```

## 依存（Parquet を使う場合）

- **Apache Arrow C++** と **Apache Parquet C++** がシステムまたは `CMAKE_PREFIX_PATH` で見える必要がある。
- 未導入の場合はビルドは完了するが Parquet ドライバは無効になる。**有効化手順**は [docs/parquet_build.md](docs/parquet_build.md) を参照（Arrow をソースからビルドして `arrow-install` に置き、続けて GDAL を再ビルドする）。

## 依存（Python バインドを使う場合）

- **SWIG** と **Python 3**（ランタイム）・**python3-dev**（ヘッダ）・**numpy** がビルド時に揃っている場合のみ、Python バインドが `local/lib/python*/site-packages` にインストールされます。**SWIG が無い場合は Python バインドはスキップされ、CLI のみビルドされます**（既存のビルド済み環境を壊しません）。
- Python バインドを有効にするには、事前に例: `sudo apt install swig python3-dev` と `pip3 install numpy` を実行してから `./build_gdal_full.sh` を再実行してください（必要なら `rm -rf gdal-build` のあと実行）。
- `source env.sh` すると `PYTHONPATH` に上記 site-packages が追加され、`python3` で `from osgeo import ogr` が利用可能になります。
- 確認: `source env.sh && python3 -c 'from osgeo import ogr; print("osgeo.ogr OK")'`

## パイプライン（SHP → GeoParquet → FGB / PMTiles）

`scripts/run_pipeline.sh` で、`input_data/` 内の各 Shapefile を GeoParquet に変換し、続けて FGB と PMTiles を出力する。

**前提**

- `source env.sh` で gdal-full の GDAL を有効にした状態で実行する（スクリプト内で自動で source する）。
- **Parquet ドライバ**が必要。Arrow/Parquet が未導入の場合はビルド時に Parquet が無効になり、スクリプトは「Parquet is not available」で終了する。有効化は [docs/parquet_build.md](docs/parquet_build.md) を参照。

**実行**

```bash
cd /home/ubuntu/projects/gdal-full
./scripts/run_pipeline.sh
```

- **入力**: `input_data/*.shp`（4 レイヤ: トンネル・庭園路・真幅道路・高速道路ポリゴン）
- **出力**: `output_data/<ベース名>.parquet` / `.fgb` / `.pmtiles`
- **信頼してよい出力**: Parquet・FGB・PMTiles はいずれも全レイヤで入力と件数一致（FGB は Polygon/MultiPolygon 混在・NULL ジオメトリ対策済み）。詳細は [docs/pipeline.md](docs/pipeline.md) を参照。
- **GeoPackage から PMTiles を直接出力**: この README どおりにビルドすれば、`ogr2ogr -f PMTiles out.pmtiles in.gpkg` で GeoPackage から PMTiles を直接書き出せます。`scripts/gpkg_to_pmtiles.sh` も利用可能です。
- **PMTiles 書き出しができるか確認**: `source env.sh && ./scripts/check_pmtiles_write.sh` を実行すると、このビルドで PMTiles の書き出しが有効かどうかだけを判定します。「結果: 可」なら `gpkg_to_pmtiles.sh` で直接 .pmtiles が作成されます。「結果: 不可」の場合は、**まず同じバージョン（3.8.4）のまままっさら再ビルド**を試してください。`rm -rf gdal-build gdal-src` のあと `./build_gdal_full.sh` を実行し、再度 `check_pmtiles_write.sh` で確認。それでも不可なら `GDAL_VERSION=3.9.0` を付けて再ビルドするか、[公式ドキュメント](https://gdal.org/drivers/vector/pmtiles.html)を参照してください。

**PMTiles 書き出しに必要な依存**: PMTiles の書き込みは内部で MVT を生成するため、**GEOS** がビルド時に必要です。CMake で `Could NOT find GEOS` のままでは書き出しが無効になります。Ubuntu では `sudo apt install libgeos-dev` を実行してから `rm -rf gdal-build gdal-src` のうえ `./build_gdal_full.sh` をやり直してください。

**過去にできていたのに今「不可」になる場合**: 同じ gdal-full 手順で以前は PMTiles が出せていたなら、**当時の環境では GEOS が検出されていた**可能性があります。上記のとおり `libgeos-dev` を入れてまっさら再ビルドし、`check_pmtiles_write.sh` で確認してください。

**PostgreSQL から変換する場合**: ダンプ（.sql / .backup）を PostgreSQL にリストアしたうえで、`scripts/run_pipeline_pg.sh` を使う。接続文字列（`PG_CONNECTION` または第1引数）の指定と手順は [docs/pipeline_pg.md](docs/pipeline_pg.md) を参照。PostgreSQL をシステムに入れず使う場合は [build_postgresql.sh](build_postgresql.sh) と [docs/postgresql_build.md](docs/postgresql_build.md) を参照。

## ディレクトリ構成（ビルド後）

- `local/` — GDAL インストール先（bin, lib, share）。Python バインド有効時は `local/lib/python*/site-packages` に osgeo が入る。
- `gdal-src/` — GDAL ソース
- `gdal-build/` — GDAL ビルド用
- `arrow-src/` — Arrow C++ ソース（Parquet 有効時）
- `arrow-build/` — Arrow ビルド用
- `arrow-install/` — Arrow/Parquet インストール先（Parquet 有効時。`env.sh` が実行時に LD_LIBRARY_PATH に追加）
- `build_arrow.sh` — Arrow ビルド用スクリプト（Parquet 有効化時に実行）
- `scripts/` — パイプラインスクリプト（`run_pipeline.sh`, `run_pipeline_pg.sh`）
- `input_data/` — 入力 Shapefile
- `output_data/` — 変換結果（parquet / fgb / pmtiles）
- このディレクトリを削除すれば上記も含めてすべて消える（システムには入れない）。

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

**Parquet を使う場合**は、先に [build_arrow.sh](build_arrow.sh) で Arrow/Parquet をビルドしてから GDAL をビルドする（[docs/parquet_build.md](docs/parquet_build.md) 参照）。

```bash
cd /home/ubuntu/projects/gdal-full
chmod +x build_arrow.sh build_gdal_full.sh
./build_arrow.sh   # Parquet を使う場合のみ
./build_gdal_full.sh
source env.sh
ogr2ogr --version
ogrinfo --formats | grep -E "Parquet|FlatGeobuf|PMTiles"
```

## 依存（Parquet を使う場合）

- **Apache Arrow C++** と **Apache Parquet C++** がシステムまたは `CMAKE_PREFIX_PATH` で見える必要がある。
- 未導入の場合はビルドは完了するが Parquet ドライバは無効になる。**有効化手順**は [docs/parquet_build.md](docs/parquet_build.md) を参照（Arrow をソースからビルドして `arrow-install` に置き、続けて GDAL を再ビルドする）。

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

## ディレクトリ構成（ビルド後）

- `local/` — GDAL インストール先（bin, lib, share）
- `gdal-src/` — GDAL ソース
- `gdal-build/` — GDAL ビルド用
- `arrow-src/` — Arrow C++ ソース（Parquet 有効時）
- `arrow-build/` — Arrow ビルド用
- `arrow-install/` — Arrow/Parquet インストール先（Parquet 有効時。`env.sh` が実行時に LD_LIBRARY_PATH に追加）
- `build_arrow.sh` — Arrow ビルド用スクリプト（Parquet 有効化時に実行）
- `scripts/` — パイプラインスクリプト（`run_pipeline.sh`）
- `input_data/` — 入力 Shapefile
- `output_data/` — 変換結果（parquet / fgb / pmtiles）
- このディレクトリを削除すれば上記も含めてすべて消える（システムには入れない）。

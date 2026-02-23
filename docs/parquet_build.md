# Parquet ドライバ有効化手順

GDAL で GeoParquet を読み書きするには、ビルド時に **Apache Arrow C++** と **Apache Parquet C++** が検出されている必要がある。ここでは Arrow/Parquet を**ソースからビルド**し、gdal-full 直下の `arrow-install` に置いてから GDAL を再ビルドする手順をまとめる。Conda / Docker は使わない。

## 前提

- **環境**: WSL2 上 Ubuntu 22.04（[structure.md](../structure.md) のとおり）。
- **必要なもの**: `build-essential`、`cmake`、`git`、`curl`。Ninja が無ければ Make が使われる。  
- **オプション**: gcc-12 を入れると Arrow の C++20 ビルドに有利。`sudo apt-get install -y gcc-12 g++-12`。未導入の場合はシステムの gcc でビルド（Arrow 14.x は C++17 でビルド可能）。

## 手順

### 1. Arrow C++ のビルドとインストール

```bash
cd /home/ubuntu/projects/gdal-full
chmod +x build_arrow.sh
./build_arrow.sh
```

- 初回は Apache Arrow のソース（既定: 14.0.2）をダウンロードし、`arrow-src/`・`arrow-build/` に展開・ビルドする。
- インストール先は `arrow-install/`。`arrow-install/lib/cmake/Arrow` と `arrow-install/lib/cmake/Parquet` ができていれば成功。
- 既に `arrow-install` に Arrow/Parquet がある場合はスキップする。再ビルドする場合は `rm -rf arrow-src arrow-build arrow-install` のうえで再実行。

### 2. GDAL の再ビルド

`build_gdal_full.sh` は、`arrow-install` が存在するときに **CMAKE_PREFIX_PATH** に自動で追加し、既存の `gdal-build` を削除してから再設定する。

```bash
cd /home/ubuntu/projects/gdal-full
./build_gdal_full.sh
```

- ビルド後、`source env.sh` して `ogrinfo --formats | grep Parquet` で **Parquet** が表示されることを確認する。
- `env.sh` は `arrow-install/lib` を **LD_LIBRARY_PATH** に追加するので、実行時に libparquet 等が読み込まれる。

### 3. パイプラインの実行

```bash
cd /home/ubuntu/projects/gdal-full
./scripts/run_pipeline.sh
```

- 入力: `input_data/*.shp`
- 出力: `output_data/<ベース名>.parquet` / `.fgb` / `.pmtiles`
- 一部レイヤで「Mismatched geometry type」という警告が出ることがある。**Parquet 出力**は全レイヤで入力と件数一致しており信頼してよい。**FGB** は `-nlt PROMOTE_TO_MULTI` と `-lco SPATIAL_INDEX=NO` により全レイヤで件数一致する（[docs/pipeline.md](pipeline.md) の「出力の正しさについて」参照）。

## 参照

- Arrow C++ ビルド: [Building Arrow C++](https://arrow.apache.org/docs/developers/cpp/building.html)
- GDAL Parquet ドライバ: [GDAL (Geo)Parquet](https://gdal.org/drivers/vector/parquet.html)

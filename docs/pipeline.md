# パイプライン（SHP → GeoParquet → FGB / PMTiles）

`scripts/run_pipeline.sh` が実行する変換のメモ。

## 流れ

1. **SHP → GeoParquet**: `ogr2ogr -f Parquet -lco GEOMETRY_ENCODING=WKB output_data/<ベース名>.parquet input_data/<ベース名>.shp`
2. **GeoParquet → FGB**: `ogr2ogr -f FlatGeobuf output_data/<ベース名>.fgb output_data/<ベース名>.parquet`
3. **GeoParquet → PMTiles**: `ogr2ogr -dsco MINZOOM=0 -dsco MAXZOOM=15 -f "PMTiles" output_data/<ベース名>.pmtiles output_data/<ベース名>.parquet`

## 注意

- **Parquet ドライバ**が必須。Arrow/Parquet C++ が未導入だと GDAL に Parquet が含まれず、スクリプトは最初のドライバ確認で終了する。有効化は README および `convert_geoparquet/docs/gdal_geoparquet_survey.md` 参照。
- 入力 CRS は .prj から読み取られる（EPSG:6674）。`-t_srs` は不要。
- 真幅道路ポリゴンは約 8 万フィーチャで最大。メモリ・実行時間はこのレイヤで確認すること。

## 検証（Parquet 有効時）

```bash
source env.sh
ogrinfo -al -so output_data/トンネルポリゴン.parquet
```

CRS に EPSG:6674 が含まれること、フィーチャ数が入力と一致することを確認する。

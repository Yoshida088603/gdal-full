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

## 出力の正しさについて

- **入力と出力のフィーチャ数**を比較すれば、スキップの有無が分かる。件数が一致していれば、少なくとも全件写っている。
- **信頼してよい出力**: 現状のパイプラインでは **GeoParquet と PMTiles** は全レイヤで入力件数と一致する。**Parquet / PMTiles を正とする**運用を推奨する。
- **FGB の既知の制限**: GeoParquet → FGB の変換で、**庭園路・真幅道路・高速道路ポリゴン**の 3 レイヤは、ジオメトリ型の扱いの関係で **0 件の FGB が出力される**ことがある。トンネルポリゴンは問題なく変換される。FGB が必要な場合は Parquet から別ツールで変換するか、レイヤごとの確認を推奨する。

## 検証（Parquet 有効時）

```bash
source env.sh
ogrinfo -al -so output_data/トンネルポリゴン.parquet
```

CRS に EPSG:6674 が含まれること、フィーチャ数が入力と一致することを確認する。全レイヤの件数比較例:

```bash
for name in トンネルポリゴン 庭園路ポリゴン 真幅道路ポリゴン 高速道路ポリゴン; do
  echo -n "$name: SHP="; ogrinfo -so -al "input_data/${name}.shp" 2>/dev/null | grep "Feature Count"
  echo -n "       Parquet="; ogrinfo -so -al "output_data/${name}.parquet" 2>/dev/null | grep "Feature Count"
done
```

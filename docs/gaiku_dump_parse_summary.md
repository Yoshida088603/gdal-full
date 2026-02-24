# gaiku_full20250220.dmp パース結果サマリ

## ファイル情報

| 項目 | 値 |
|------|-----|
| パス | `input_data/gaiku_full20250220/gaiku_full20250220.dmp` |
| 形式 | PostgreSQL プレーン SQL ダンプ（ASCII text） |
| サイズ | 約 485 MiB |
| リストア方法 | `psql -d <DB名> -f gaiku_full20250220.dmp` |

## ダンプの種類

- **pg_dump** のプレーン SQL 形式（`-Fp` またはデフォルト）。
- 先頭に `-- PostgreSQL database dump` とあり、`SET` / `CREATE TYPE` / `CREATE TABLE` / `COPY ... FROM stdin` で構成される。

## スキーマ構成

| スキーマ | 説明（推測） |
|----------|----------------|
| **public** | メインの業務テーブル（街区・基準点・図面等） |
| **tosikanmin** | 図書館民（等）向けの一部テーブル |
| **kanri** | 管理用（merge, sinsai 等） |

## ジオメトリを持つテーブル（geometry_columns より）

いずれも **ジオメトリ型は POINT**、**SRID は 900913**（Web Mercator）。

| スキーマ | テーブル名 | ジオメトリカラム | 型 | SRID |
|----------|------------|------------------|-----|------|
| public | kijyunten | the_geom | POINT | 900913 |
| public | hojyoten_ | the_geom | POINT | 900913 |
| public | hojyoten | the_geom | POINT | 900913 |
| public | sankakuten | the_geom | POINT | 900913 |
| public | takakuten | the_geom | POINT | 900913 |
| public | totiriyo_kijyunten | the_geom | POINT | 900913 |
| public | totiriyo_hojyoten | the_geom | POINT | 900913 |
| public | totiriyo_sankakuten | the_geom | POINT | 900913 |
| public | totiriyo_takakuten | the_geom | POINT | 900913 |
| tosikanmin | sankakuten | the_geom | POINT | 900913 |
| tosikanmin | takakuten | the_geom | POINT | 900913 |

※ COPY で実データがあるのは、少なくとも public.hojyoten / sankakuten / takakuten、public.totiriyo_*、tosikanmin.sankakuten / takakuten 等。

## COPY でデータが含まれる主なテーブル（抜粋）

- **kanri**: hojyoten, merge, sankakuten, sinsai, takakuten
- **public**: antenna_iti, gaikuten_seika_kubun, gaikuten_settisya, genkyo_timoku, geometry_columns, hojyoten, ken, kijyunten_syubetu, kyoukai_kakutei, sankakuten, setti_kubun, sikutyo, sikutyo_new, sokutei_housiki, sokutikei, spatial_ref_sys, takakuten, tatiai_kakutei_umu, timei, timei_jyuryodata, tmp_gaikuten, tmp_haiten, totiriyo_hojyoten, totiriyo_sankakuten, totiriyo_takakuten, tyomoku, tyomoku_new, zaisitu_kubun, hyousiki, …
- **tosikanmin**: sankakuten, sankakuten_test, seido_kubun, sokutei_housiki, sokutikei, syubetu, takakuten, takakuten_test, zaisitu

## 方針立案のためのポイント

1. **リストア**  
   空 DB を作成 → PostGIS 拡張を有効化 → `psql -d <DB> -f gaiku_full20250220.dmp` でリストア可能。

2. **GDAL パイプライン（run_pipeline_pg.sh）**  
   リストア後、接続文字列を指定して実行すれば、上記ジオメトリテーブルが `ogrinfo -so` に列挙され、PG → GeoParquet → FGB / PMTiles の対象にできる。

3. **CRS**  
   ダンプ内は SRID=900913（Web Mercator）。日本平面座標系（EPSG:6674 等）に揃えたい場合は、`run_pipeline_pg.sh` の ogr2ogr に `-t_srs EPSG:6674` を付与するオプションを検討する。

4. **データ量**  
   約 485 MiB の SQL のため、リストアと変換にはある程度時間がかかる想定。まずは 1 テーブル（例: public.hojyoten や public.sankakuten）でリストア〜パイプライン実行を試すとよい。

5. **スキーマ付きレイヤ名**  
   `public.hojyoten`、`tosikanmin.takakuten` のようにスキーマ付きでレイヤが列挙される。`run_pipeline_pg.sh` はレイヤ名の `.` を `_` に置換してファイル名にしている（例: `public_hojyoten.parquet`）。

## 次のステップ

実行手順（リストアから GeoParquet / FGB / PMTiles までの一連の流れ）は [pipeline_pg.md](pipeline_pg.md) の「gaiku 系ダンプ（プレーン SQL .dmp）の例」および「リストア用スクリプト」を参照すること。

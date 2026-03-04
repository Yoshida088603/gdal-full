# 都市部官民基準点等データ 全CSV → 1本PMTiles 変換計画

## 1. 情報収集結果

### 1.1 入力データ

| 項目 | 内容 |
|------|------|
| **フォルダ** | `データ_origin/都市部官民基準点等データ` |
| **CSV ファイル数** | **284 件** |
| **命名規則** | `TKS_*.csv` 等（例: TKS_04206, TKT_23105 …） |
| **座標** | 列「X座標」「Y座標」。平面直角座標（系1～19）。 |
| **CRS 列** | 列「座標系」（0-based 11）。系番号 1～19 → EPSG:6669～6687。 |
| **前処理** | 既存 `csv_to_geoparquet_tochi.py` で UTF-8 化・X/Y ヘッダ入れ替え（Y,X 並び対応）・系番号取得（街区と同様の列構成のため流用可）。 |

### 1.2 既存スクリプトの役割

| スクリプト | 対象 | 入出力 | 都市部官民での利用 |
|------------|------|--------|---------------------|
| `csv_to_geopackage.sh` | 街区・都市部官民・土地活用等 | CSV → 1 CSV 1 GPKG | **利用可**。都市部官民ブロックで全 CSV を `データ_geopackage_converted/都市部官民基準点等データ/*.gpkg` に変換。各 GPKG は **既に EPSG:3857**（`-s_srs EPSG:$EPSG -t_srs EPSG:3857`）。 |
| `merge_toshi_geopackage.sh` | 都市部官民（GPKG 経由） | 複数 GPKG → 1 merged.gpkg | **利用可**。`データ_geopackage_converted/都市部官民基準点等データ/*.gpkg` を `都市部官民基準点等_merged.gpkg`（レイヤ `toshi_merged`）にマージ。 |
| `gpkg_to_pmtiles.sh` | 任意 1 GPKG | 1 GPKG → 1 PMTiles | **利用可**。マージ後の 1 本 GPKG を渡せば PMTiles 化できる。 |

### 1.3 出力先の慣例

| 段階 | パス |
|------|------|
| CSV → GPKG（1ファイル1GPKG） | `データ_geopackage_converted/都市部官民基準点等データ/<ベース名>.gpkg` |
| マージ後 1 本 GPKG | `データ_geopackage_marged/都市部官民基準点等_merged.gpkg` |
| 最終 PMTiles | `データ_geopackage_marged/都市部官民基準点等_merged.pmtiles` |

### 1.4 都市部官民マージの特徴

- **都市部官民**: `csv_to_geopackage.sh` の都市部官民ブロックで **既に 3857 に変換**して GPKG 出力している（tochi.py で系番号取得し `-s_srs EPSG:6669～6687 -t_srs EPSG:3857`）。  
  → マージ時は **SRS 変換不要**。全 GPKG を **同一レイヤ名で -update -append** するだけでよい。

---

## 2. 計画（必要な作業）

### ステップ 1: 全 CSV → GPKG（csv_to_geopackage.sh で完結）

- **実行**: `csv_to_geopackage.sh`（入力ルート未指定なら `データ_origin` がデフォルト）。
- **結果**: `データ_geopackage_converted/都市部官民基準点等データ/*.gpkg` が 284 件できる。
- **オプション**: `-s` で既存 GPKG をスキップ可能。再変換時はスキップなしで上書き。

### ステップ 2: 都市部官民用「GPKG マージ」（実装済み）

- **スクリプト**: `merge_toshi_geopackage.sh`
  - **入力**: `データ_geopackage_converted/都市部官民基準点等データ/*.gpkg`
  - **出力**: `データ_geopackage_marged/都市部官民基準点等_merged.gpkg`
  - **処理**: 先頭 1 件で `-f GPKG -nln toshi_merged` で新規作成し、2 件目以降は `-update -append -nln toshi_merged` で追加。全ファイルとも既に 3857 のため `-s_srs` / `-t_srs` は不要。
- **実行**: `bash scripts/merge_toshi_geopackage.sh`（`source env.sh` のうえで実行）。

### ステップ 3: 1 本 GPKG → PMTiles（既存で完結）

- **実行**: `gpkg_to_pmtiles.sh データ_geopackage_marged/都市部官民基準点等_merged.gpkg`
- **結果**: `データ_geopackage_marged/都市部官民基準点等_merged.pmtiles` ができる。

---

## 3. 実行順序のまとめ

1. `cd MapLibre-HandsOn-Beginner/05_ポリゴン表示/gdal-full && source env.sh`
2. （必要なら）都市部官民の既存 GPKG を削除:  
   `rm -f "inputfile/.../データ_geopackage_converted/都市部官民基準点等データ/"*.gpkg`
3. 全 CSV → GPKG:  
   `bash scripts/csv_to_geopackage.sh`
4. 都市部官民マージ:  
   `bash scripts/merge_toshi_geopackage.sh`
5. PMTiles 出力:  
   `bash scripts/gpkg_to_pmtiles.sh "inputfile/.../データ_geopackage_marged/都市部官民基準点等_merged.gpkg"`

---

## 4. 補足

- **属性**: 元の X座標・Y座標・市区町名・所在地・基準点等名称・基準点コード・座標系・標高・測量年月日 等は CSV 列がそのまま GPKG 属性に入るため、マージ後も PMTiles に保持される。
- **レイヤ名**: マージ後は `toshi_merged` を想定。地図の `main.js` で都市部官民マージ PMTiles を参照する場合は `source-layer: 'toshi_merged'` とする。
- **件数**: 284 ファイルの GPKG 化・マージは街区より少ない。`-s` で再実行時に GPKG 作成をスキップできる。

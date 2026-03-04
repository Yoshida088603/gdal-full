# 街区基準点等データ 全CSV → 1本PMTiles 変換計画

## 1. 情報収集結果

### 1.1 入力データ

| 項目 | 内容 |
|------|------|
| **フォルダ** | `データ_origin/街区基準点等データ` |
| **CSV ファイル数** | **3,594 件** |
| **命名規則** | `H_*.csv`（例: H_01101, H_01102, H_02201 …） |
| **座標** | 列「X座標」「Y座標」（0-based で 13, 14）。平面直角座標（系1～19）。 |
| **CRS 列** | 列「座標系」（0-based 11）。系番号 1～19 → EPSG:6669～6687。 |
| **前処理** | 既存 `csv_to_geoparquet_tochi.py` で UTF-8 化・X/Y ヘッダ入れ替え（Y,X 並び対応）・系番号取得。 |

### 1.2 既存スクリプトの役割

| スクリプト | 対象 | 入出力 | 街区での利用 |
|------------|------|--------|--------------|
| `csv_to_geopackage.sh` | 街区・土地活用等 | CSV → 1 CSV 1 GPKG | **利用可**。街区ブロックで全 CSV を `データ_geopackage_converted/街区基準点等データ/*.gpkg` に変換。各 GPKG は **既に EPSG:3857**（`-s_srs EPSG:$EPSG -t_srs EPSG:3857`）。 |
| `merge_tochi_geopackage.py` | 土地活用のみ | 複数 GPKG → 1 merged.gpkg | **対象外**。土地活用は「系番号を読んで 6669～6687→3857 変換しながらマージ」。街区は変換済み 3857 なので「そのまま append のみ」でよい。 |
| `merge_gaiku_geopackage.sh` | 街区（GPKG 経由） | 複数 GPKG → 1 merged.gpkg | **利用可**。`データ_geopackage_converted/街区基準点等データ/*.gpkg` を `街区基準点等_merged.gpkg`（レイヤ `gaiku_merged`）にマージ。 |
| `merge_gaiku_geoparquet.py` | 街区（Parquet 経由） | 複数 **Parquet** → 1 merged | **経路が異なる**。入力が `データ_geoparquet_converted` の Parquet。今回は **GPKG 経由**（`データ_geopackage_converted`）で統一。 |
| `gpkg_to_pmtiles.sh` | 任意 1 GPKG | 1 GPKG → 1 PMTiles | **利用可**。マージ後の 1 本 GPKG を渡せば PMTiles 化できる。 |

### 1.3 出力先の慣例

| 段階 | パス |
|------|------|
| CSV → GPKG（1ファイル1GPKG） | `データ_geopackage_converted/街区基準点等データ/<ベース名>.gpkg` |
| マージ後 1 本 GPKG | `データ_geopackage_marged/街区基準点等_merged.gpkg` |
| 最終 PMTiles | `データ_geopackage_marged/街区基準点等_merged.pmtiles` |

※ 土地活用は `土地活用推進調査_merged.gpkg` / `_merged.pmtiles`。街区は「街区基準点等_merged」で揃える。

### 1.4 街区マージの特徴（土地活用との違い）

- **土地活用**: 変換後 GPKG は **平面直角のまま**（系ごと EPSG:6669～6687）。マージ時に `merge_tochi_geopackage.py` が系番号を読んで 3857 に変換しながら append。
- **街区**: `csv_to_geopackage.sh` の街区ブロックで **既に 3857 に変換**して GPKG 出力している。  
  → マージ時は **SRS 変換不要**。全 GPKG を **同一レイヤ名で -update -append** するだけでよい。

---

## 2. 計画（必要な作業）

### ステップ 1: 全 CSV → GPKG（既存で完結）

- **実行**: `csv_to_geopackage.sh`（入力ルート未指定なら `データ_origin` がデフォルト）。
- **結果**: `データ_geopackage_converted/街区基準点等データ/*.gpkg` が 3,594 件できる。
- **オプション**: `-s` で既存 GPKG をスキップ可能。再変換時はスキップなしで上書き。

### ステップ 2: 街区用「GPKG マージ」（実装済み）

- **スクリプト**: `merge_gaiku_geopackage.sh`
  - **入力**: `データ_geopackage_converted/街区基準点等データ/*.gpkg`
  - **出力**: `データ_geopackage_marged/街区基準点等_merged.gpkg`
  - **処理**: 先頭 1 件で `-f GPKG -nln gaiku_merged` で新規作成し、2 件目以降は `-update -append -nln gaiku_merged` で追加。全ファイルとも既に 3857 のため `-s_srs` / `-t_srs` は不要。
- **実行**: `bash scripts/merge_gaiku_geopackage.sh`（`source env.sh` のうえで実行）。

### ステップ 3: 1 本 GPKG → PMTiles（既存で完結）

- **実行**: `gpkg_to_pmtiles.sh データ_geopackage_marged/街区基準点等_merged.gpkg`
- **結果**: `データ_geopackage_marged/街区基準点等_merged.pmtiles` ができる。

---

## 3. 実行順序のまとめ

1. `cd MapLibre-HandsOn-Beginner/05_ポリゴン表示/gdal-full && source env.sh`
2. （必要なら）街区の既存 GPKG を削除:  
   `rm -f "inputfile/.../データ_geopackage_converted/街区基準点等データ/"*.gpkg`
3. 全 CSV → GPKG:  
   `bash scripts/csv_to_geopackage.sh`
4. 街区マージ:  
   `bash scripts/merge_gaiku_geopackage.sh`
5. PMTiles 出力:  
   `bash scripts/gpkg_to_pmtiles.sh "inputfile/.../データ_geopackage_marged/街区基準点等_merged.gpkg"`

---

## 4. 補足

- **属性**: 元の X座標・Y座標は CSV 列がそのまま GPKG 属性に入るため、マージ後も PMTiles に保持される。
- **レイヤ名**: マージ後は `gaiku_merged` を想定。地図の `main.js` で街区マージ PMTiles を参照する場合は `source-layer: 'gaiku_merged'` とする。
- **件数**: 3,594 ファイルの GPKG 化・マージは時間とディスクを要する。`-s` で再実行時に GPKG 作成をスキップできる。

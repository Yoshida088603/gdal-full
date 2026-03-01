#!/usr/bin/env python3
# データ_geopackage_converted/土地活用推進調査 内の全 .gpkg を、
# 各ファイルの col5（平面直角座標系の系番号 1～19）に応じて EPSG:6669～6687 → Webメルカトル(EPSG:3857) に変換し 1 本にマージする。
# 元の座標は属性 元X・元Y として保持する（OGR でジオメトリ重心の座標を追加してから ogr2ogr で変換・マージ）。
# 使い方: source env.sh && python3 scripts/merge_tochi_geopackage.py
# 出力: データ_geopackage_marged/土地活用推進調査_merged.gpkg
# PMTiles が欲しい場合は別途: source env.sh && ./scripts/gpkg_to_pmtiles.sh

import os
import re
import subprocess
import sys
import tempfile

try:
    from osgeo import ogr
    from osgeo import osr
    ogr.DontUseExceptions()
    HAS_OGR = True
except ImportError:
    HAS_OGR = False

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
DATA_PARENT = os.path.join(
    PROJECT_ROOT,
    "inputfile", "20260219昨年納品DVD", "05ホームページ公開用データ及びプログラム",
)
INPUT_DIR = os.path.join(DATA_PARENT, "データ_geopackage_converted", "土地活用推進調査")
OUTPUT_FILE = os.path.join(DATA_PARENT, "データ_geopackage_marged", "土地活用推進調査_merged.gpkg")
TGT_SRS = "EPSG:3857"
# 平面直角座標系 系1～系19 → EPSG:6669～6687（例: 系9 → EPSG:6677）
EPSG_BASE = 6668
# 座標系は col5（0-based 属性インデックス 5）で固定
ZUKEI_ATTR_INDEX = 5


def get_zukei(gpkg_path, ogrinfo_cmd="ogrinfo"):
    """GPKG の 1 レコード目の col5（属性インデックス 5）から平面直角座標系の系番号を取得。1～19 を返し、取得できない場合は None。"""
    try:
        out = subprocess.run(
            [ogrinfo_cmd, "-al", gpkg_path],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=60,
            cwd=PROJECT_ROOT,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    txt = (out.stdout or "") + (out.stderr or "")

    # 1) 土地活用は col5 が系番号で固定。最初の OGRFeature の属性リストで index 5 の値を採用
    feature_block = re.search(r"OGRFeature\([^)]+\):\d+\s*\n(.*?)(?=OGRFeature\(|\Z)", txt, re.DOTALL)
    if feature_block:
        block = feature_block.group(1)
        attr_vals = []
        for line in block.splitlines():
            m_line = re.search(r"\)\s*=\s*(.*)$", line)
            if m_line:
                attr_vals.append(m_line.group(1).strip())
        if len(attr_vals) > ZUKEI_ATTR_INDEX:
            val = attr_vals[ZUKEI_ATTR_INDEX]
            if val.isdigit():
                z = int(val)
                if 1 <= z <= 19:
                    return z

    # 2) フォールバック: 「座標系」の名前で検索
    m = re.search(r"座標系\s*\([^)]+\)\s*=\s*(\d+)", txt)
    if m:
        z = int(m.group(1))
        if 1 <= z <= 19:
            return z
    return None


def get_layer_info(gpkg_path, ogrinfo_cmd="ogrinfo"):
    """ogrinfo -al -so でレイヤ名とジオメトリ列名を取得。(layer_name, geom_column) を返す。"""
    try:
        out = subprocess.run(
            [ogrinfo_cmd, "-al", "-so", gpkg_path],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
            cwd=PROJECT_ROOT,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None, None
    if out.returncode != 0:
        return None, None
    txt = out.stdout or ""
    layer_name = None
    geom_col = "geometry"
    for line in txt.splitlines():
        m = re.match(r"Layer name:\s*(.+)", line)
        if m:
            layer_name = m.group(1).strip()
            continue
        m = re.match(r"Geometry Column\s*=\s*(.+)", line, re.IGNORECASE)
        if m:
            geom_col = m.group(1).strip()
    if not layer_name:
        base = os.path.splitext(os.path.basename(gpkg_path))[0]
        layer_name = base
    return layer_name, geom_col


def add_genxy_to_gpkg(gpkg_path, zukei, out_path):
    """OGR で gpkg_path を開き、各フィーチャのジオメトリ重心を元X・元Y として追加した GPKG を out_path に作成する。成功で True。"""
    if not HAS_OGR:
        return False
    ds = ogr.Open(gpkg_path)
    if not ds:
        return False
    layer = ds.GetLayer(0)
    if not layer:
        ds = None
        return False
    srs = osr.SpatialReference()
    srs.ImportFromEPSG(EPSG_BASE + zukei)
    driver = ogr.GetDriverByName("GPKG")
    out_ds = driver.CreateDataSource(out_path)
    if not out_ds:
        ds = None
        return False
    out_lyr = out_ds.CreateLayer(
        "with_genxy",
        srs=srs,
        geom_type=layer.GetGeomType(),
        options=["GEOMETRY_NAME=geom"],
    )
    defn = layer.GetLayerDefn()
    for i in range(defn.GetFieldCount()):
        out_lyr.CreateField(defn.GetFieldDefn(i))
    out_lyr.CreateField(ogr.FieldDefn("元X", ogr.OFTReal))
    out_lyr.CreateField(ogr.FieldDefn("元Y", ogr.OFTReal))
    out_defn = out_lyr.GetLayerDefn()
    idx_x = out_defn.GetFieldIndex("元X")
    idx_y = out_defn.GetFieldIndex("元Y")
    for feat in layer:
        geom = feat.GetGeometryRef()
        gx, gy = None, None
        if geom and not geom.IsEmpty():
            try:
                if geom.GetGeometryType() in (ogr.wkbPoint, ogr.wkbPoint25D):
                    gx, gy = geom.GetX(), geom.GetY()
                else:
                    cent = geom.Centroid()
                    gx = cent.GetX()
                    gy = cent.GetY()
            except Exception:
                try:
                    g = geom.GetGeometryRef(0)
                    if g:
                        pt = g.GetPoint_2D(0)
                        gx, gy = pt[0], pt[1]
                except Exception:
                    pass
        new_feat = ogr.Feature(out_defn)
        for i in range(defn.GetFieldCount()):
            new_feat.SetField(i, feat.GetField(i))
        if gx is not None:
            new_feat.SetField(idx_x, gx)
        if gy is not None:
            new_feat.SetField(idx_y, gy)
        if geom:
            new_feat.SetGeometry(geom.Clone())
        out_lyr.CreateFeature(new_feat)
    out_ds = None
    ds = None
    return True


def main():
    if not os.path.isdir(INPUT_DIR):
        print(f"Error: input directory not found: {INPUT_DIR}", file=sys.stderr)
        sys.exit(1)

    gpkgs = sorted(
        os.path.join(INPUT_DIR, f)
        for f in os.listdir(INPUT_DIR)
        if f.lower().endswith(".gpkg")
    )
    if not gpkgs:
        print(f"Error: no .gpkg files in {INPUT_DIR}", file=sys.stderr)
        sys.exit(1)

    out_dir = os.path.dirname(OUTPUT_FILE)
    os.makedirs(out_dir, exist_ok=True)

    if not HAS_OGR:
        print("Warning: osgeo.ogr がありません。元X・元Y なしでマージします。pip install gdal などで OGR を入れると元座標を保持できます。", file=sys.stderr)
    print(f"Merge 土地活用推進調査: {len(gpkgs)} files -> Web Mercator ({TGT_SRS}) -> {OUTPUT_FILE}", file=sys.stderr)
    first = True
    merged = 0
    skipped = 0

    for path in gpkgs:
        base = os.path.basename(path)
        zukei = get_zukei(path)
        if zukei is None:
            print(f"Warning: skip (no 座標系 1-19 in col5): {base}", file=sys.stderr)
            skipped += 1
            continue
        epsg = EPSG_BASE + zukei
        src_path = path
        temp_path = None
        if HAS_OGR:
            try:
                tmpdir = os.path.dirname(OUTPUT_FILE)
                if os.path.isdir(tmpdir):
                    fd, temp_path = tempfile.mkstemp(suffix=".gpkg", dir=tmpdir)
                    os.close(fd)
                    os.unlink(temp_path)
            except OSError:
                temp_path = None
            if temp_path and add_genxy_to_gpkg(path, zukei, temp_path):
                src_path = temp_path
            else:
                if temp_path and os.path.exists(temp_path):
                    try:
                        os.unlink(temp_path)
                    except OSError:
                        pass
                src_path = path
        if first:
            cmd = [
                "ogr2ogr", "-f", "GPKG", "-nln", "tochi_merged",
                "-s_srs", f"EPSG:{epsg}",
                "-t_srs", TGT_SRS,
                OUTPUT_FILE,
                src_path,
            ]
            first = False
        else:
            cmd = [
                "ogr2ogr", "-update", "-append", "-nln", "tochi_merged",
                "-s_srs", f"EPSG:{epsg}",
                "-t_srs", TGT_SRS,
                OUTPUT_FILE,
                src_path,
            ]
        ret = subprocess.run(cmd, cwd=PROJECT_ROOT, timeout=300)
        if src_path != path and os.path.exists(src_path):
            try:
                os.unlink(src_path)
            except OSError:
                pass
        if ret.returncode != 0:
            print(f"Warning: ogr2ogr failed for {base}", file=sys.stderr)
            skipped += 1
            continue
        merged += 1
        if merged % 100 == 0:
            print(f"Progress: {merged} files merged ...", file=sys.stderr)

    print(f"Merged: {merged}, skipped: {skipped}. Output: {OUTPUT_FILE}", file=sys.stderr)
    if merged == 0:
        print("Error: no files were merged.", file=sys.stderr)
        sys.exit(1)
    print("Done.", file=sys.stderr)


if __name__ == "__main__":
    main()

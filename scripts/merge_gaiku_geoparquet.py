#!/usr/bin/env python3
# 街区基準点等データの GeoParquet を、ファイルごとの座標系（1～19）に応じて WGS84 に変換し 1 本にマージする。
# 使い方: source env.sh のうえで python3 scripts/merge_gaiku_geoparquet.py
#   既存の 街区基準点等_merged.parquet は上書きする。

import os
import re
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
DATA_PARENT = os.path.join(
    PROJECT_ROOT,
    "inputfile", "20260219昨年納品DVD", "05ホームページ公開用データ及びプログラム",
)
INPUT_DIR = os.path.join(DATA_PARENT, "データ_geoparquet_converted", "街区基準点等データ")
OUTPUT_DIR = os.path.join(DATA_PARENT, "データ_geoparquet_marged")
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "街区基準点等_merged.parquet")
# Parquet は -update -append 非対応のため、一旦 GeoPackage にマージしてから Parquet に変換する
OUTPUT_GPKG = os.path.join(OUTPUT_DIR, "街区基準点等_merged_tmp.gpkg")

# 座標系 1～19 → EPSG:6669～6687
EPSG_BASE = 6668


def get_zukei(parquet_path, ogrinfo_cmd="ogrinfo", debug=False):
    """Parquet の 1 レコード目から「座標系」属性を取得。1～19 を返し、取得できない場合は None。"""
    try:
        out = subprocess.run(
            [ogrinfo_cmd, "-al", parquet_path],
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

    # 1) 「座標系 (Integer|Integer64|String) = N」で検索（Parquet が数値を String で持つ場合あり）
    m = re.search(r"座標系\s*\([^)]+\)\s*=\s*(\d+)", txt)
    if m:
        z = int(m.group(1))
        if 1 <= z <= 19:
            return z
        return None

    # 2) フォールバック: スキーマの「Field N」の列名で値を探す（N=10,11,12 の順で試す）
    for field_idx in (10, 11, 12):
        schema_field = re.search(
            rf"Field\s+{field_idx}:\s*(.+?)\s*\((?:Integer64?|Real|String)",
            txt,
            re.IGNORECASE,
        )
        if not schema_field:
            continue
        name = schema_field.group(1).strip()
        m2 = re.search(
            re.escape(name) + r"\s*\([^)]+\)\s*=\s*(\d+)",
            txt,
        )
        if m2:
            z = int(m2.group(1))
            if 1 <= z <= 19:
                return z

    # 3) フォールバック: 最初の OGRFeature の属性行から座標系を取得。列位置はずれるため 8～13 番目を順に試す
    feature_block = re.search(r"OGRFeature\([^)]+\):\d+\s*\n(.*?)(?=OGRFeature\(|\Z)", txt, re.DOTALL)
    if feature_block:
        block = feature_block.group(1)
        # 行ごとに " (型) = 値" の値を取得（\r\n や $ の扱いを避けるため行分割してから正規表現）
        attr_vals = []
        for line in block.splitlines():
            m_line = re.search(r"\)\s*=\s*(.*)$", line)
            if m_line:
                attr_vals.append(m_line.group(1).strip())
        for idx in (8, 9, 10, 11, 12, 13):
            if len(attr_vals) <= idx:
                continue
            val = attr_vals[idx]
            if val.isdigit():
                z = int(val)
                if 1 <= z <= 19:
                    return z

    if debug:
        # デバッグ: 先頭行を stderr に出力（実際のフィールド名確認用）
        print(" [ogrinfo head for 座標系 check]", file=sys.stderr)
        for line in txt.splitlines()[:80]:
            print(line, file=sys.stderr)
    return None


def main():
    # デバッグ: 指定ファイルの ogrinfo -al をそのまま表示して終了
    if len(sys.argv) >= 3 and sys.argv[1] == "--dump-ogrinfo":
        path = sys.argv[2]
        if not os.path.isabs(path):
            path = os.path.join(PROJECT_ROOT, path)
        if not os.path.isfile(path):
            print(f"Error: file not found: {path}", file=sys.stderr)
            sys.exit(1)
        try:
            out = subprocess.run(
                ["ogrinfo", "-al", path],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=60,
                cwd=PROJECT_ROOT,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired) as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
        try:
            print(out.stdout, end="")
            if out.stderr:
                print(out.stderr, file=sys.stderr, end="")
        except BrokenPipeError:
            pass  # head 等でパイプが閉じた場合は無視
        sys.exit(0 if out.returncode == 0 else 1)

    if not os.path.isdir(INPUT_DIR):
        print(f"Error: input directory not found: {INPUT_DIR}", file=sys.stderr)
        sys.exit(1)

    parquets = sorted(
        os.path.join(INPUT_DIR, f)
        for f in os.listdir(INPUT_DIR)
        if f.lower().endswith(".parquet")
    )
    if not parquets:
        print(f"Error: no .parquet files in {INPUT_DIR}", file=sys.stderr)
        sys.exit(1)

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Parquet は -update -append 非対応のため、まず GeoPackage にマージする
    appended = 0
    skipped = 0
    debug_done = False
    first_append = True
    for i, path in enumerate(parquets):
        zukei = get_zukei(path, debug=(not debug_done))
        if zukei is None:
            if not debug_done:
                debug_done = True  # 最初のスキップ時のみ ogrinfo 先頭を表示
            print(f"Warning: skip (no 座標系 1-19): {os.path.basename(path)}", file=sys.stderr)
            skipped += 1
            continue
        epsg = EPSG_BASE + zukei
        if first_append:
            cmd = [
                "ogr2ogr", "-f", "GPKG",
                "-nln", "merged",
                "-s_srs", f"EPSG:{epsg}",
                "-t_srs", "EPSG:4326",
                OUTPUT_GPKG,
                path,
            ]
            first_append = False
        else:
            cmd = [
                "ogr2ogr", "-update", "-append",
                "-nln", "merged",
                "-s_srs", f"EPSG:{epsg}",
                "-t_srs", "EPSG:4326",
                OUTPUT_GPKG,
                path,
            ]
        ret = subprocess.run(cmd, cwd=PROJECT_ROOT, timeout=300)
        if ret.returncode != 0:
            print(f"Warning: ogr2ogr failed for {os.path.basename(path)}", file=sys.stderr)
            skipped += 1
            continue
        appended += 1
        if appended % 500 == 0:
            print(f"Progress: {appended} files merged ...", file=sys.stderr)

    print(f"Merged: {appended}, skipped: {skipped}", file=sys.stderr)

    if appended == 0:
        print("Error: no files were merged.", file=sys.stderr)
        sys.exit(1)

    # GeoPackage を Parquet に変換（既存の 街区基準点等_merged.parquet は上書き）
    ret = subprocess.run(
        [
            "ogr2ogr", "-f", "Parquet",
            "-lco", "GEOMETRY_ENCODING=WKB",
            OUTPUT_FILE,
            OUTPUT_GPKG,
        ],
        cwd=PROJECT_ROOT,
        timeout=600,
    )
    if ret.returncode != 0:
        print("Error: GeoPackage to Parquet conversion failed.", file=sys.stderr)
        sys.exit(1)
    try:
        os.remove(OUTPUT_GPKG)
    except OSError:
        print(f"Warning: could not remove temp file {OUTPUT_GPKG}", file=sys.stderr)

    # 検証: CRS と Feature Count
    try:
        out = subprocess.run(
            ["ogrinfo", "-al", "-so", OUTPUT_FILE],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
            cwd=PROJECT_ROOT,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        print("Verification (ogrinfo) skipped.", file=sys.stderr)
    else:
        if out.returncode == 0:
            print(out.stdout)
            if "EPSG:4326" not in out.stdout and "4326" not in out.stdout:
                print("Warning: expected Layer SRS EPSG:4326. Check output above.", file=sys.stderr)
        else:
            print("Warning: ogrinfo verification failed.", file=sys.stderr)

    print(f"Done. Output: {OUTPUT_FILE}", file=sys.stderr)


if __name__ == "__main__":
    main()

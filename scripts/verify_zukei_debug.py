#!/usr/bin/env python3
"""座標系取得の原因検証用。get_zukei が None を返す理由を特定する。
使い方: source env.sh のうえで
  python3 scripts/verify_zukei_debug.py [parquetファイルパス]
  未指定時は H_01101.parquet を使用。
"""

import os
import re
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
INPUT_DIR = os.path.join(
    PROJECT_ROOT,
    "inputfile", "20260219昨年納品DVD", "05ホームページ公開用データ及びプログラム",
    "データ_geoparquet_converted", "街区基準点等データ",
)


def main():
    if len(sys.argv) >= 2:
        path = sys.argv[1]
        if not os.path.isabs(path):
            path = os.path.join(PROJECT_ROOT, path)
    else:
        path = os.path.join(INPUT_DIR, "H_01101.parquet")

    if not os.path.isfile(path):
        print(f"Error: file not found: {path}", file=sys.stderr)
        sys.exit(1)

    print(f"=== 検証対象: {path}", file=sys.stderr)
    print(f"=== PROJECT_ROOT: {PROJECT_ROOT}", file=sys.stderr)
    print(f"=== cwd で ogrinfo 実行", file=sys.stderr)

    out = subprocess.run(
        ["ogrinfo", "-al", path],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
        cwd=PROJECT_ROOT,
    )

    print(f"\n--- ogrinfo returncode: {out.returncode}", file=sys.stderr)
    print(f"--- stdout length: {len(out.stdout or '')}", file=sys.stderr)
    print(f"--- stderr length: {len(out.stderr or '')}", file=sys.stderr)

    txt = (out.stdout or "") + (out.stderr or "")
    print(f"--- txt length: {len(txt)}", file=sys.stderr)

    # 1) 座標系 直接検索
    m1 = re.search(r"座標系\s*\([^)]+\)\s*=\s*(\d+)", txt)
    print(f"\n--- 1) 座標系 直接: {'MATCH ' + m1.group(1) if m1 else 'NO MATCH'}", file=sys.stderr)

    # 2) Field N 検索
    for idx in (10, 11, 12):
        sf = re.search(rf"Field\s+{idx}:\s*(.+?)\s*\((?:Integer64?|Real|String)", txt, re.I)
        print(f"--- 2) Field {idx}: {'MATCH ' + repr(sf.group(1)) if sf else 'NO MATCH'}", file=sys.stderr)

    # 3) OGRFeature ブロック
    fb = re.search(r"OGRFeature\([^)]+\):\d+\s*\n(.*?)(?=OGRFeature\(|\Z)", txt, re.DOTALL)
    if not fb:
        print(f"\n--- 3) OGRFeature ブロック: NO MATCH", file=sys.stderr)
        print(f"--- 'OGRFeature' in txt: {'OGRFeature' in txt}", file=sys.stderr)
        # 先頭 1500 文字を表示（原因特定用）
        print("\n--- txt 先頭 1500 文字 (repr):", file=sys.stderr)
        print(repr(txt[:1500]), file=sys.stderr)
        return

    block = fb.group(1)
    print(f"\n--- 3) OGRFeature ブロック: MATCH, block length={len(block)}", file=sys.stderr)
    print(f"--- block 先頭 500 文字 (repr):", file=sys.stderr)
    print(repr(block[:500]), file=sys.stderr)

    # 4) 属性行パース
    attr_vals = []
    for i, line in enumerate(block.splitlines()):
        m_line = re.search(r"\)\s*=\s*(.*)$", line)
        if m_line:
            val = m_line.group(1).strip()
            attr_vals.append(val)
            if i < 15:  # 先頭15行を表示
                print(f"  line{i}: val={repr(val)}", file=sys.stderr)

    print(f"\n--- attr_vals 件数: {len(attr_vals)}", file=sys.stderr)
    for idx in (8, 9, 10, 11, 12, 13):
        if idx < len(attr_vals):
            v = attr_vals[idx]
            digit = v.isdigit()
            z = int(v) if digit else None
            in_range = (1 <= z <= 19) if z is not None else False
            print(f"  idx={idx}: val={repr(v)} isdigit={digit} z={z} 1-19={in_range}", file=sys.stderr)


if __name__ == "__main__":
    main()

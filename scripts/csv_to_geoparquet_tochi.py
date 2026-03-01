#!/usr/bin/env python3
# 土地活用推進調査 CSV 用: ヘッダなし・Shift-JIS を、仮ヘッダ付き UTF-8 CSV に変換する。
# 8列目・9列目を座標として使用。平面直角座標は X=東方向・Y=北方向。
# 国土数値情報の一部では 8列目=Y(北緯相当)、9列目=X(東経相当) の並びのため、
# ここでは 8列目→y, 9列目→x として ogr2ogr に渡す（道路位置に合うように X/Y をこの順で解釈）。
# 使い方: python3 csv_to_geoparquet_tochi.py <入力.csv> <出力.csv>

import csv
import sys

def main():
    if len(sys.argv) != 3:
        sys.stderr.write("Usage: csv_to_geoparquet_tochi.py <input.csv> <output.csv>\n")
        sys.exit(1)
    src = sys.argv[1]
    dst = sys.argv[2]

    # 列数は可変のため、1行目で列数を取得し、col0..col7, x, y, col10... のようにヘッダを付与
    encodings = ["cp932", "utf-8", "utf-8-sig"]
    errors_options = ["strict", "strict", "strict"]
    encodings += ["utf-8", "cp932"]
    errors_options += ["replace", "replace"]
    rows = None
    for enc, err in zip(encodings, errors_options):
        try:
            with open(src, "r", encoding=enc, newline="", errors=err) as f:
                reader = csv.reader(f)
                rows = list(reader)
            break
        except (UnicodeDecodeError, UnicodeError, OSError):
            continue
    if rows is None:
        sys.stderr.write("Failed to read CSV with cp932/utf-8\n")
        sys.exit(1)

    if not rows:
        sys.stderr.write("Empty CSV\n")
        sys.exit(1)

    ncols = len(rows[0])
    # 8列目→y, 9列目→x（平面直角で X=東,Y=北。データが Y,X 並びの場合に正しい位置になる）
    header = [f"col{i}" for i in range(ncols)]
    if ncols > 8:
        header[7] = "y"
    if ncols > 9:
        header[8] = "x"

    try:
        with open(dst, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(header)
            writer.writerows(rows)
    except OSError as e:
        sys.stderr.write(f"Failed to write {dst}: {e}\n")
        sys.exit(1)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        import traceback
        sys.stderr.write(f"csv_to_geoparquet_tochi.py: {e}\n")
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)

#!/usr/bin/env python3
# 公図と現況のずれデータ用: X1,Y1..X4,Y4 から POLYGON WKT を生成し、WKT 列を追加した CSV を出力。
# 使い方: python3 csv_to_geoparquet_kozu.py <入力.csv> <出力.csv>

import csv
import sys

def main():
    if len(sys.argv) != 3:
        sys.stderr.write("Usage: csv_to_geoparquet_kozu.py <input.csv> <output.csv>\n")
        sys.exit(1)
    src = sys.argv[1]
    dst = sys.argv[2]

    encodings = ["cp932", "utf-8", "utf-8-sig", "utf-8"]
    errors_opts = ["strict", "strict", "strict", "replace"]
    rows = None
    for enc, err in zip(encodings, errors_opts):
        try:
            with open(src, "r", encoding=enc, newline="", errors=err) as f:
                reader = csv.reader(f)
                rows = list(reader)
            break
        except (UnicodeDecodeError, UnicodeError, OSError):
            continue
    if rows is None:
        sys.stderr.write("Failed to read CSV\n")
        sys.exit(1)

    if not rows:
        sys.stderr.write("Empty CSV\n")
        sys.exit(1)

    header = rows[0]
    # ヘッダから X1,Y1,X2,Y2,X3,Y3,X4,Y4 の列インデックスを探す（大文字小文字・全角は考慮しない簡易版）
    colmap = {}
    for i, h in enumerate(header):
        hnorm = h.strip().upper().replace(" ", "")
        if hnorm in ("X1", "Y1", "X2", "Y2", "X3", "Y3", "X4", "Y4"):
            colmap[hnorm] = i

    # 必須: X1,Y1,X2,Y2,X3,Y3,X4,Y4
    required = ["X1", "Y1", "X2", "Y2", "X3", "Y3", "X4", "Y4"]
    if not all(k in colmap for k in required):
        # フォールバック: よくある順序 NO, 図上X, 図上Y, 実測X, 実測Y, X1, Y1, X2, Y2, X3, Y3, X4, Y4, ...
        idx_x1 = idx_y1 = idx_x2 = idx_y2 = idx_x3 = idx_y3 = idx_x4 = idx_y4 = None
        for i, h in enumerate(header):
            hnorm = h.strip().upper()
            if hnorm == "X1": idx_x1 = i
            elif hnorm == "Y1": idx_y1 = i
            elif hnorm == "X2": idx_x2 = i
            elif hnorm == "Y2": idx_y2 = i
            elif hnorm == "X3": idx_x3 = i
            elif hnorm == "Y3": idx_y3 = i
            elif hnorm == "X4": idx_x4 = i
            elif hnorm == "Y4": idx_y4 = i
        if all(x is not None for x in (idx_x1, idx_y1, idx_x2, idx_y2, idx_x3, idx_y3, idx_x4, idx_y4)):
            colmap = {"X1": idx_x1, "Y1": idx_y1, "X2": idx_x2, "Y2": idx_y2,
                      "X3": idx_x3, "Y3": idx_y3, "X4": idx_x4, "Y4": idx_y4}
        else:
            # 固定位置: 多くのサンプルでは X1,Y1,X2,Y2,X3,Y3,X4,Y4 が 5,6,7,8,9,10,11,12 (0-based)
            if len(header) >= 13:
                colmap = {"X1": 5, "Y1": 6, "X2": 7, "Y2": 8, "X3": 9, "Y3": 10, "X4": 11, "Y4": 12}
            else:
                sys.stderr.write("Could not find X1,Y1,X2,Y2,X3,Y3,X4,Y4 columns\n")
                sys.exit(1)

    out_header = list(header) + ["WKT"]

    try:
        with open(dst, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(out_header)
            for row in rows[1:]:
                if len(row) <= max(colmap.values()):
                    continue
                try:
                    x1 = float(row[colmap["X1"]])
                    y1 = float(row[colmap["Y1"]])
                    x2 = float(row[colmap["X2"]])
                    y2 = float(row[colmap["Y2"]])
                    x3 = float(row[colmap["X3"]])
                    y3 = float(row[colmap["Y3"]])
                    x4 = float(row[colmap["X4"]])
                    y4 = float(row[colmap["Y4"]])
                except (ValueError, IndexError):
                    wkt = ""
                else:
                    wkt = f"POLYGON(({x1} {y1},{x2} {y2},{x3} {y3},{x4} {y4},{x1} {y1}))"
                writer.writerow(list(row) + [wkt])
    except OSError as e:
        sys.stderr.write(f"Failed to write {dst}: {e}\n")
        sys.exit(1)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        import traceback
        sys.stderr.write(f"csv_to_geoparquet_kozu.py: {e}\n")
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)

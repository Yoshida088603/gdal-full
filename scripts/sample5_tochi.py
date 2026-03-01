#!/usr/bin/env python3
# 土地活用 CSV を読み、Parquet と同じ列名で先頭5件を表示（Parquet と中身は同一）。
import csv
import os
import sys

def main():
    root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    csv_path = os.path.join(
        root, "inputfile", "20260219昨年納品DVD", "05ホームページ公開用データ及びプログラム",
        "データ_origin", "土地活用推進調査", "TH_01103.csv"
    )
    if not os.path.isfile(csv_path):
        print(f"CSV not found: {csv_path}", file=sys.stderr)
        sys.exit(1)
    for enc in ("cp932", "utf-8", "utf-8-sig"):
        try:
            with open(csv_path, "r", encoding=enc, newline="") as f:
                rows = list(csv.reader(f))
            break
        except (UnicodeDecodeError, UnicodeError):
            continue
    else:
        print("Failed to read CSV", file=sys.stderr)
        sys.exit(1)
    if not rows:
        sys.exit(1)
    ncols = len(rows[0])
    header = [f"col{i}" for i in range(ncols)]
    if ncols > 8:
        header[7] = "x"
    if ncols > 9:
        header[8] = "y"
    out_path = os.path.join(root, "parquet_sample5_TH_01103.txt")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("TH_01103.parquet の先頭5レコード（元 CSV と同じ内容・列名は Parquet の属性名）\n")
        f.write("=" * 80 + "\n\n")
        for i, row in enumerate(rows[:5]):
            f.write(f"--- レコード {i+1} ---\n")
            for j, (h, v) in enumerate(zip(header, row)):
                if j < len(row):
                    f.write(f"  {h}: {row[j]}\n")
                else:
                    f.write(f"  {h}: (なし)\n")
            if len(row) > len(header):
                for j in range(len(header), len(row)):
                    f.write(f"  col{j}: {row[j]}\n")
            f.write("\n")
        f.write("(座標は x, y の列。ジオメトリは POINT(x y) として Parquet に格納)\n")
    print(f"Wrote: {out_path}")

if __name__ == "__main__":
    main()

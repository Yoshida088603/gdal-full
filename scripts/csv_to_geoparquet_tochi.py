#!/usr/bin/env python3
# 国土数値情報 CSV 共通: 土地活用推進調査・街区基準点等のいずれかを検出し UTF-8 化する。
# 土地活用: ヘッダなし・8列目→y, 9列目→x の仮ヘッダ付与（ファイル並びが Y,X のため）。系番号は col5（0-based 5列目）。
# 街区基準点等: ヘッダあり。国土数値情報同様に「X座標」「Y座標」列の実データが Y,X 並びのため、
#   ヘッダのみ X座標↔Y座標 を入れ替えて出力し、ogr2ogr の解釈を合わせる。系番号は列「座標系」（0-based 11列目）。
# 使い方: python3 csv_to_geoparquet_tochi.py <入力.csv> <出力.csv> [--print-zukei]
#   --print-zukei 時は stdout にのみ系番号 1～19 を1行で出力（他は stderr）。

import csv
import sys

def main():
    args = [a for a in sys.argv[1:] if a != "--print-zukei"]
    print_zukei = len(args) != len(sys.argv) - 1
    if len(args) != 2:
        sys.stderr.write("Usage: csv_to_geoparquet_tochi.py <input.csv> <output.csv> [--print-zukei]\n")
        sys.exit(1)
    src, dst = args[0], args[1]

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

    first = rows[0]
    # 街区基準点等: 1行目に「座標系」と「X座標」があればヘッダあり
    is_gaiku = "座標系" in first and "X座標" in first

    if is_gaiku:
        # UTF-8 で書き出し。国土数値情報と同様に座標列は実データが Y,X 並びのため、ヘッダの X座標↔Y座標 を入れ替える。
        zukei_col = 11
        if len(rows) > 1 and len(rows[1]) > zukei_col:
            try:
                z = int(rows[1][zukei_col].strip())
                if 1 <= z <= 19 and print_zukei:
                    print(z)
            except ValueError:
                pass
        # ヘッダ行で「X座標」「Y座標」のラベルを入れ替え（ogr2ogr が正しく X,Y を解釈するため）
        out_rows = [list(rows[0])]
        for i, cell in enumerate(out_rows[0]):
            if cell == "X座標":
                out_rows[0][i] = "Y座標"
            elif cell == "Y座標":
                out_rows[0][i] = "X座標"
        out_rows.extend(rows[1:])
        try:
            with open(dst, "w", encoding="utf-8", newline="") as f:
                writer = csv.writer(f)
                writer.writerows(out_rows)
        except OSError as e:
            sys.stderr.write(f"Failed to write {dst}: {e}\n")
            sys.exit(1)
        return

    # 土地活用: ヘッダなし → col0..col7,y,x,col10...
    ncols = len(first)
    header = [f"col{i}" for i in range(ncols)]
    if ncols > 8:
        header[7] = "y"
    if ncols > 9:
        header[8] = "x"
    zukei_col = 5  # col5 = 系番号
    if len(rows) > 1 and len(rows[1]) > zukei_col and print_zukei:
        try:
            z = int(rows[1][zukei_col].strip())
            if 1 <= z <= 19:
                print(z)
        except ValueError:
            pass

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

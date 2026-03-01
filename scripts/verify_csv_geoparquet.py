#!/usr/bin/env python3
# 変換前 CSV と変換後 GeoParquet の件数が一致するか検証する。
# 使い方: source env.sh のうえで python3 scripts/verify_csv_geoparquet.py [入力ルート [出力ルート]]
#   未指定時は データ_origin と データ_geoparquet_converted を使用。

import os
import re
import subprocess
import sys

# プロジェクトルート（スクリプトの1つ上）
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
DATA_PARENT = os.path.join(
    PROJECT_ROOT,
    "inputfile", "20260219昨年納品DVD", "05ホームページ公開用データ及びプログラム",
)


def count_csv_rows(path, has_header=True, encodings=("utf-8", "utf-8-sig", "cp932")):
    """CSV のデータ行数を返す。has_header=True なら1行目をヘッダとして除く。"""
    for enc in encodings:
        try:
            with open(path, "r", encoding=enc, newline="", errors="strict") as f:
                lines = f.readlines()
            break
        except (UnicodeDecodeError, UnicodeError, OSError):
            continue
    else:
        return None
    n = len([L for L in lines if L.strip()])
    if has_header and n > 0:
        n -= 1
    return max(0, n)


def get_parquet_feature_count(parquet_path, ogrinfo_cmd="ogrinfo"):
    """ogrinfo -so -al で Feature Count を取得。"""
    try:
        out = subprocess.run(
            [ogrinfo_cmd, "-so", "-al", parquet_path],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
            cwd=PROJECT_ROOT,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    m = re.search(r"Feature Count:\s*(\d+)", out.stdout)
    return int(m.group(1)) if m else None


def main():
    input_root = os.path.join(DATA_PARENT, "データ_origin")
    output_root = os.path.join(DATA_PARENT, "データ_geoparquet_converted")
    if len(sys.argv) >= 2:
        input_root = sys.argv[1]
    if len(sys.argv) >= 3:
        output_root = sys.argv[2]

    if not os.path.isdir(input_root):
        print(f"Error: input root not found: {input_root}", file=sys.stderr)
        sys.exit(1)
    if not os.path.isdir(output_root):
        print(f"Error: output root not found: {output_root}", file=sys.stderr)
        sys.exit(1)

    ok = 0
    ng = 0
    pairs = []

    # 街区基準点等データ: 1 CSV = 1 parquet、ヘッダあり
    folder = "街区基準点等データ"
    in_dir = os.path.join(input_root, folder)
    out_dir = os.path.join(output_root, folder)
    if os.path.isdir(in_dir) and os.path.isdir(out_dir):
        for name in sorted(os.listdir(in_dir)):
            if not name.lower().endswith(".csv"):
                continue
            base = name[:-4]
            csv_path = os.path.join(in_dir, name)
            parquet_path = os.path.join(out_dir, base + ".parquet")
            pairs.append((folder, name, csv_path, parquet_path, True))

    # 都市部官民基準点等データ: 同様
    folder = "都市部官民基準点等データ"
    in_dir = os.path.join(input_root, folder)
    out_dir = os.path.join(output_root, folder)
    if os.path.isdir(in_dir) and os.path.isdir(out_dir):
        for name in sorted(os.listdir(in_dir)):
            if not name.lower().endswith(".csv"):
                continue
            base = name[:-4]
            csv_path = os.path.join(in_dir, name)
            parquet_path = os.path.join(out_dir, base + ".parquet")
            pairs.append((folder, name, csv_path, parquet_path, True))

    # 土地活用推進調査: ヘッダなし
    folder = "土地活用推進調査"
    in_dir = os.path.join(input_root, folder)
    out_dir = os.path.join(output_root, folder)
    if os.path.isdir(in_dir) and os.path.isdir(out_dir):
        for name in sorted(os.listdir(in_dir)):
            if not name.lower().endswith(".csv"):
                continue
            base = name[:-4]
            csv_path = os.path.join(in_dir, name)
            parquet_path = os.path.join(out_dir, base + ".parquet")
            pairs.append((folder, name, csv_path, parquet_path, False))

    # 公図と現況のずれデータ: サブフォルダ/配置テキスト.csv → サブフォルダ_配置テキスト.parquet
    folder = "公図と現況のずれデータ"
    in_dir = os.path.join(input_root, folder)
    out_dir = os.path.join(output_root, folder)
    if os.path.isdir(in_dir) and os.path.isdir(out_dir):
        for subname in sorted(os.listdir(in_dir)):
            subpath = os.path.join(in_dir, subname)
            if not os.path.isdir(subpath):
                continue
            csv_path = os.path.join(subpath, "配置テキスト.csv")
            if not os.path.isfile(csv_path):
                continue
            base = f"{subname}_配置テキスト"
            parquet_path = os.path.join(out_dir, base + ".parquet")
            pairs.append((folder, f"{subname}/配置テキスト.csv", csv_path, parquet_path, True))
        for name in sorted(os.listdir(in_dir)):
            if not name.lower().endswith(".csv"):
                continue
            csv_path = os.path.join(in_dir, name)
            if not os.path.isfile(csv_path):
                continue
            base = name[:-4]
            parquet_path = os.path.join(out_dir, base + ".parquet")
            pairs.append((folder, name, csv_path, parquet_path, True))

    print("CSV vs GeoParquet 件数照合")
    print("入力:", input_root)
    print("出力:", output_root)
    print("-" * 60)

    for folder, label, csv_path, parquet_path, has_header in pairs:
        csv_count = count_csv_rows(csv_path, has_header=has_header)
        if csv_count is None:
            print(f"[?] {folder}/{label}: CSV 読み込み失敗")
            ng += 1
            continue
        if not os.path.isfile(parquet_path):
            print(f"[MISS] {folder}/{label}: Parquet なし (CSV={csv_count})")
            ng += 1
            continue
        pq_count = get_parquet_feature_count(parquet_path)
        if pq_count is None:
            print(f"[?] {folder}/{label}: Parquet 読み込み失敗 (CSV={csv_count})")
            ng += 1
            continue
        if csv_count == pq_count:
            print(f"[OK] {folder}/{label}: {csv_count}")
            ok += 1
        else:
            print(f"[NG] {folder}/{label}: CSV={csv_count} vs Parquet={pq_count}")
            ng += 1

    print("-" * 60)
    print(f"OK: {ok}, NG/?: {ng}, 合計: {ok + ng}")
    sys.exit(1 if ng else 0)


if __name__ == "__main__":
    main()

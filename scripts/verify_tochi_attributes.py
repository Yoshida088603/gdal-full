#!/usr/bin/env python3
"""土地活用推進調査 GPKG の属性をサンプルで検証する。
   座標系（1～19）がどの列か特定するため、スキーマと先頭レコードの値を一覧表示する。
使い方（gdal-full をカレントに）:
  source env.sh
  python3 scripts/verify_tochi_attributes.py [ファイルパス]
  未指定時は データ_geopackage_converted/土地活用推進調査 内の最初の .gpkg を使用。
  -n N または --samples N : 先頭 N 件の .gpkg で col5/col2 を比較（複数サンプル）
  -d [N] または --diverse [N] : 命名規則の異なるグループから各 N 件ずつサンプル取得（デフォルト N=2）。スキーマ差の確認用。
  -o 出力.txt で ogrinfo の生出力をファイルに保存できる。
"""

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
TOCHI_DIR = os.path.join(DATA_PARENT, "データ_geopackage_converted", "土地活用推進調査")

# 座標系候補として注目する列（col5 と col2 を比較）
CANDIDATE_INDICES = (5, 2)


def get_first_feature_vals(gpkg_path):
    """GPKG の先頭レコードの属性値リストを返す。失敗時は None。"""
    out = subprocess.run(
        ["ogrinfo", "-al", gpkg_path],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
        cwd=PROJECT_ROOT,
    )
    txt = (out.stdout or "") + (out.stderr or "")
    feature_block = re.search(r"OGRFeature\([^)]+\):\d+\s*\n(.*?)(?=OGRFeature\(|\Z)", txt, re.DOTALL)
    if not feature_block:
        return None
    attr_vals = []
    for line in feature_block.group(1).splitlines():
        m = re.search(r"\)\s*=\s*(.*)$", line)
        if m:
            attr_vals.append(m.group(1).strip())
    return attr_vals


def filename_prefix(name):
    """ファイル名から命名規則のプレフィックスを取得。例: TH_01103.gpkg -> TH, TT_S_33204.gpkg -> TT_S"""
    base = name.replace(".gpkg", "").replace(".GPKG", "")
    parts = base.split("_")
    if len(parts) >= 2 and not parts[1].isdigit():
        return "_".join(parts[:2])
    return parts[0] if parts else base


def run_multi_sample(gpkgs, n):
    """複数サンプルで col5 / col2 を比較表で表示。"""
    files = gpkgs[:n]
    print(f"=== 複数サンプル比較（先頭 {len(files)} 件、候補列: col{CANDIDATE_INDICES}）", file=sys.stderr)
    print("-" * 70)
    header = "ファイル名".ljust(32) + " | " + " | ".join(f"col{i}" for i in CANDIDATE_INDICES)
    print(header)
    print("-" * 70)

    for path in files:
        base = os.path.basename(path)
        vals = get_first_feature_vals(path)
        if vals is None:
            print(f"{base[:32]:<32} | (取得失敗)")
            continue
        parts = []
        for idx in CANDIDATE_INDICES:
            v = vals[idx] if idx < len(vals) else "-"
            if v.isdigit() and 1 <= int(v) <= 19:
                v = f"{v}[候補]"
            parts.append(v.ljust(10))
        print(f"{base[:32]:<32} | " + " | ".join(parts))

    print("-" * 70)
    print("地域が違うファイルで値が変わる列が 座標系 の可能性が高いです。", file=sys.stderr)
    print("測地系は多くのファイルで 2 のままです。", file=sys.stderr)


def run_diverse_sample(gpkgs, per_group=2):
    """命名規則（プレフィックス）が異なるグループからそれぞれサンプルを取って比較。スキーマ差の有無を確認。"""
    groups = {}
    for path in gpkgs:
        base = os.path.basename(path)
        prefix = filename_prefix(base)
        groups.setdefault(prefix, []).append(path)
    # 各グループから最大 per_group 件を選ぶ（先頭でよい）
    selected = []
    for prefix in sorted(groups.keys()):
        selected.extend(groups[prefix][:per_group])
    selected.sort()
    print(f"=== 命名規則別サンプル比較（プレフィックスごと最大 {per_group} 件、候補列: col{CANDIDATE_INDICES}）", file=sys.stderr)
    print(f"    検出したプレフィックス: {', '.join(sorted(groups.keys()))}", file=sys.stderr)
    print("-" * 80)
    header = "プレフィックス".ljust(12) + " | " + "ファイル名".ljust(28) + " | " + " | ".join(f"col{i}" for i in CANDIDATE_INDICES)
    print(header)
    print("-" * 80)

    for path in selected:
        base = os.path.basename(path)
        prefix = filename_prefix(base)
        vals = get_first_feature_vals(path)
        if vals is None:
            print(f"{prefix:<12} | {base[:28]:<28} | (取得失敗)")
            continue
        parts = []
        for idx in CANDIDATE_INDICES:
            v = vals[idx] if idx < len(vals) else "-"
            if v.isdigit() and 1 <= int(v) <= 19:
                v = f"{v}[候補]"
            parts.append(v.ljust(10))
        print(f"{prefix:<12} | {base[:28]:<28} | " + " | ".join(parts))

    print("-" * 80)
    print("プレフィックスが違っても col5/col2 の位置と値の意味が同じならスキーマは揃っています。", file=sys.stderr)


def main():
    path = None
    out_file = None
    n_samples = None
    diverse = None
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] in ("-n", "--samples") and i + 1 < len(args):
            try:
                n_samples = int(args[i + 1])
            except ValueError:
                n_samples = 10
            i += 2
        elif args[i] in ("-d", "--diverse"):
            diverse = 2
            if i + 1 < len(args) and args[i + 1].isdigit():
                diverse = int(args[i + 1])
                i += 1
            i += 1
        elif args[i] == "-o" and i + 1 < len(args):
            out_file = args[i + 1]
            i += 2
        elif path is None and not args[i].startswith("-"):
            path = args[i]
            i += 1
        else:
            i += 1

    if path and not os.path.isabs(path):
        path = os.path.join(PROJECT_ROOT, path)

    gpkgs = []
    if os.path.isdir(TOCHI_DIR):
        gpkgs = sorted(
            os.path.join(TOCHI_DIR, f)
            for f in os.listdir(TOCHI_DIR)
            if f.lower().endswith(".gpkg")
        )
    if not path and gpkgs:
        path = gpkgs[0]

    # 命名規則別サンプル比較モード（-d / --diverse）
    if diverse is not None and gpkgs:
        run_diverse_sample(gpkgs, per_group=diverse)
        return

    # 複数サンプル比較モード（-n N）
    if n_samples is not None and n_samples > 1 and gpkgs:
        run_multi_sample(gpkgs, min(n_samples, len(gpkgs)))
        return

    if not path or not os.path.isfile(path):
        print("Error: no .gpkg file found. Specify path or run csv_to_geopackage.sh first.", file=sys.stderr)
        sys.exit(1)

    print(f"=== 検証対象: {path}", file=sys.stderr)
    print(f"=== PROJECT_ROOT: {PROJECT_ROOT}", file=sys.stderr)

    out = subprocess.run(
        ["ogrinfo", "-al", path],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
        cwd=PROJECT_ROOT,
    )
    txt = (out.stdout or "") + (out.stderr or "")

    if out_file:
        with open(out_file, "w", encoding="utf-8") as f:
            f.write(txt)
        print(f"--- ogrinfo 生出力を保存: {out_file}", file=sys.stderr)

    feature_block = re.search(r"OGRFeature\([^)]+\):\d+\s*\n(.*?)(?=OGRFeature\(|\Z)", txt, re.DOTALL)
    if not feature_block:
        print("--- OGRFeature が見つかりません", file=sys.stderr)
        print(txt[:3000])
        return

    block = feature_block.group(1)
    attr_names = []
    attr_vals = []
    for line in block.splitlines():
        m = re.match(r"\s*(.+?)\s*\([^)]+\)\s*=\s*(.*)$", line)
        if m:
            attr_names.append(m.group(1).strip())
            attr_vals.append(m.group(2).strip())

    schema_fields = re.findall(r"Field\s+(\d+):\s*([^\s(]+)", txt)
    if schema_fields:
        print("\n--- スキーマ (Field 番号: 名前)", file=sys.stderr)
        for idx, name in schema_fields[:25]:
            print(f"  Field {idx}: {name}", file=sys.stderr)

    print("\n--- 先頭レコードの属性一覧（値が 1～19 のものは [座標系候補] と表示）", file=sys.stderr)
    print("-" * 80)
    print(f"{'idx':>4} | {'属性名':<25} | 値")
    print("-" * 80)

    for i in range(len(attr_names)):
        name = attr_names[i] if i < len(attr_names) else "(unknown)"
        val = attr_vals[i] if i < len(attr_vals) else ""
        mark = " [座標系候補]" if val.isdigit() and 1 <= int(val) <= 19 else ""
        print(f"{i:>4} | {name[:25]:<25} | {val}{mark}")
    print("-" * 80)
    print("\n上記のうち、平面直角の「系」(1～19) は 座標系 列です。", file=sys.stderr)
    print("複数サンプル比較: python3 scripts/verify_tochi_attributes.py -n 20", file=sys.stderr)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# Parquet の中身（スキーマ・件数・先頭数行）を表示する。
# 使い方: python3 scripts/peek_parquet.py <file.parquet>

import subprocess
import sys
import os

def main():
    if len(sys.argv) < 2:
        print("Usage: peek_parquet.py <file.parquet>", file=sys.stderr)
        sys.exit(1)
    path = os.path.abspath(sys.argv[1])
    if not os.path.isfile(path):
        print(f"Not found: {path}", file=sys.stderr)
        sys.exit(1)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    out = subprocess.run(
        ["ogrinfo", "-so", "-al", path],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
        cwd=project_root,
    )
    if out.returncode != 0:
        print("ogrinfo failed (is env.sh sourced?)", file=sys.stderr)
        sys.exit(1)
    print("=== レイヤ概要 (-so -al) ===")
    print(out.stdout)

    out2 = subprocess.run(
        ["ogrinfo", "-al", path],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
        cwd=project_root,
    )
    if out2.returncode == 0:
        lines = out2.stdout.splitlines()
        # 先頭2件分のフィーチャ程度（1件あたり約20行想定）
        head = "\n".join(lines[:120])
        print("=== 先頭のフィーチャ（抜粋） ===")
        print(head)
        if len(lines) > 120:
            print(f"\n... 他 {len(lines)-120} 行")

if __name__ == "__main__":
    main()

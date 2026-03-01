#!/usr/bin/env python3
# Parquet の先頭5レコードを表示。ogrinfo または pyarrow を使用。
import os
import subprocess
import sys

def via_ogrinfo(path, project_root):
    out = subprocess.run(
        ["ogrinfo", "-al", path],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
        cwd=project_root,
    )
    if out.returncode != 0:
        return None
    lines = out.stdout.splitlines()
    result = []
    current = []
    for line in lines:
        if line.strip().startswith("OGRFeature("):
            if current:
                result.append(current)
                if len(result) >= 5:
                    break
            current = [line]
        else:
            current.append(line)
    if current:
        result.append(current)
    return result[:5]

def main():
    if len(sys.argv) < 2:
        print("Usage: parquet_sample5.py <file.parquet>", file=sys.stderr)
        sys.exit(1)
    path = os.path.abspath(sys.argv[1])
    if not os.path.isfile(path):
        print(f"Not found: {path}", file=sys.stderr)
        sys.exit(1)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)

    # pyarrow があれば表形式で5行
    try:
        import pyarrow.parquet as pq
        t = pq.read_table(path)
        df = t.to_pandas() if hasattr(t, "to_pandas") else None
        if df is not None:
            print("=== 先頭5レコード (pyarrow) ===\n")
            print(df.head(5).to_string())
            return
    except Exception:
        pass

    # ogrinfo で5件分のブロックを取得
    blocks = via_ogrinfo(path, project_root)
    if not blocks:
        print("ogrinfo の実行に失敗しました。source env.sh してから実行してください。", file=sys.stderr)
        sys.exit(1)
    print("=== 先頭5レコード (ogrinfo) ===\n")
    for i, block in enumerate(blocks, 1):
        print(f"--- レコード {i} ---")
        print("\n".join(block))
        print()

if __name__ == "__main__":
    main()

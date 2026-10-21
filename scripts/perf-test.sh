#!/usr/bin/env bash
# Benchmark macrename preview + rename on a configurable number of files.
# Usage: ./scripts/perf-test.sh [count]    (default: 10000)
set -euo pipefail

cd "$(dirname "$0")/.."

N="${1:-10000}"

echo "Building release binary..."
swift build -c release --product macrename >/dev/null 2>&1
CLI="$(pwd)/.build/release/macrename"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Creating $N files in $tmp ..."
/usr/bin/python3 -c "
import os, sys
tmp, n = sys.argv[1], int(sys.argv[2])
for i in range(n):
    open(os.path.join(tmp, f'file-{i:06d}.txt'), 'w').close()
" "$tmp" "$N"

echo
echo "── preview ($N files) ──"
/usr/bin/time -p "$CLI" preview -s 'file' -r 'renamed' "$tmp" >/dev/null

echo
echo "── rename ($N files) ──"
/usr/bin/time -p "$CLI" rename -s 'file' -r 'renamed' "$tmp" >/dev/null

echo
echo "── rollback rename ──"
/usr/bin/time -p "$CLI" rename -s 'renamed' -r 'file' "$tmp" >/dev/null

echo
echo "Report 'real' as wall-clock seconds."

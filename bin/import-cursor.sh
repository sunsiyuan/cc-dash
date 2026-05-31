#!/usr/bin/env bash
# Stage a Cursor usage CSV at data/cursor/usage.csv (the path the dashboard reads).
#
# Cursor's web export is named cursor-usage-events-<YYYY-MM-DD>.csv. Drop a fresh
# export anywhere; this script archives the previous one and replaces it.
#
# Usage:
#   bin/import-cursor.sh ~/Downloads/cursor-usage-events-2026-05-01.csv

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

src="${1:-}"
if [[ -z "$src" || ! -f "$src" ]]; then
  echo "usage: $0 <path-to-cursor-usage-events-*.csv>" >&2
  exit 1
fi

mkdir -p data/cursor
# Keep the dated original as an archive (gitignored), then point usage.csv at the new one.
cp "$src" "data/cursor/$(basename "$src")"
cp "$src" "data/cursor/usage.csv"
echo "✓ data/cursor/$(basename "$src") archived"
echo "✓ data/cursor/usage.csv now points to this export"
python3 bin/lib/build-manifest.py

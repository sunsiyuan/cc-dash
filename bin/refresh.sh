#!/usr/bin/env bash
# Regenerate the three ccusage JSON reports for a given month.
#
# Usage:
#   bin/refresh.sh                # current month
#   bin/refresh.sh 2026-04        # specific month
#   bin/refresh.sh 2026-04 prev   # previous month relative to today (ignores arg 1)
#   bin/refresh.sh all            # full history (no --since/--until)
#
# Output: data/<YYYY-MM>/{daily,monthly,session}.json
# Also updates data/latest -> <YYYY-MM> symlink.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "${1:-}" == "all" ]]; then
  MONTH="all"
  SINCE=""
  UNTIL=""
elif [[ "${1:-}" == "prev" ]]; then
  # First day of previous month, BSD date (macOS)
  MONTH=$(date -v-1m +%Y-%m)
  SINCE=$(date -v-1m -v1d +%Y%m%d)
  UNTIL=$(date -v1d -v-1d +%Y%m%d)  # last day of previous month
elif [[ -n "${1:-}" ]]; then
  MONTH="$1"
  if [[ ! "$MONTH" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
    echo "month must be YYYY-MM (got: $MONTH)" >&2
    exit 1
  fi
  YEAR="${MONTH%-*}"
  MO="${MONTH#*-}"
  SINCE="${YEAR}${MO}01"
  # Last day of that month — pad to 31, ccusage tolerates over-shoot
  UNTIL="${YEAR}${MO}31"
else
  MONTH=$(date +%Y-%m)
  SINCE="$(date +%Y%m)01"
  UNTIL="$(date +%Y%m)31"
fi

OUT="data/$MONTH"
mkdir -p "$OUT"

run() {
  local cmd="$1"
  local file="$2"
  if [[ -z "$SINCE" ]]; then
    echo "→ ccusage $cmd --json > $file"
    npx -y ccusage@latest "$cmd" --json > "$file"
  else
    echo "→ ccusage $cmd --since $SINCE --until $UNTIL --json > $file"
    npx -y ccusage@latest "$cmd" --since "$SINCE" --until "$UNTIL" --json > "$file"
  fi
}

run daily   "$OUT/daily.json"
run monthly "$OUT/monthly.json"
run session "$OUT/session.json"

# Refresh the "latest" pointer so the dashboard's one-click load finds it.
ln -sfn "$MONTH" data/latest

# Maintain data/index.json so the dashboard's bundled-month dropdown can
# discover what's available without listing the directory (browsers can't).
python3 - "$MONTH" <<'PY'
import json, os, sys
month = sys.argv[1]
months = sorted([
    d for d in os.listdir("data")
    if os.path.isdir(os.path.join("data", d)) and len(d) == 7 and d[4] == "-"
])
with open("data/index.json", "w") as f:
    json.dump({"months": months, "latest": month}, f, indent=2)
PY

echo "✓ wrote $OUT/{daily,monthly,session}.json"
echo "✓ data/latest -> $MONTH"
echo "✓ data/index.json updated"

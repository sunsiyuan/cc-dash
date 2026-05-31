#!/usr/bin/env bash
# Regenerate the three ccusage JSON reports for Claude Code (the "direct"
# channel — your local machine) for a given month.
#
# Usage:
#   bin/import-claude.sh                # current month
#   bin/import-claude.sh 2026-04        # specific month
#   bin/import-claude.sh prev           # previous month relative to today
#   bin/import-claude.sh all            # full history (no --since/--until)
#
# Output: data/claude/direct/<YYYY-MM>/{daily,monthly,session}.json
# The "relay" channel (data/claude/relay/<month>/) is the same shape from a CC
# routing/relay provider; drop those in manually — this script only does direct.
# Refreshes data/manifest.json afterward.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "${1:-}" == "all" ]]; then
  MONTH="all"; SINCE=""; UNTIL=""
elif [[ "${1:-}" == "prev" ]]; then
  MONTH=$(date -v-1m +%Y-%m)
  SINCE=$(date -v-1m -v1d +%Y%m%d)
  UNTIL=$(date -v1d -v-1d +%Y%m%d)  # last day of previous month
elif [[ -n "${1:-}" ]]; then
  MONTH="$1"
  if [[ ! "$MONTH" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
    echo "month must be YYYY-MM (got: $MONTH)" >&2
    exit 1
  fi
  YEAR="${MONTH%-*}"; MO="${MONTH#*-}"
  SINCE="${YEAR}${MO}01"
  UNTIL="${YEAR}${MO}31"   # over-shoot; ccusage tolerates it
else
  MONTH=$(date +%Y-%m)
  SINCE="$(date +%Y%m)01"
  UNTIL="$(date +%Y%m)31"
fi

OUT="data/claude/direct/$MONTH"
mkdir -p "$OUT"

run() {
  local cmd="$1" file="$2"
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

echo "✓ wrote $OUT/{daily,monthly,session}.json"
python3 bin/lib/build-manifest.py

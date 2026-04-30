#!/usr/bin/env bash
# Invoked by ~/Library/LaunchAgents/com.siyuansun.cc-dash.refresh.plist on
# the 1st of each month. Refreshes the previous month's ccusage JSONs and
# commits the resulting data/index.json bump if anything changed.
#
# Run manually any time:
#   ~/utils/cc-dash/bin/refresh-and-commit.sh
#
# Logs go to data/refresh.log (gitignored).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# launchd starts jobs with a minimal PATH; make node/npx (Homebrew) and git
# reachable explicitly so this works the same under launchd and in a shell.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ts() { date "+%Y-%m-%dT%H:%M:%S%z"; }
echo "[$(ts)] cc-dash refresh starting (uid=$(id -u))"

bin/refresh.sh prev

# data/<month>/ JSONs are gitignored; only data/index.json is tracked, so
# that's the audit-trail file we commit when its contents change.
if [[ -n "$(git status --porcelain data/index.json 2>/dev/null)" ]]; then
  month="$(python3 -c 'import json; print(json.load(open("data/index.json"))["latest"])')"
  git add data/index.json
  git -c user.name="cc-dash refresh" \
      -c user.email="cc-dash-refresh@local" \
      commit -m "refresh: $month" >/dev/null
  echo "[$(ts)] committed refresh: $month"
else
  echo "[$(ts)] index unchanged — nothing to commit"
fi
echo "[$(ts)] cc-dash refresh done"

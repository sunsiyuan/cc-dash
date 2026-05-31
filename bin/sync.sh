#!/usr/bin/env bash
# Invoked by ~/Library/LaunchAgents/com.siyuansun.cc-dash.refresh.plist on the
# 1st of each month. Refreshes the previous month for every source that can run
# unattended (local, no expiring credentials), then commits the manifest bump.
#
# Runs:
#   - import-claude.sh prev   (ccusage, local)
#   - import-codex.sh  prev   (~/.codex session logs, local)
# Skips: import-codex-cloud.sh (needs a short-lived web Bearer/cookie — can't be
# automated reliably) and import-cursor.sh (manual CSV export). Run those by hand.
#
# Run manually any time:  ~/utils/cc-dash/bin/sync.sh
# Logs go to data/logs/refresh.log (gitignored).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# launchd starts jobs with a minimal PATH; make node/npx (Homebrew) and git
# reachable explicitly so this works the same under launchd and in a shell.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ts() { date "+%Y-%m-%dT%H:%M:%S%z"; }
echo "[$(ts)] cc-dash sync starting (uid=$(id -u))"

bin/import-claude.sh prev
bin/import-codex.sh  prev || echo "[$(ts)] codex import skipped/failed (non-fatal)"

# data/* payloads are gitignored; only data/manifest.json is tracked, so that's
# the audit-trail file we commit when its contents change.
if [[ -n "$(git status --porcelain data/manifest.json 2>/dev/null)" ]]; then
  latest="$(python3 -c 'import json; print(json.load(open("data/manifest.json")).get("latest"))')"
  git add data/manifest.json
  git -c user.name="cc-dash sync" \
      -c user.email="cc-dash-sync@local" \
      commit -m "sync: $latest" >/dev/null
  echo "[$(ts)] committed sync: $latest"
else
  echo "[$(ts)] manifest unchanged — nothing to commit"
fi
echo "[$(ts)] cc-dash sync done"

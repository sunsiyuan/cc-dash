#!/usr/bin/env bash
# Serve the dashboard locally so the browser can fetch ./data/*.json.
# Browsers block fetch() from file:// URLs, so this is the easiest way
# to make the "Load bundled data" button work.
#
# Usage:
#   bin/serve.sh           # port 8765
#   bin/serve.sh 9000      # custom port

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PORT="${1:-8765}"
URL="http://localhost:$PORT/dashboard.html"

echo "Serving $ROOT at $URL"
echo "Ctrl-C to stop."

# Open the browser shortly after the server starts (best-effort).
( sleep 0.6 && open "$URL" >/dev/null 2>&1 || true ) &

exec python3 -m http.server "$PORT" --bind 127.0.0.1

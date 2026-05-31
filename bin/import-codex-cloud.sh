#!/usr/bin/env bash
# Pull Codex *cloud* usage from the ChatGPT web backend (the data behind
# chatgpt.com/codex/cloud/settings/analytics) for a month, and aggregate it.
#
# This covers the surfaces the local CLI logs can't see — GitHub Code Review,
# Exec, Desktop App — plus a per-model credit split and code-review metrics.
#
# UNOFFICIAL: there is no public API for personal accounts. This reuses your
# logged-in ChatGPT credentials (a Bearer token + cookies) exactly as the web
# dashboard does. Credentials are short-lived; when they expire you'll get a
# 401/403 and must refresh them (see data/codex/cloud/.auth.sh.example).
#
# Values are OpenAI "credits" rendered as a PERCENT of your plan window
# (the response says "units": "percent") — a usage *distribution*, NOT tokens
# or dollars. The CLI-token importer (bin/import-codex.sh) is what gives you
# absolute tokens + equivalent $; this one tells you how that splits by surface.
#
# Setup (once):
#   cp data/codex/cloud/.auth.sh.example data/codex/cloud/.auth.sh
#   # then paste your Bearer + cookie into it (from a browser DevTools "Copy as cURL")
#
# Usage:
#   bin/import-codex-cloud.sh            # previous month
#   bin/import-codex-cloud.sh 2026-05    # specific month
#
# Output: data/codex/cloud/<YYYY-MM>.json  (+ raw responses under raw/)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# CODEX_CLOUD_SKIP_FETCH=1 parses whatever raw responses already exist under
# data/codex/cloud/raw/ without hitting the network (useful for re-parsing a
# manually-saved capture, or when your credentials have expired).
AUTH="data/codex/cloud/.auth.sh"
if [[ "${CODEX_CLOUD_SKIP_FETCH:-}" != "1" ]]; then
  if [[ ! -f "$AUTH" ]]; then
    echo "missing $AUTH — copy data/codex/cloud/.auth.sh.example and fill in your Bearer + cookie" >&2
    echo "  (or re-run with CODEX_CLOUD_SKIP_FETCH=1 to parse already-saved raw/ captures)" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$AUTH"
  : "${CODEX_CLOUD_BEARER:?set CODEX_CLOUD_BEARER in $AUTH}"
  : "${CODEX_CLOUD_COOKIE:?set CODEX_CLOUD_COOKIE in $AUTH}"
fi

MONTH="${1:-$(date -v-1m +%Y-%m)}"
if [[ ! "$MONTH" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
  echo "month must be YYYY-MM (got: $MONTH)" >&2
  exit 1
fi
START="${MONTH}-01"
# Last day of the month: first day of next month, minus one day (BSD date).
END="$(date -v"${MONTH}-01" -v+1m -v-1d +%Y-%m-%d 2>/dev/null || true)"
if [[ -z "$END" ]]; then
  # Fallback if the -v parse above is fussy about the day token.
  END="$(date -j -f %Y-%m-%d "${START}" -v+1m -v-1d +%Y-%m-%d)"
fi

RAW="data/codex/cloud/raw"
mkdir -p "$RAW"

BASE="https://chatgpt.com/backend-api/wham"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"

# fetch <name> <path> <extra-query>
fetch() {
  local name="$1" path="$2" extra="${3:-}"
  local url="${BASE}${path}?start_date=${START}&end_date=${END}&group_by=day${extra}"
  local out="$RAW/${name}-${MONTH}.json"
  local code
  code=$(curl -sS -o "$out" -w '%{http_code}' "$url" \
    -H "authorization: Bearer ${CODEX_CLOUD_BEARER}" \
    -H "cookie: ${CODEX_CLOUD_COOKIE}" \
    -H "accept: */*" \
    -H "user-agent: ${UA}" \
    -H "referer: https://chatgpt.com/codex/cloud/settings/analytics" \
    -H "oai-language: en-US" \
    -H "x-openai-target-path: ${path}" \
    -H "x-openai-target-route: ${path}") || { echo "curl failed for $name" >&2; return 1; }
  if [[ "$code" != "200" ]]; then
    echo "✗ $name: HTTP $code" >&2
    if [[ "$code" == "401" || "$code" == "403" ]]; then
      echo "  → credentials expired; refresh $AUTH (re-copy Bearer + cookie from the browser)" >&2
    fi
    head -c 300 "$out" >&2; echo >&2
    return 1
  fi
  echo "✓ fetched $name ($code) -> $out"
}

if [[ "${CODEX_CLOUD_SKIP_FETCH:-}" != "1" ]]; then
  fetch usage        "/usage/daily-token-usage-breakdown"        || exit 1
  fetch code_reviews "/analytics/daily-code-review-metrics"      || true
  fetch skills       "/analytics/daily-skill-usage-metrics"      "&workspace_user=true&top_skill_limit=10" || true
else
  echo "(skip-fetch) parsing existing raw/ captures for $MONTH"
fi

python3 - "$MONTH" "$RAW" <<'PY'
import json, os, sys, collections
month, raw = sys.argv[1], sys.argv[2]

def load(name):
    p = os.path.join(raw, f"{name}-{month}.json")
    if not os.path.exists(p):
        return None
    try:
        return json.load(open(p))
    except Exception:
        return None

usage = load("usage")
reviews = load("code_reviews")

out = {"month": month, "source": "codex-cloud",
       "note": "Unofficial pull of the ChatGPT Codex usage dashboard. Values are credits as a percent of plan window (a distribution), not tokens/$."}

if usage and usage.get("data"):
    surf = collections.defaultdict(float)
    models = collections.defaultdict(float)
    daily = []
    for row in usage["data"]:
        sv = row.get("product_surface_usage_values", {}) or {}
        for k, v in sv.items():
            surf[k] += v
        for m in row.get("models", []) or []:
            models[m.get("model", "unknown")] += m.get("credits", 0.0)
        day_total = sum(sv.values())
        daily.append({"date": row.get("date"), "total": round(day_total, 4),
                      "surfaces": {k: round(v, 4) for k, v in sv.items() if v}})
    grand = sum(surf.values()) or 1.0
    out["units"] = usage.get("units", "percent")
    out["surface_totals"] = {k: round(v, 4) for k, v in
                             sorted(surf.items(), key=lambda x: -x[1]) if v}
    out["surface_share_pct"] = {k: round(v / grand * 100, 1) for k, v in
                                sorted(surf.items(), key=lambda x: -x[1]) if v}
    out["model_totals"] = {k: round(v, 4) for k, v in
                           sorted(models.items(), key=lambda x: -x[1]) if v}
    out["daily"] = daily

if reviews and reviews.get("data"):
    r = reviews["data"]
    out["code_review"] = {
        "active_days": len(r),
        "n_reviews": sum(x.get("n_reviews", 0) for x in r),
        "n_comments": sum(x.get("n_comments", 0) for x in r),
        "n_comments_p0": sum(x.get("n_comments_p0", 0) for x in r),
        "n_comments_p1": sum(x.get("n_comments_p1", 0) for x in r),
        "n_comments_p2": sum(x.get("n_comments_p2", 0) for x in r),
        "n_replies": sum(x.get("n_replies", 0) for x in r),
    }

os.makedirs(os.path.join("data", "codex", "cloud"), exist_ok=True)
dest = os.path.join("data", "codex", "cloud", f"{month}.json")
json.dump(out, open(dest, "w"), indent=2)

# Console summary.
print(f"\n== Codex cloud {month} ==")
if "surface_share_pct" in out:
    print("surface share (% of all credits this month):")
    for k, v in out["surface_share_pct"].items():
        print(f"  {k:<20} {v:>5}%   (raw {out['surface_totals'][k]})")
if "model_totals" in out:
    print("by model (raw credit-percent):")
    for k, v in out["model_totals"].items():
        print(f"  {k:<16} {v}")
if "code_review" in out:
    cr = out["code_review"]
    print(f"code review: {cr['n_reviews']} PRs reviewed, {cr['n_comments']} comments "
          f"(P0={cr['n_comments_p0']} P1={cr['n_comments_p1']} P2={cr['n_comments_p2']}), "
          f"{cr['n_replies']} replies over {cr['active_days']} active days")
print(f"\n✓ wrote {dest}")
PY

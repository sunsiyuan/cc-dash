#!/usr/bin/env bash
# Aggregate OpenAI Codex CLI usage from local session rollout logs into the
# dashboard's data/ tree, pricing each model from a configurable table.
#
# Source: $CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl (default ~/.codex).
# Each session's *last* `token_count` event carries `total_token_usage`
# (cumulative for that session); we take that plus the session's dominant
# model, attribute it to the session's start date, and aggregate per day/month.
#
# IMPORTANT — this only covers the *CLI* surface. Codex cloud surfaces
# (GitHub Code Review, Exec, Desktop App) run in OpenAI's cloud and write
# nothing local, so they are NOT counted here. See README "Codex" section.
#
# Cost is an *equivalent API cost* (what these tokens would cost at OpenAI's
# pay-per-token API rates) — NOT your real bill, since Codex via a ChatGPT
# subscription is flat-rate. Prices live in config/codex-pricing.json (auto-
# seeded on first run); edit that file to correct/extend per-model rates.
#
# Usage:
#   bin/import-codex.sh                # previous month (launchd-friendly default)
#   bin/import-codex.sh 2026-05        # specific month
#   bin/import-codex.sh prev           # previous month relative to today
#   bin/import-codex.sh all            # every month found
#
# Output: data/codex/cli/<YYYY-MM>/{daily,monthly}.json  (refreshes data/manifest.json)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
SESS_DIR="$CODEX_HOME/sessions"
PRICING="config/codex-pricing.json"

if [[ ! -d "$SESS_DIR" ]]; then
  echo "no Codex session dir at $SESS_DIR (set CODEX_HOME?)" >&2
  exit 1
fi

# Resolve which month(s) to build.
case "${1:-prev}" in
  all)  TARGET="all" ;;
  prev) TARGET="$(date -v-1m +%Y-%m)" ;;
  "")   TARGET="$(date -v-1m +%Y-%m)" ;;
  *)
    if [[ ! "$1" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
      echo "month must be YYYY-MM, 'prev', or 'all' (got: $1)" >&2
      exit 1
    fi
    TARGET="$1" ;;
esac

mkdir -p data/codex/cli config

# Seed a default pricing table (USD per 1M tokens) on first run. Edit freely;
# subsequent runs read whatever is here. Rates below are OpenAI's published
# gpt-5.5 API pricing (input $5 / cached input $0.50 / output $30) as of
# 2026-06; other models are best-effort placeholders — correct as needed.
if [[ ! -f "$PRICING" ]]; then
  cat > "$PRICING" <<'JSON'
{
  "_comment": "USD per 1,000,000 tokens. uncached_input = input - cached_input. output includes reasoning tokens. Unknown models are counted but left uncosted (listed under unpriced_models in the output).",
  "_source": "https://developers.openai.com/api/docs/models/gpt-5.5 (gpt-5.5, 2026-06)",
  "models": {
    "gpt-5.5":        { "input": 5.00, "cached_input": 0.50, "output": 30.00 },
    "gpt-5.5-codex":  { "input": 5.00, "cached_input": 0.50, "output": 30.00 },
    "gpt-5":          { "input": 1.25, "cached_input": 0.125, "output": 10.00 },
    "gpt-5-codex":    { "input": 1.25, "cached_input": 0.125, "output": 10.00 },
    "gpt-5.1":        { "input": 1.25, "cached_input": 0.125, "output": 10.00 },
    "o3":             { "input": 2.00, "cached_input": 0.50, "output": 8.00 },
    "o4-mini":        { "input": 1.10, "cached_input": 0.275, "output": 4.40 }
  }
}
JSON
  echo "✓ seeded $PRICING (edit to adjust per-model rates)"
fi

python3 - "$SESS_DIR" "$PRICING" "$TARGET" <<'PY'
import json, os, sys, glob, re, collections

sess_dir, pricing_path, target = sys.argv[1], sys.argv[2], sys.argv[3]
prices = json.load(open(pricing_path)).get("models", {})

def session_summary(path):
    """Return (last cumulative total_token_usage dict, dominant model) or None."""
    last, models = None, collections.Counter()
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if '"model"' in line:
                m = re.search(r'"model":\s*"([^"]+)"', line)
                if m:
                    models[m.group(1)] += 1
            if '"total_token_usage"' in line:
                try:
                    last = json.loads(line)["payload"]["info"]["total_token_usage"]
                except Exception:
                    pass
    if not last:
        return None
    model = models.most_common(1)[0][0] if models else "unknown"
    return last, model

def month_of(path):
    # .../sessions/YYYY/MM/DD/rollout-*.jsonl  ->  YYYY-MM , YYYY-MM-DD
    parts = path.split(os.sep)
    try:
        i = parts.index("sessions")
        y, mo, d = parts[i+1], parts[i+2], parts[i+3]
        return f"{y}-{mo}", f"{y}-{mo}-{d}"
    except (ValueError, IndexError):
        return None, None

# Bucket sessions by month -> date -> model, accumulating token fields.
def zero():
    return dict(sessions=0, uncached_input=0, cached_input=0, output=0)

months = collections.defaultdict(lambda: collections.defaultdict(
    lambda: collections.defaultdict(zero)))

for path in glob.glob(os.path.join(sess_dir, "*/*/*/*.jsonl")):
    ym, ymd = month_of(path)
    if ym is None:
        continue
    if target != "all" and ym != target:
        continue
    s = session_summary(path)
    if s is None:
        continue
    usage, model = s
    inp = usage.get("input_tokens", 0)
    cached = usage.get("cached_input_tokens", 0)
    out = usage.get("output_tokens", 0)  # already includes reasoning_output_tokens
    b = months[ym][ymd][model]
    b["sessions"] += 1
    b["uncached_input"] += max(inp - cached, 0)
    b["cached_input"] += cached
    b["output"] += out

def cost_of(model, b):
    p = prices.get(model)
    if not p:
        return None
    return round(
        b["uncached_input"] / 1e6 * p["input"]
        + b["cached_input"] / 1e6 * p["cached_input"]
        + b["output"] / 1e6 * p["output"], 4)

built = []
for ym in sorted(months):
    days = months[ym]
    daily_rows, mtot, by_model, unpriced = [], zero(), collections.defaultdict(zero), set()
    mtot["cost_usd"] = 0.0
    mtot["cost_partial"] = False

    for ymd in sorted(days):
        drow = dict(date=ymd, **zero())
        drow["cost_usd"] = 0.0
        drow_models = {}
        for model, b in days[ymd].items():
            c = cost_of(model, b)
            for k in ("sessions", "uncached_input", "cached_input", "output"):
                drow[k] += b[k]; mtot[k] += b[k]; by_model[model][k] += b[k]
            drow_models[model] = dict(b, cost_usd=c)
            if c is None:
                unpriced.add(model); drow["cost_partial"] = True; mtot["cost_partial"] = True
            else:
                drow["cost_usd"] += c; mtot["cost_usd"] += c
        drow["input"] = drow["uncached_input"] + drow["cached_input"]
        drow["total"] = drow["input"] + drow["output"]
        drow["cost_usd"] = round(drow["cost_usd"], 4)
        drow["by_model"] = drow_models
        daily_rows.append(drow)

    mtot["input"] = mtot["uncached_input"] + mtot["cached_input"]
    mtot["total"] = mtot["input"] + mtot["output"]
    mtot["cost_usd"] = round(mtot["cost_usd"], 4)
    mtot["cache_hit_pct"] = round(mtot["cached_input"] / mtot["input"] * 100, 1) if mtot["input"] else 0.0

    model_rows = []
    for model in sorted(by_model, key=lambda m: -(by_model[m]["uncached_input"] + by_model[m]["output"])):
        b = by_model[model]
        model_rows.append(dict(model=model, **b, input=b["uncached_input"] + b["cached_input"],
                               total=b["uncached_input"] + b["cached_input"] + b["output"],
                               cost_usd=cost_of(model, b)))

    out_dir = os.path.join("data", "codex", "cli", ym)
    os.makedirs(out_dir, exist_ok=True)
    monthly = dict(month=ym, source="codex-cli", note="CLI surface only; cloud (Code Review/Exec/Desktop) not included. cost_usd is equivalent API cost, not actual subscription billing.",
                   pricing_source=pricing_path, totals=mtot,
                   unpriced_models=sorted(unpriced), by_model=model_rows)
    json.dump(monthly, open(os.path.join(out_dir, "monthly.json"), "w"), indent=2)
    json.dump(dict(month=ym, source="codex-cli", daily=daily_rows),
              open(os.path.join(out_dir, "daily.json"), "w"), indent=2)
    built.append((ym, mtot, sorted(unpriced)))

if not built:
    print(f"no Codex sessions found for target '{target}'")
    sys.exit(0)

for ym, t, unpriced in built:
    warn = f"  (unpriced: {', '.join(unpriced)})" if unpriced else ""
    star = "~" if t["cost_partial"] else ""
    print(f"✓ {ym}: {t['sessions']} sessions  total={t['total']:,}  "
          f"hit={t['cache_hit_pct']}%  cost={star}${t['cost_usd']:.2f}{warn}")

PY

python3 bin/lib/build-manifest.py

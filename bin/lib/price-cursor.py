#!/usr/bin/env python3
# Price Cursor usage events at official per-model API rates to get an
# *equivalent API cost* (Cursor bills via subscription, so its CSV says
# "Included"; this answers "what would this usage cost on the providers' APIs").
#
# Reads data/cursor/usage.csv + config/cursor-pricing.json, writes one
# data/cursor/<YYYY-MM>.json per month present, and prints a summary.
#
# Cursor CSV token columns (verified):
#   Total = Input(w/ Cache Write) + Input(w/o Cache Write) + Cache Read + Output
#   Input (w/ Cache Write)  -> cache_write  (cache-creation tokens)
#   Input (w/o Cache Write) -> input        (uncached input)
#   Cache Read              -> cache_read
#   Output Tokens           -> output

import csv, json, os, sys, collections

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CSV = os.path.join(ROOT, "data", "cursor", "usage.csv")
PRICING = os.path.join(ROOT, "config", "cursor-pricing.json")

# Effort / reasoning suffixes Cursor appends to model names — strip to get the base.
EFFORT = {"high", "medium", "low", "none", "minimal", "xhigh", "thinking"}
# Provider-naming reshuffles → canonical pricing key (after effort stripping).
ALIAS = {
    "claude-4.6-sonnet": "claude-sonnet-4-6",
    "claude-4.5-sonnet": "claude-sonnet-4-5",
    "claude-4-sonnet": "claude-sonnet-4",
    "claude-4.6-opus": "claude-opus-4-6",
    "claude-4.5-opus": "claude-opus-4-5",
    "composer-2.5": "composer",
    "composer-2-fast": "composer",
}


def normalize(model):
    parts = model.split("-")
    while parts and parts[-1] in EFFORT:
        parts.pop()
    base = "-".join(parts)
    return ALIAS.get(base, base)


def cell(x):
    x = (x or "").strip()
    return int(x) if x.lstrip("-").isdigit() else 0


prices = json.load(open(PRICING))["models"]
rows = list(csv.DictReader(open(CSV)))


def zero():
    return dict(events=0, cache_write=0, input=0, cache_read=0, output=0)


# month -> model -> token buckets
months = collections.defaultdict(lambda: collections.defaultdict(zero))
for r in rows:
    month = (r.get("Date") or "")[:7]
    if len(month) != 7 or month[4] != "-":
        continue
    model = normalize(r.get("Model", "unknown"))
    b = months[month][model]
    b["events"] += 1
    b["cache_write"] += cell(r.get("Input (w/ Cache Write)"))
    b["input"] += cell(r.get("Input (w/o Cache Write)"))
    b["cache_read"] += cell(r.get("Cache Read"))
    b["output"] += cell(r.get("Output Tokens"))


def cost_of(model, b):
    p = prices.get(model)
    if not p:
        return None
    return round(
        b["cache_write"] / 1e6 * p["cache_write"]
        + b["input"] / 1e6 * p["input"]
        + b["cache_read"] / 1e6 * p["cache_read"]
        + b["output"] / 1e6 * p["output"], 4)


for month in sorted(months):
    by_model, totals, unpriced = [], zero(), set()
    totals["cost_usd"] = 0.0
    for model in sorted(months[month], key=lambda m: -sum(
            months[month][m][k] for k in ("cache_write", "input", "cache_read", "output"))):
        b = months[month][model]
        c = cost_of(model, b)
        tok = b["cache_write"] + b["input"] + b["cache_read"] + b["output"]
        by_model.append(dict(model=model, **b, total_tokens=tok, cost_usd=c))
        for k in ("events", "cache_write", "input", "cache_read", "output"):
            totals[k] += b[k]
        if c is None:
            unpriced.add(model)
        else:
            totals["cost_usd"] += c
    totals["total_tokens"] = (totals["cache_write"] + totals["input"]
                              + totals["cache_read"] + totals["output"])
    totals["cost_usd"] = round(totals["cost_usd"], 2)
    totals["cost_partial"] = bool(unpriced)

    out = dict(month=month, source="cursor",
               note="Equivalent API cost (Cursor bills via subscription). cost_usd sums official per-model API rates over the CSV's token split.",
               totals=totals, unpriced_models=sorted(unpriced), by_model=by_model)
    dest = os.path.join(ROOT, "data", "cursor", f"{month}.json")
    json.dump(out, open(dest, "w"), indent=2)

    star = "~" if unpriced else ""
    warn = f"  (unpriced: {', '.join(sorted(unpriced))})" if unpriced else ""
    print(f"✓ {month}: {totals['events']} events  {totals['total_tokens']:,} tokens  "
          f"equiv-cost={star}${totals['cost_usd']:.2f}{warn}")

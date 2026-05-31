#!/usr/bin/env python3
# Regenerate data/manifest.json by scanning what's actually on disk.
#
# Every importer calls this after writing its slice, so the manifest is always
# a truthful reflection of data/ — no per-source merge logic, no races. The
# dashboard reads this one file to discover every source and month available.
#
# Schema:
#   {
#     "months": ["2026-04", "2026-05"],   # union across month-partitioned sources (dropdown)
#     "latest": "2026-05",
#     "sources": {
#       "claude": {"direct": [...], "relay": [...]},
#       "codex":  {"cli": [...], "cloud": [...]},
#       "cursor": {"present": true}
#     }
#   }

import json, os, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(ROOT, "data")


def months_in(*parts):
    """Sorted YYYY-MM subdirectories under data/<parts...>."""
    d = os.path.join(DATA, *parts)
    if not os.path.isdir(d):
        return []
    return sorted(
        x for x in os.listdir(d)
        if len(x) == 7 and x[4] == "-" and os.path.isdir(os.path.join(d, x))
    )


def month_files(*parts):
    """Sorted YYYY-MM from <YYYY-MM>.json files under data/<parts...>."""
    d = os.path.join(DATA, *parts)
    if not os.path.isdir(d):
        return []
    return sorted(
        x[:-5] for x in os.listdir(d)
        if x.endswith(".json") and len(x) == 12 and x[4] == "-"
    )


sources = {
    "claude": {"direct": months_in("claude", "direct"),
               "relay": months_in("claude", "relay")},
    "codex": {"cli": months_in("codex", "cli"),
              "cloud": month_files("codex", "cloud")},
    "cursor": {"present": os.path.exists(os.path.join(DATA, "cursor", "usage.csv")),
               "months": month_files("cursor")},
}

# Union of every month-partitioned source drives the dashboard's month dropdown.
all_months = set()
for prov in sources.values():
    for chan in prov.values():
        if isinstance(chan, list):
            all_months.update(chan)
months = sorted(all_months)

manifest = {"months": months, "latest": months[-1] if months else None,
            "sources": sources}

with open(os.path.join(DATA, "manifest.json"), "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")

print(f"✓ manifest.json: {len(months)} month(s), latest={manifest['latest']}")

# cc-dash

Local static dashboard for [ccusage](https://www.npmjs.com/package/ccusage) JSON reports. Single HTML file, vanilla JS + Chart.js CDN, no backend, all processing client-side.

## What it shows

For Claude Code (via ccusage):

- **Featured month cards** — Total tokens, cost USD, cache hit %, reuse ×. The last two are the actionable signals (the cache panel grades you on them).
- **Daily trend** for the selected month, with optional model breakdown (stacked).
- **Cache & context-management panel** — hit rate, reuse multiplier, daily hit-rate trend, per-project cache efficiency, and rule-based insights about your context habits.
- **Top projects** — one row per CWD ccusage tracks, columns Project / Total / Cost / Reuse ×. Reuse pill is colored by health (≥10× green, 3–10× soft green, 1–3× amber, <1× red).
- **By Model** breakdown when the toggle is on.
- **Monthly trend** auto-collapses with one month of data; expands once you've got history.

For Cursor (via the cursor.com CSV export):

- **Cursor activity panel** — events / total tokens / cache hit rate / reuse multiplier, daily activity (tokens + events on dual axes), per-model breakdown, top days. Honors the Month filter. Cost isn't shown — Cursor bills on a subscription so per-event cost is "Included".

For Codex (via the local CLI session logs):

- `bin/import-codex.sh` aggregates OpenAI Codex CLI usage straight from `~/.codex/sessions/**/*.jsonl` (the `token_count` events, same source ccusage's `@ccusage/codex` reads) into `data/codex/<month>/{daily,monthly}.json` — sessions, input / cached-input / output tokens, cache hit %, and a per-model breakdown.
- **Cost is an *equivalent API cost***, not your real bill: Codex billed via a ChatGPT subscription is flat-rate, so we price the tokens at OpenAI's published pay-per-token rates to answer "what would this usage cost on the API." Rates live in `data/codex/pricing.json` (auto-seeded with gpt-5.5's official $5 / $0.50 / $30 per-1M input / cached / output; edit to correct or extend). Unpriced models are counted but left uncosted and listed under `unpriced_models`.
- **CLI surface only.** Codex's cloud surfaces — *GitHub Code Review*, *Exec*, *Desktop App* (the categories in ChatGPT's "Usage breakdown") — run server-side and write nothing local, so `import-codex.sh` can't see them. For those, see the cloud importer below.

For Codex cloud (via the ChatGPT web backend — **unofficial**):

- `bin/import-codex-cloud.sh` pulls the data behind `chatgpt.com/codex/cloud/settings/analytics` — the per-surface usage split (CLI / GitHub Code Review / Exec / Desktop App / …), a per-model credit split, and code-review metrics (PRs reviewed, comment counts by P0/P1/P2). This is what surfaces *GitHub Code Review* and *Exec* usage that the local logs miss.
- **No official personal API exists** — this reuses your logged-in ChatGPT credentials the same way the dashboard does. Copy `data/codex/cloud/.auth.sh.example` → `.auth.sh` (gitignored) and paste a Bearer token + cookie from a browser DevTools "Copy as cURL". They're short-lived; on HTTP 401/403 the script tells you to refresh them. `CODEX_CLOUD_SKIP_FETCH=1` re-parses an already-saved capture under `raw/` without the network.
- **Values are a distribution, not tokens/$.** The response reports credits as a *percent* of your plan window (`"units": "percent"`), so this answers "what share of my Codex usage was cloud PR review" — not absolute tokens. Pair it with `import-codex.sh` (absolute CLI tokens + equivalent $) for the full picture.
- The only *official* per-surface export is the enterprise **Codex Analytics API** (`api.chatgpt.com/v1/analytics/codex`, workspace-admin scoped); the platform Usage API (`/v1/organization/usage/*`) is API-key billing only and has no Codex-surface dimension.

Shared:

- Filters: **month**, **project**, and **break down by model** toggle.
- Token numbers auto-format K / M / B; data is cached in `localStorage` between reloads.
- Tolerates ccusage shape variations (`{daily:[]}`, `{sessions:[]}`, raw arrays, `{data:[]}`, snake_case keys, etc.).

## Layout

```
cc-dash/
├── ccusage-dashboard.html         # the dashboard (open via http://localhost:…)
├── bin/
│   ├── refresh.sh                 # regenerate JSONs for a month via ccusage
│   ├── refresh-and-commit.sh      # wrapper used by launchd; logs + commits index bumps
│   ├── import-cursor.sh           # stage a fresh Cursor CSV export at data/cursor/usage.csv
│   ├── import-codex.sh            # aggregate Codex CLI usage from ~/.codex/sessions into data/codex/
│   ├── import-codex-cloud.sh      # pull Codex cloud usage (Code Review/Exec/…) from the ChatGPT web backend
│   └── serve.sh                   # python3 -m http.server + opens the dashboard
├── launchd/
│   └── com.example.cc-dash.refresh.plist  # template LaunchAgent (edit paths to install)
├── data/                          # mostly gitignored; regenerable
│   ├── index.json                 # tracked — drives the dashboard's bundled-month dropdown
│   ├── 2026-04/                   # gitignored — direct ccusage JSONs (your local machine)
│   │   ├── daily.json
│   │   ├── monthly.json
│   │   └── session.json
│   ├── latest -> 2026-04          # gitignored
│   ├── refresh.log                # gitignored — launchd stdout/stderr
│   ├── relay/                     # gitignored — same JSONs from a CC routing/relay provider
│   │   ├── 2026-04/{daily,monthly,session}.json
│   │   └── latest -> 2026-04
│   ├── cursor/                    # gitignored — Cursor CSV exports (manual)
│   │   ├── usage.csv              # the file the dashboard reads
│   │   └── cursor-usage-events-*.csv  # archived dated exports
│   └── codex/                     # mostly gitignored — Codex aggregates
│       ├── pricing.json           # tracked — per-model rate table (config, editable)
│       ├── 2026-05/{daily,monthly}.json  # gitignored — CLI usage from ~/.codex/sessions
│       ├── latest -> 2026-05      # gitignored
│       └── cloud/                 # Codex cloud usage (unofficial web-backend pull)
│           ├── .auth.sh.example   # tracked — credential template
│           ├── .auth.sh           # gitignored — your Bearer + cookie
│           ├── raw/               # gitignored — raw API responses
│           └── 2026-05.json       # gitignored — parsed per-surface summary
└── .gitignore                     # data/* except !data/index.json, !data/codex/pricing.json
```

## Reading the numbers

### Token formula

```
total_tokens = input + output + cache_creation + cache_read
```

ccusage rolls all four into `totalTokens`, which is why a healthy Claude Code user often shows `total` orders of magnitude larger than `input + output` alone — the bulk is `cache_read`. That's not a bug, it's the cost-saving working as intended: every cached prefix you re-read on subsequent turns counts as fresh `cache_read` tokens, but you're billed at ~10% of the input rate for them.

| Field | What it is | Approx. price (relative to fresh input) |
|---|---|---|
| `input` | New tokens not from cache | 1.0× |
| `output` | Model's response | ~5× input |
| `cache_creation` | Input tokens written to cache | 1.25× (5-min TTL) or 2.0× (1-hour TTL) |
| `cache_read` | Input tokens served from cache | 0.1× |

### Cache reuse multiplier

```
reuse = cache_read / cache_creation
```

Anthropic's break-even (where caching pays for itself) is ~1.4× for a 5-min TTL or ~2.1× for a 1-hour TTL. The Cache panel grades you on a wider scale so you have margin:

| Reuse | Verdict | Color |
|---|---|---|
| ≥ 10× | excellent — long, focused sessions, stable file set | green |
| 3–10× | healthy — comfortably above break-even | green |
| 1–3× | marginal — cache barely paying for itself | amber |
| < 1× | losing money — cache writes outnumber reads | red |

### Cache hit rate

```
hit_rate = cache_read / (input + cache_creation + cache_read)
```

Share of input-side tokens served from cache. Typical Claude Code: 40–70%; very long sticky sessions can hit 90%+. Lower numbers are usually a sign of frequent context churn (large tool outputs pasted in, frequent `/clear`, switching between projects).

## Quick start

```sh
bin/serve.sh           # serves on http://localhost:8765 and opens the page
```

In the page: click **Load bundled data**, or pick files manually in the upload section. The bundled-month dropdown is populated from `data/index.json`.

> Browsers block `fetch()` over `file://`, so double-clicking the HTML works for manual uploads but not for one-click load. Always go through `bin/serve.sh` for the bundled flow.

## Refresh data

```sh
bin/refresh.sh                # current month
bin/refresh.sh prev           # previous month (used by the LaunchAgent)
bin/refresh.sh 2026-04        # specific month
bin/refresh.sh all            # full history (no date filter)
```

`refresh.sh` writes to `data/<YYYY-MM>/`, updates the `data/latest` symlink, and rebuilds `data/index.json` so the dashboard's bundled dropdown stays in sync. It is equivalent to:

```sh
npx ccusage@latest daily   --since 20260401 --until 20260430 --json > daily.json
npx ccusage@latest monthly --since 20260401 --until 20260430 --json > monthly.json
npx ccusage@latest session --since 20260401 --until 20260430 --json > session.json
```

(Drop `--since`/`--until` for full history.)

## Multiple sources (Direct + Relay)

If you also use Claude Code through a routing/relay provider (one-api, new-api, FastGPT, etc.) that emits the same `daily.json` / `monthly.json` / `session.json` shape, drop the relay's exports under `data/relay/<YYYY-MM>/`:

```
data/relay/2026-04/{daily,monthly,session}.json
data/relay/latest -> 2026-04
```

The dashboard's **Source** filter then offers Direct / Relay / Combined:

- **Direct** — your local ccusage exports.
- **Relay** — the relay provider's exports.
- **Combined** — sums per-date (daily) and per-month (monthly), concatenates sessions. Useful for "total CC spend across both billing channels"; the cache panel in this mode shows the blended hit rate, which is rarely what you want — flip to a single source for clean cache-reuse signals.

The toggle only appears when both sources have data; otherwise the dashboard silently uses whichever is loaded.

## Cursor data

Cursor doesn't have a CLI export, so this is manual:

1. Sign in at [cursor.com](https://cursor.com) → Settings → Usage → **Export CSV**.
2. Drop the file into the workspace:

   ```sh
   bin/import-cursor.sh ~/Downloads/cursor-usage-events-2026-05-01.csv
   ```

   That copies the dated export into `data/cursor/` for archive and points `data/cursor/usage.csv` at it (the path the dashboard reads).
3. Refresh the dashboard tab. **Load bundled data** auto-picks up `data/cursor/usage.csv` if present — the Cursor panel only renders when the file exists.

The Cursor CSV is not month-partitioned (it's one rolling export). The dashboard filters rows by the selected month at render time, so picking April will show only April events even if the CSV spans more.

## Monthly auto-refresh (macOS LaunchAgent)

`bin/refresh-and-commit.sh` is a wrapper meant to be triggered by `launchd` (or cron). It runs `bin/refresh.sh prev` and commits `data/index.json` as `refresh: <month>` only when the index actually changed — so you get a clean `git log` audit trail without spurious commits.

To install on a fresh Mac:

```sh
# 1. Copy the template, fix paths/label for your user, install into LaunchAgents.
cp launchd/com.example.cc-dash.refresh.plist \
   ~/Library/LaunchAgents/com.<yourname>.cc-dash.refresh.plist
# Then edit the new file: replace USERNAME / Label / paths.

# 2. Load it.
launchctl bootstrap "gui/$(id -u)" \
   ~/Library/LaunchAgents/com.<yourname>.cc-dash.refresh.plist

# 3. Smoke-test it now (doesn't wait for the 1st of the month).
launchctl kickstart -k "gui/$(id -u)/com.<yourname>.cc-dash.refresh"
tail -f data/refresh.log
```

Schedule: 1st of each month, 09:00 **local time** (`StartCalendarInterval`). If the Mac is asleep at 09:00 launchd runs the job when it next wakes — you don't lose a month.

Useful commands while running:

```sh
launchctl print     gui/$(id -u)/com.<yourname>.cc-dash.refresh    # status, schedule, paths
launchctl list      | grep cc-dash                                  # one-line status
launchctl kickstart -k gui/$(id -u)/com.<yourname>.cc-dash.refresh  # run now
launchctl bootout   gui/$(id -u)/com.<yourname>.cc-dash.refresh     # disable/unload
```

To remove permanently: `launchctl bootout …` then delete the plist.

## Repo conventions

- `data/` is gitignored except `data/index.json` (the audit-trail file).
- Manual commits use your normal git identity. The LaunchAgent commits use `cc-dash refresh <cc-dash-refresh@local>` so they're easy to spot in `git log`.
- All processing in the browser is client-side; nothing leaves your machine.

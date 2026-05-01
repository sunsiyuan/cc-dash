# cc-dash

Local static dashboard for [ccusage](https://www.npmjs.com/package/ccusage) JSON reports. Single HTML file, vanilla JS + Chart.js CDN, no backend, all processing client-side.

## What it shows

For Claude Code (via ccusage):

- **Featured month totals** — input / output / total tokens + cost USD, with the top 5 days by token volume.
- **Monthly trend** — bar (tokens) + line (cost) on dual axes.
- **Daily trend** for the selected month, with optional model breakdown (stacked).
- **Token composition** — input / output / cache create / cache read doughnut.
- **Top projects** and **top sessions** tables, sortable.
- **Cache & context-management panel** — hit rate, reuse multiplier, daily hit-rate trend, per-project cache efficiency, and rule-based insights about your context habits.

For Cursor (via the cursor.com CSV export):

- **Cursor activity panel** — events / total tokens / cache hit rate / reuse multiplier, daily activity (tokens + events on dual axes), per-model breakdown, top days. Honors the Month filter. Cost isn't shown — Cursor bills on a subscription so per-event cost is "Included".

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
│   └── serve.sh                   # python3 -m http.server + opens the dashboard
├── launchd/
│   └── com.example.cc-dash.refresh.plist  # template LaunchAgent (edit paths to install)
├── data/                          # mostly gitignored; regenerable
│   ├── index.json                 # tracked — drives the dashboard's bundled-month dropdown
│   ├── 2026-04/                   # gitignored — Claude Code JSONs
│   │   ├── daily.json
│   │   ├── monthly.json
│   │   └── session.json
│   ├── latest -> 2026-04          # gitignored
│   ├── refresh.log                # gitignored — launchd stdout/stderr
│   └── cursor/                    # gitignored — Cursor CSV exports (manual)
│       ├── usage.csv              # the file the dashboard reads
│       └── cursor-usage-events-*.csv  # archived dated exports
└── .gitignore                     # data/* except !data/index.json
```

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

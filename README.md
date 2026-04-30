# cc-dash

Local static dashboard for [ccusage](https://www.npmjs.com/package/ccusage) JSON reports. Single HTML file, vanilla JS + Chart.js CDN, no backend.

## Layout

```
cc-dash/
├── ccusage-dashboard.html   # the dashboard (open in a browser)
├── bin/
│   ├── refresh.sh           # regenerate JSONs for a month
│   └── serve.sh             # python3 -m http.server, opens the dashboard
└── data/                    # gitignored; regenerable
    ├── 2026-04/
    │   ├── daily.json
    │   ├── monthly.json
    │   └── session.json
    └── latest -> 2026-04
```

## One-click load

The dashboard's **Load bundled data** button fetches `./data/<month>/{daily,monthly,session}.json`. Browsers block `fetch()` over `file://`, so run a local server:

```sh
bin/serve.sh           # serves on http://localhost:8765 and opens the page
```

You can still open `ccusage-dashboard.html` directly via `file://` and use the manual file pickers — the button just won't work in that mode.

## Refresh data

```sh
bin/refresh.sh                # current month
bin/refresh.sh 2026-04        # specific month
bin/refresh.sh prev           # previous month
bin/refresh.sh all            # full history (no date filter)
```

`refresh.sh` writes to `data/<YYYY-MM>/` and updates `data/latest` to point at it, so the dashboard's "Latest" preset always picks up the most recent run.

## How the JSONs are produced

Equivalent to:

```sh
npx ccusage@latest daily   --since 20260401 --until 20260430 --json > daily.json
npx ccusage@latest monthly --since 20260401 --until 20260430 --json > monthly.json
npx ccusage@latest session --since 20260401 --until 20260430 --json > session.json
```

Drop the `--since`/`--until` flags for the full history.

## Notes

- All processing is client-side; data never leaves the machine.
- The dashboard caches the last loaded JSONs in `localStorage`, so reloads aren't a fresh start.
- `data/` is gitignored on purpose — it contains personal usage data (project paths, token counts, costs).

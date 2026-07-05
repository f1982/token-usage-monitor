# Token Usage Monitor

A native macOS app + desktop widget that shows your local **Claude Code** usage
at a glance — session (5-hour) and weekly quota, scoped model limits, and
opt-in per-project token analytics. It's a SwiftUI + WidgetKit project, and
everything runs and stays on your machine.

## What it does

- **Overview** — current session %, weekly "All models" %, and any scoped
  model limits, each rendered as a configurable chart (progress bar, bar,
  donut, or a draining "water ball"). Shows which data source produced the
  snapshot and how stale it is.
- **Projects** (opt-in) — scans `~/.claude/projects/**/*.jsonl` and aggregates
  per-project token totals (input / output / cache), message counts, models,
  and first/last-used times across Today / 7 Days / 30 Days / All.
- **Desktop widgets** — small and medium WidgetKit widgets that read cached
  snapshots (the medium widget can show your top 3 projects).
- **Privacy first** — raw JSONL logs, prompts, and message content are never
  stored or uploaded. Only normalized snapshots and aggregate token totals are
  cached in the App Group container.

## Where usage data comes from

Quota usage is fetched through providers, tried in order:

1. **Claude Code statusline `rate_limits`** (default, always tried first) —
   read from `~/.claude-usage-widget/statusline/latest.json`, considered fresh
   for 10 minutes.
2. **Local JSONL estimate** — optional, only when enabled in Settings (present
   for forward compatibility; not registered in this build).
3. **Experimental OAuth usage API** — opt-in, reads the local Claude Code OAuth
   token against an undocumented endpoint; off by default and marked
   experimental.

The Overview page shows which source produced the current snapshot
(`Source: Official statusline` / `Local estimate` / `Experimental OAuth`).

### Setting up the statusline source

The app never installs hooks itself. To feed the default source, configure a
Claude Code statusline command that writes the normalized state file, e.g. in
`~/.claude/settings.json`:

```json
{
  "statusLine": { "type": "command", "command": "~/.claude/statusline-usage.sh" }
}
```

with a script that maps the statusline JSON (stdin) to the normalized format:

```sh
#!/bin/bash
# ~/.claude/statusline-usage.sh
# Claude Code (>= 2.1.80, Pro/Max subscription) provides
# `.rate_limits.five_hour` / `.rate_limits.seven_day` with `used_percentage`
# and `resets_at` (Unix epoch seconds). Both windows can be absent until the
# first API response of a session.
input=$(cat)
mkdir -p ~/.claude-usage-widget/statusline
echo "$input" | jq '
  def iso: if . == null then null elif type == "number" then todate else tostring end;
  {
    schemaVersion: 1,
    source: "claude-code-statusline",
    capturedAt: (now | todate),
    rateLimits: {
      session: {kind: "session", label: "Session",
                percent: (.rate_limits.five_hour.used_percentage // null),
                resetsAt: (.rate_limits.five_hour.resets_at | iso)},
      weekly:  {kind: "weekly_all", label: "All models",
                percent: (.rate_limits.seven_day.used_percentage // null),
                resetsAt: (.rate_limits.seven_day.resets_at | iso)}
    }
  }' > ~/.claude-usage-widget/statusline/latest.json 2>/dev/null
echo "Claude Code"   # whatever you want the statusline to display
```

If the file is missing or older than 10 minutes, the app reports
"Official statusline data not available." and only falls back to sources you
explicitly enabled in Settings.

## Local Project Analytics (opt-in)

Off by default. When enabled in Settings, the Projects page scans
`~/.claude/projects/**/*.jsonl` (path configurable), streams files line by line
off the main thread, and aggregates per-project token totals (input / output /
cache), message counts, models, and first/last-used times for Today /
Last 7 Days / Last 30 Days / All. Only the aggregated summaries are cached
(`project-usage-summary.json` in the App Group); the medium widget can then
show the top 3 projects. The widget never reads JSONL files directly.

## Layout

```
token-usage-monitor/
├── App/                        # SwiftUI app: UI, Providers, Services
├── Shared/                     # domain models, settings, analytics, caches
├── Widget/                     # WidgetKit extension (reads App Group caches)
├── Tests/                      # unit tests
├── project.yml                 # XcodeGen manifest (source of truth)
└── TokenUsageMonitor.xcodeproj # generated from project.yml
```

## Building

Requires macOS 14+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
The `.xcodeproj` is generated from `project.yml`.

```sh
brew install xcodegen   # once
xcodegen generate       # after editing project.yml or adding files

# build + test from the CLI
xcodebuild -project TokenUsageMonitor.xcodeproj -scheme TokenUsageMonitor \
  -allowProvisioningUpdates build
xcodebuild -project TokenUsageMonitor.xcodeproj -scheme TokenUsageMonitor \
  -destination 'platform=macOS' -allowProvisioningUpdates test
```

Or just open `TokenUsageMonitor.xcodeproj` in Xcode and run.

Signing uses team `4MX24QZ69S` with automatic provisioning (required by the App
Groups capability). If the first CLI build fails on a missing provisioning
profile, run it again — Xcode registers profiles on the first pass.

Building under a different Apple Developer account? Change the team ID and App
Group ID in `project.yml`, both `.entitlements` files (`App/` and `Widget/`),
and `Shared/Constants/AppGroup.swift`, then re-run `xcodegen generate`.

## Using the widget

1. Launch the app once so it fetches usage and caches a snapshot in the
   `4MX24QZ69S.group.me.andycao.app.tokenusagemonitor` App Group container.
2. Right-click the desktop → **Edit Widgets** → search "Claude Code Usage" and
   add the small or medium widget.
3. The widget reads only the cached snapshots; keep the app running (it
   auto-refreshes every 5 minutes) so data stays fresh.
4. For top projects in the medium widget, enable **Local Project Analytics** in
   Settings and run a scan from the Projects page.

## Behavior notes

- Cache TTL 5 min; manual Refresh bypasses TTL. OAuth 429s still trigger a
  2-minute cooldown inside the aggregator.
- Provider failures fall back to the stale cache with a readable note that
  names the failing source.
- Widget timeline asks for a reload every 15 minutes and shows cache age
  ("Cached · 12m ago" once stale).
- Project scans are manual (Refresh button); no filesystem watching in V0.2.
</content>
</invoke>

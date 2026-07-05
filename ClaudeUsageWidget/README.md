# Claude Code Usage Widget (V0.2)

A macOS SwiftUI app + WidgetKit widget that shows your local Claude Code usage
(session %, weekly "All models" %, scoped model limits) and opt-in per-project
token analytics — implemented per
[the V0.1 spec](../docs/claude-code-usage-widget-v0.1-implementation-spec.md) and
[the V0.2 patch spec](../docs/claude-code-usage-widget-v0.2-patch-implementation-spec.md).

Everything stays local. Raw JSONL logs, prompt text, and message content are
never stored or uploaded; only normalized snapshots and aggregate token totals
are cached in the App Group container.

## Data sources (V0.2)

Quota usage is fetched through providers, in this order:

1. **Claude Code statusline `rate_limits`** (default, always tried first) —
   read from `~/.claude-usage-widget/statusline/latest.json`, fresh for
   10 minutes.
2. **Local JSONL estimate** — optional, only when enabled in Settings
   (not registered in this build; the mode exists for forward compatibility).
3. **Experimental OAuth usage API** — the V0.1 path, now opt-in only. Reads
   the local Claude Code OAuth token and an undocumented endpoint; off by
   default and marked experimental.

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
`~/.claude/projects/**/*.jsonl` (path configurable), streams files line by
line off the main thread, and aggregates per-project token totals (input /
output / cache), message counts, models, and first/last-used times for
Today / Last 7 Days / Last 30 Days / All. Only the aggregated summaries are
cached (`project-usage-summary.json` in the App Group); the medium widget can
then show the top 3 projects. The widget never reads JSONL files directly.

## Project layout

- `project.yml` — XcodeGen manifest (source of truth for the Xcode project)
- `Shared/` — domain models, formatting, settings store, provider protocol,
  project analytics (parser, aggregator, time ranges), App Group cache stores
- `App/` — SwiftUI app (Overview / Projects / Settings), providers
  (statusline, OAuth, local project scan), aggregator + refresh services
- `Widget/` — WidgetKit extension (small + medium, reads App Group caches only)
- `Tests/` — unit tests (domain, storage, settings, providers, services,
  parsing, aggregation)

## Building

The `.xcodeproj` is generated from `project.yml`. After changing the manifest
(or adding files), regenerate:

```sh
brew install xcodegen   # once
xcodegen generate
```

Build and test:

```sh
xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageWidget \
  -allowProvisioningUpdates build
xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageWidget \
  -destination 'platform=macOS' -allowProvisioningUpdates test
```

Or just open `ClaudeUsageWidget.xcodeproj` in Xcode and run.

Signing uses team `4MX24QZ69S` with automatic provisioning (the App Groups
capability requires it). If the first CLI build fails with a missing
provisioning profile file, run it again — Xcode registers the profiles on the
first pass.

## Using the widget

1. Launch the app once (it fetches usage and caches a snapshot in the
   `4MX24QZ69S.group.com.boardpro.ClaudeUsageWidget` App Group container).
2. Right-click the desktop → Edit Widgets → search "Claude Code Usage" and add
   the small or medium widget.
3. The widget reads only the cached snapshots; open the app (or leave it
   running — it auto-refreshes every 5 minutes) to keep data fresh.
4. To see top projects in the medium widget, enable Local Project Analytics in
   Settings and run a scan from the Projects page.

## Behavior notes

- Cache TTL 5 min; manual Refresh bypasses TTL. OAuth 429s still trigger a
  2-minute cooldown inside the aggregator.
- Provider failures fall back to the stale cache with a readable note that
  names the failing source.
- Widget timeline asks for a reload every 15 minutes and shows cache age
  ("Cached · 12m ago" once stale).
- Project scans are manual (Refresh button); no filesystem watching in V0.2.

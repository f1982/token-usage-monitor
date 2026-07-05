# Agent Usage Monitor

A native macOS app + desktop widget that shows your local **Claude Code** usage
at a glance — session (5-hour) and weekly quota, scoped model limits, and
opt-in per-project token analytics. Everything runs and stays on your machine.

The app is **Claude Code Usage Widget**, a SwiftUI + WidgetKit project living in
[`ClaudeUsageWidget/`](ClaudeUsageWidget/).

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

Quota is fetched through providers, tried in order:

1. **Claude Code statusline `rate_limits`** (default) — read from
   `~/.claude-usage-widget/statusline/latest.json`, considered fresh for 10 min.
2. **Local JSONL estimate** — opt-in (present for forward compatibility).
3. **Experimental OAuth usage API** — opt-in, reads the local Claude Code OAuth
   token against an undocumented endpoint; off by default.

You feed the default source with a Claude Code statusline command that writes
the normalized state file — the app never installs hooks itself. See
[the app README](ClaudeUsageWidget/README.md#setting-up-the-statusline-source)
for the exact `~/.claude/settings.json` snippet and script.

## Layout

```
agent-usage-monitor/
├── ClaudeUsageWidget/        # the macOS app + widget (XcodeGen project)
│   ├── App/                  # SwiftUI app: UI, Providers, Services
│   ├── Shared/               # domain models, settings, analytics, caches
│   ├── Widget/               # WidgetKit extension (reads App Group caches)
│   ├── Tests/                # unit tests
│   ├── project.yml           # XcodeGen manifest (source of truth)
│   └── README.md             # full app documentation
└── docs/                     # implementation specs (v0.1, v0.2)
```

## Building

Requires macOS 14+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
The `.xcodeproj` is generated from `project.yml`.

```sh
brew install xcodegen                     # once
cd ClaudeUsageWidget
xcodegen generate                         # after editing project.yml or adding files

# build + test from the CLI
xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageWidget \
  -allowProvisioningUpdates build
xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageWidget \
  -destination 'platform=macOS' -allowProvisioningUpdates test
```

Or just open `ClaudeUsageWidget/ClaudeUsageWidget.xcodeproj` in Xcode and run.

Signing uses team `4MX24QZ69S` with automatic provisioning (required by the App
Groups capability). If the first CLI build fails on a missing provisioning
profile, run it again — Xcode registers profiles on the first pass.

Building under a different Apple Developer account? Change the team ID and App
Group ID in `project.yml`, both `.entitlements` files (`App/` and `Widget/`),
and `Shared/Constants/AppGroup.swift`, then re-run `xcodegen generate`.

## Using the widget

1. Launch the app once so it fetches usage and caches a snapshot in the
   `4MX24QZ69S.group.com.boardpro.ClaudeUsageWidget` App Group.
2. Right-click the desktop → **Edit Widgets** → search "Claude Code Usage" and
   add the small or medium widget.
3. Keep the app running (it auto-refreshes every 5 minutes) so data stays fresh.
4. For top projects in the medium widget, enable **Local Project Analytics** in
   Settings and run a scan from the Projects page.

## Docs

- [`ClaudeUsageWidget/README.md`](ClaudeUsageWidget/README.md) — full app docs,
  statusline setup, behavior notes
- [`docs/`](docs/) — v0.1 and v0.2 implementation specs

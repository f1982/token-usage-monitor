# Token Usage Monitor

A native macOS app + desktop widget that shows your local **Claude Code** and
**Codex** usage at a glance — session (5-hour) and weekly quota, scoped model
limits, Codex reset state, and opt-in per-project token analytics. It's a
SwiftUI + WidgetKit project, and everything runs and stays on your machine.

## What it does

- **Overview** — current session %, weekly "All models" %, and any scoped
  model limits, plus Codex 5-hour and weekly limits when available. Each limit
  is rendered as a configurable chart (progress bar, bar, donut, or a draining
  "water ball"). Shows which data source produced the Claude snapshot and how
  stale it is.
- **Display settings** — choose whether the overview and widget show Claude
  Code, Codex, or both. The setting is stored in the App Group so the widget
  follows the same selection.
- **Projects** (opt-in) — scans `~/.claude/projects/**/*.jsonl` and aggregates
  per-project token totals (input / output / cache), message counts, models,
  and first/last-used times across Today / 7 Days / 30 Days / All.
- **Desktop widgets** — small and medium WidgetKit widgets that read cached
  snapshots (the medium widget can show your top 3 projects).
- **Privacy first** — raw JSONL logs, prompts, and message content are never
  stored or uploaded. Only normalized snapshots and aggregate token totals are
  cached in the App Group container. Local Project Analytics also caches project
  names, project paths, model names, and first/last-used timestamps as metadata.

## Where usage data comes from

Claude quota usage is fetched through providers, tried in order:

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

Codex usage is read independently from the latest local Codex session JSONL
under `~/.codex/sessions` by default. The path is configurable in Settings
under **Codex**. The app looks for the newest `token_count` event and maps
`rate_limits.primary` and `rate_limits.secondary` into Codex 5-hour and weekly
rows, including reset timestamps. The widget reads those Codex rows only from
the app's cached snapshot; it does not scan `~/.codex` directly.

### Setting up the statusline source

The app never installs hooks itself. To feed the default source, configure a
Claude Code statusline command that writes the normalized state file, e.g. in
`~/.claude/settings.json`:

```json
{
  "statusLine": { "type": "command", "command": "~/.claude/statusline-usage.sh" }
}
```

Install the included converter and make it executable:

```sh
cp scripts/statusline-usage.sh ~/.claude/statusline-usage.sh
chmod +x ~/.claude/statusline-usage.sh
```

The converter writes to a temporary file and atomically replaces
`latest.json`, so the app cannot observe a half-written JSON document.

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

The cached summaries intentionally do not include raw JSONL lines, prompts, or
message text. They do include project names, project paths, model names, token
totals, message counts, and first/last-used timestamps, because those fields are
needed for the Projects view and widget. Treat screenshots or exported cache
files as potentially sensitive if your project names or filesystem paths reveal
private work.

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
# regenerate the ignored .xcodeproj from project.yml
xcodegen generate
```

### Local unsigned build

The open-source repository does not contain a developer Team, certificate, or
provisioning profile. Build locally without code signing:

```sh
xcodegen generate

xcodebuild \
  -project TokenUsageMonitor.xcodeproj \
  -scheme TokenUsageMonitor \
  -destination 'platform=macOS' \
  build \
  CODE_SIGNING_ALLOWED=NO
```

Run the generated app with:

```sh
open ~/Library/Developer/Xcode/DerivedData/TokenUsageMonitor-*/Build/Products/Debug/TokenUsageMonitor.app
```

Run all unit tests with signing disabled:

```sh
xcodebuild \
  -project TokenUsageMonitor.xcodeproj \
  -scheme TokenUsageMonitor \
  -destination 'platform=macOS' \
  test \
  CODE_SIGNING_ALLOWED=NO
```

Run only the Codex parser tests:

```sh
xcodebuild \
  -project TokenUsageMonitor.xcodeproj \
  -scheme TokenUsageMonitor \
  -destination 'platform=macOS' \
  test \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:TokenUsageMonitorTests/CodexSessionUsageProviderTests
```

The generated `.xcodeproj` is ignored by Git. If Xcode reports Team or
provisioning errors, use the unsigned CLI build above, or configure signing
locally in Xcode without committing those settings.

### Signed GitHub Releases

Releases are automated with Release Please and GitHub Actions. The complete
maintainer runbook, including one-time GitHub setup and troubleshooting, is in
[`CONTRIBUTING.md`](CONTRIBUTING.md#releasing). The short version is:

```text
Conventional Commit PR
  → merge into develop
  → Release Please opens/updates a release PR
  → merge the release PR
  → VERSION, CHANGELOG, tag, and GitHub Release are created
  → signed macOS build, tests, notarization, and zip upload run automatically
```

Release versioning is managed by [`VERSION`](VERSION),
[`release-please-config.json`](release-please-config.json), and
[`.release-please-manifest.json`](.release-please-manifest.json). Do not
manually edit `VERSION` for a normal release. Release Please updates it in the
release PR. The signed build workflow is
[`.github/workflows/release.yml`](.github/workflows/release.yml).

For downloads hosted on GitHub, the app is Developer ID signed and Apple
notarized. Apple describes [Developer ID distribution](https://developer.apple.com/support/developer-id/)
and [notarization](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
for apps distributed outside the Mac App Store.

The release pipeline keeps repository configuration and signing secrets
separate. Private keys, certificates, profiles, and API keys must never be
committed or placed in an uploaded `.env` file.

The workflow can also be started manually with **Actions → Release macOS app →
Run workflow** and a version such as `1.0.0`; use that only for recovery or a
deliberate manual release because it bypasses the normal Release Please PR.

The current repository contains only placeholder identifiers:

- `DEVELOPMENT_TEAM: ""`
- bundle IDs under `com.example.tokenusagemonitor`
- App Group `group.example.tokenusagemonitor`

Before enabling a signed release workflow, replace these values at build time
or through an untracked local/CI configuration layer. App and widget targets
must use matching, team-scoped App Group identifiers. The exact need for a
provisioning profile depends on the distribution channel and entitlements;
Apple documents that some macOS entitlements can be claimed without a profile,
while restricted capabilities and App Groups must match the authorized
signing configuration.

## Using the widget

1. Launch the app once so it fetches usage and caches a snapshot in the
   configured App Group container.
2. Right-click the desktop → **Edit Widgets** → search "Code Usage" and
   add the small or medium widget.
3. The widget reads only the cached snapshots; keep the app running (it
   auto-refreshes every 5 minutes) so data stays fresh.
4. For top projects in the medium widget, enable **Local Project Analytics** in
   Settings and run a scan from the Projects page.

## Behavior notes

- Cache TTL 5 min; manual Refresh bypasses TTL. OAuth 429s still trigger a
  2-minute cooldown inside the aggregator.
- Display filters hide sources in the app and widget only; refresh still caches
  all available usage so switching sources back on is immediate.
- Provider failures fall back to the stale cache with a readable note that
  names the failing source.
- Widget timeline asks for a reload every 15 minutes and shows cache age
  ("Cached · 12m ago" once stale).
- Project scans are manual (Refresh button); no filesystem watching in V0.2.

#!/usr/bin/env bash
# Convert Claude Code statusline JSON into the state file consumed by the app.
# The temporary file + mv sequence prevents the app from reading partial JSON.
set -euo pipefail

OUTPUT_DIR="${HOME}/.claude-usage-widget/statusline"
OUTPUT_FILE="${OUTPUT_DIR}/latest.json"
mkdir -p "$OUTPUT_DIR"

input="$(cat)"
tmp_file="$(mktemp "${OUTPUT_DIR}/.latest.json.XXXXXX")"
trap 'rm -f "$tmp_file"' EXIT

printf '%s' "$input" | jq '
  def iso:
    if . == null then null
    elif type == "number" then todate
    else tostring
    end;
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
  }' > "$tmp_file"

mv -f "$tmp_file" "$OUTPUT_FILE"
echo "Claude Code"

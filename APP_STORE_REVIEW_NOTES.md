# App Store Review Notes

## What the app does

Token Usage Monitor displays usage information from Claude Code and Codex on a
local Mac, including quota percentages and optional aggregate project token
analytics. It is an independent app and is not affiliated with Anthropic,
OpenAI, Claude Code, or Codex.

## First launch and directory access

1. Launch the app and open Settings.
2. Click “Choose Statusline Folder”, “Choose Codex Sessions Folder”, or
   “Choose Claude Projects Folder”.
3. Select a test directory containing the relevant local data. The app does
   not scan guessed paths without a user-granted security-scoped bookmark.
4. Revoke access in Settings and confirm the app continues to run and shows an
   unavailable state rather than reading the directory.

The widget reads only normalized cache files in the shared App Group. It does
not read the selected source directories directly.

## OAuth

OAuth is disabled by default and is not needed for the local statusline or
Codex features. To test it, enable the experimental source in Settings and
paste a token that belongs to the reviewer account. The token is stored in the
macOS Keychain, is never included in cache files, and can be removed from the
same screen. The app sends only the token and required API headers to the
undocumented Anthropic usage endpoint; it does not upload local project paths,
prompts, messages, models, or cached totals.

## Privacy controls

Settings provides Privacy Policy and Support links, Clear Cached Usage Data,
directory re-authorization, directory revocation, and OAuth token removal.

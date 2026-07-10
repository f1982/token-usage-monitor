# Token Usage Monitor Privacy Policy

Last updated: 2026-07-10

Token Usage Monitor is a macOS app that displays usage information from files
you explicitly choose and, if enabled, an Anthropic usage endpoint.

The app is independent and is not affiliated with or endorsed by Anthropic,
OpenAI, Claude Code, or Codex. Product names are used descriptively.

## Data processed

- Claude Code statusline files, Codex session files, and Claude project logs
  are read only after you choose their folders in the app.
- The app extracts usage percentages, token totals, project names and paths,
  model names, message counts, and timestamps needed for the local views.
- Raw logs, prompts, and message content are not stored by the app.
- The app does not sell, advertise against, or share local data.

## Local storage

Normalized usage, project summaries, usage history, and the directory
bookmarks you grant are stored locally in the app's sandbox/App Group so the
main app and widget can work together. Cached summaries can contain project
names, paths, model names, token totals, message counts, and timestamps. The
app does not cache raw log lines or OAuth tokens in these files.

You can clear cached usage data and revoke folder access from Settings at any
time. Removing the app may not remove Keychain items; use “Remove Token” in
Settings before uninstalling if you enabled OAuth.

## Optional OAuth request

OAuth usage is disabled by default. If you enable it, you paste a token into
Settings and the app stores it in the macOS Keychain. The app sends that token
as a Bearer `Authorization` header to Anthropic's undocumented usage endpoint,
along with the API version and beta header required by that endpoint. It does
not send project paths, prompts, messages, model names, or cached token totals
in that request. Anthropic's own policies govern its handling of the request.

## Contact

For questions or removal requests, open an issue on the project's [support
page](SUPPORT.md).

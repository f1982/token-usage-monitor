#!/usr/bin/env bash
#
# dev-release.sh — quick dev release for Token Usage Monitor.
#
# Regenerates the Xcode project, builds a Release .app, zips it into ./dist/,
# and publishes a GitHub *pre-release* with the zip attached.
#
# This is a DEV release: the app is ad-hoc signed only (placeholder team, no
# notarization). Gatekeeper will warn on machines other than the build machine.
#
# Usage:
#   scripts/dev-release.sh                 # build + zip + GitHub pre-release
#   scripts/dev-release.sh --no-github     # build + zip only (skip publish)
#   scripts/dev-release.sh -n "notes..."   # custom release notes
#
set -euo pipefail

# --- locate repo root (script lives in scripts/) -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="TokenUsageMonitor.xcodeproj"
SCHEME="TokenUsageMonitor"
APP_NAME="TokenUsageMonitor"
INFO_PLIST="App/Info.plist"
DERIVED="build/dev-release"
DIST="dist"

# --- args ---------------------------------------------------------------------
PUBLISH_GITHUB=1
NOTES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-github) PUBLISH_GITHUB=0; shift ;;
    -n|--notes)  NOTES="${2:-}"; shift 2 ;;
    -h|--help)   sed -n '3,20p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# --- preflight ----------------------------------------------------------------
command -v xcodegen >/dev/null || { echo "xcodegen not found (brew install xcodegen)"; exit 1; }
command -v xcodebuild >/dev/null || { echo "xcodebuild not found (install Xcode)"; exit 1; }
if [[ "$PUBLISH_GITHUB" == 1 ]]; then
  command -v gh >/dev/null || { echo "gh not found (brew install gh); use --no-github to skip"; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "gh not authenticated (run: gh auth login)"; exit 1; }
fi

# --- version / tag metadata ---------------------------------------------------
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
GIT_SHA="$(git rev-parse --short HEAD)"
STAMP="$(date +%Y%m%d%H%M%S)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
TAG="v${VERSION}-dev.${STAMP}+${GIT_SHA}"
ZIP_NAME="${APP_NAME}-${VERSION}-dev-${GIT_SHA}.zip"

if ! git diff --quiet HEAD 2>/dev/null || [[ -n "$(git status --porcelain)" ]]; then
  log "WARNING: working tree has uncommitted changes; the released build won't match a committed state."
fi

log "Version ${VERSION} • ${GIT_SHA} • branch ${BRANCH}"

# --- generate + build ---------------------------------------------------------
log "xcodegen generate"
xcodegen generate

log "Building Release (ad-hoc signed)…"
rm -rf "$DERIVED"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  build

APP_PATH="$DERIVED/Build/Products/Release/${APP_NAME}.app"
[[ -d "$APP_PATH" ]] || { echo "Build succeeded but ${APP_PATH} not found"; exit 1; }

# --- package ------------------------------------------------------------------
mkdir -p "$DIST"
ZIP_PATH="$DIST/$ZIP_NAME"
rm -f "$ZIP_PATH"
log "Zipping → $ZIP_PATH"
# ditto preserves the .app bundle structure, symlinks, and code signature.
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

log "Artifact: $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"

# --- publish ------------------------------------------------------------------
if [[ "$PUBLISH_GITHUB" == 0 ]]; then
  log "Skipping GitHub release (--no-github). Done."
  exit 0
fi

if [[ -z "$NOTES" ]]; then
  NOTES=$(cat <<EOF
Dev pre-release built from \`${BRANCH}\` at \`${GIT_SHA}\`.

- Version: ${VERSION}
- Ad-hoc signed only (not notarized) — Gatekeeper will warn on other machines.
- Install: unzip and drag \`${APP_NAME}.app\` to /Applications.
EOF
)
fi

log "Creating GitHub pre-release ${TAG}"
gh release create "$TAG" "$ZIP_PATH" \
  --prerelease \
  --target "$(git rev-parse HEAD)" \
  --title "${APP_NAME} ${VERSION} (dev ${STAMP})" \
  --notes "$NOTES"

log "Done → $(gh release view "$TAG" --json url -q .url)"

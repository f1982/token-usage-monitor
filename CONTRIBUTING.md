# Contributing and Releasing

This project uses GitHub pull requests, squash merges, and GitHub Actions. The
default branch is `main`. Keep generated `TokenUsageMonitor.xcodeproj` files
and local signing configuration out of commits.

## Pull requests

Use a Conventional Commit title for every PR. The title becomes the squash
commit message and is used by Release Please to determine the next version.

| Prefix | Version effect | Example |
| --- | --- | --- |
| `fix:` | patch | `fix(auth): handle expired token` |
| `feat:` | minor | `feat(ui): add usage trend` |
| `feat!:` or `BREAKING CHANGE` | major | `feat!: replace the settings format` |
| `docs:`, `chore:`, `ci:`, `test:`, `refactor:` | no release by itself | `ci: update Xcode runner` |

Before opening a PR, run the relevant tests locally if possible:

```sh
xcodegen generate
xcodebuild \
  -project TokenUsageMonitor.xcodeproj \
  -scheme TokenUsageMonitor \
  -destination 'platform=macOS' \
  test \
  CODE_SIGNING_ALLOWED=NO
```

## Releasing

The normal release flow requires one maintainer to merge the generated Release
Please PR. Do not manually create a version tag for a normal release.

```text
1. Merge one or more feat/fix PRs into main.
2. Wait for the Release Please workflow to create or update a release PR.
3. Review the proposed VERSION bump and CHANGELOG entries.
4. Merge the Release Please PR.
5. Release Please creates vX.Y.Z and a GitHub Release.
6. The vX.Y.Z tag starts the signed macOS release workflow.
7. Verify the workflow and download the uploaded zip from the GitHub Release.
```

### Version rules

`VERSION` is the current released app version. Release Please uses the root
package configured in `release-please-config.json` and records the current
version in `.release-please-manifest.json`.

Normal changes are batched: several merged `feat:` and `fix:` PRs become one
release PR. A `feat:` normally produces a minor bump, while `fix:` produces a
patch bump. Documentation and CI-only changes do not create a release PR on
their own.

If a specific version is required, add a `Release-As: X.Y.Z` footer to the
commit body that lands on `main`, then review the generated release PR
carefully. Prefer the normal Conventional Commit calculation whenever possible.

### One-time GitHub setup

The signed workflow uses the GitHub Environment named `release`.

The Mac App Store workflow is manually started from **Actions → Build Mac App
Store app** and uses a separate `app-store` Environment. It archives with the
Mac App Store distribution identities, exports an App Store `.pkg`, and uploads
it with Transporter. The App Store target has no Sparkle or other GitHub
updater dependency; the GitHub workflow and App Store workflow therefore
produce separate distribution artifacts.

Create the following Environment variables under **Settings → Environments →
release → Environment variables**:

| Name | Value | Secret? |
| --- | --- | --- |
| `APPLE_TEAM_ID` | Apple Developer Team ID | No |
| `APP_BUNDLE_ID` | Production app bundle ID | No |
| `WIDGET_BUNDLE_ID` | Production widget bundle ID | No |
| `APP_GROUP_IDENTIFIER` | Team-scoped App Group ID | No |

Create the following Environment secrets:

| Name | Purpose |
| --- | --- |
| `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD` | Password for the Developer ID `.p12` certificate |
| `DEVELOPER_ID_APPLICATION_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID Application certificate |
| `APP_PROVISIONING_PROFILE_BASE64` | Base64-encoded app provisioning profile |
| `WIDGET_PROVISIONING_PROFILE_BASE64` | Base64-encoded widget provisioning profile |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect API issuer ID |
| `APPLE_API_PRIVATE_KEY_P8` | Raw or Base64-encoded `.p8` private key |

Create `RELEASE_PLEASE_TOKEN` as a **Repository secret**, not an Environment
secret. It should be a fine-grained token scoped only to this repository with
Contents, Issues, and Pull requests set to Read and write. A PAT or GitHub App
token is required so the tag created by Release Please can trigger the signed
release workflow; the default `GITHUB_TOKEN` does not provide that trigger
behavior.

Never commit these values, paste them into an issue, or print them in workflow
logs. Keep local values in an ignored `.env` file only for local tooling.

The `app-store` Environment needs the same four variables as `release` plus
these secrets:

| Name | Purpose |
| --- | --- |
| `APP_STORE_CERTIFICATE_PASSWORD` | Mac App Store application certificate password |
| `APP_STORE_CERTIFICATE_P12_BASE64` | Base64-encoded Mac App Store application certificate |
| `APP_STORE_INSTALLER_CERTIFICATE_PASSWORD` | Mac App Store installer certificate password |
| `APP_STORE_INSTALLER_CERTIFICATE_P12_BASE64` | Base64-encoded Mac App Store installer certificate |
| `APP_STORE_APP_PROVISIONING_PROFILE_BASE64` | App Store app provisioning profile |
| `APP_STORE_WIDGET_PROVISIONING_PROFILE_BASE64` | Widget provisioning profile |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect API issuer ID |
| `APPLE_API_PRIVATE_KEY_P8` | App Store Connect API private key |

### What the workflows do

`.github/workflows/release-please.yml` runs after pushes to `main`. It reads
Conventional Commit history, updates the release PR, and manages the version,
changelog, tag, and GitHub Release.

`.github/workflows/release.yml` runs for `v*` tags and performs these steps:

1. Resolves and validates the version from the tag.
2. Installs XcodeGen and selects the configured Xcode runner.
3. Validates all signing and notarization configuration.
4. Creates a temporary keychain and imports the Developer ID certificate.
5. Installs the app and widget provisioning profiles.
6. Generates the Xcode project and runs the unit tests without signing.
7. Archives the app with Developer ID signing and the release version.
8. Submits the app to Apple notarization and staples the ticket.
9. Uploads `TokenUsageMonitor-X.Y.Z.zip` to the existing GitHub Release.

The workflow is intentionally compatible with Release Please creating the
GitHub Release before the signed artifact is ready. It uploads the zip to that
release, and can still create a release itself for a manually supplied tag.

### Verifying a release

Use GitHub CLI from the repository root:

```sh
gh run list --workflow release-please.yml --limit 5
gh run list --workflow release.yml --limit 5
gh run view RUN_ID --log
gh release view vX.Y.Z
```

A successful release must have:

- a successful Release Please run;
- a `vX.Y.Z` tag and non-draft GitHub Release;
- a successful macOS release workflow;
- a `TokenUsageMonitor-X.Y.Z.zip` asset on that release.
- a matching `TokenUsageMonitor-X.Y.Z.zip.sha256` asset; verify it with
  `shasum -a 256 -c TokenUsageMonitor-X.Y.Z.zip.sha256`.

## Developer pre-releases

For a quick, ad-hoc signed build without Apple notarization, use:

```sh
scripts/dev-release.sh --no-github
```

To publish a GitHub pre-release, authenticate `gh` first and omit
`--no-github`:

```sh
gh auth status
scripts/dev-release.sh
```

Developer pre-releases are not production releases: they use ad-hoc signing,
are not notarized, and Gatekeeper may warn on other machines.

## Manual recovery

Use **Actions → Release macOS app → Run workflow** only when a tag was not
created, a release artifact must be rebuilt, or an operator has deliberately
chosen a version outside the Release Please flow. The manual input must be a
full semantic version such as `1.0.2`.

If a GitHub Release already exists, the workflow uploads or replaces the zip;
it does not create a duplicate release.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No Release Please PR | Confirm the merged PR title starts with `feat:` or `fix:` and inspect the Release Please run log. |
| `root package ... not configured` | Check that `release-please-config.json` contains the `"packages": { ".": ... }` entry. |
| Tag exists but macOS workflow did not start | Check that `RELEASE_PLEASE_TOKEN` is a PAT/GitHub App token, not the default `GITHUB_TOKEN`. |
| Missing release variable/secret | Check the `release` Environment spelling and the exact names in the tables above. |
| Certificate identity not found | Re-export the Developer ID Application certificate and update its Base64 secret/password. |
| Provisioning profile metadata error | Re-export the matching app/widget profiles and update both Base64 secrets. |
| Notarization fails | Check the App Store Connect API key ID, issuer ID, private key format, and Apple account access. |
| Local Xcode build asks for a Team | Use `CODE_SIGNING_ALLOWED=NO` or configure local signing without committing it. |

When debugging, start with the failing GitHub Actions step and its run log. Do
not retry a release blindly if a tag or GitHub Release already exists; inspect
the release first and rerun only the necessary workflow.

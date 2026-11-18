# Railty CI/CD Maintenance Guide

## Workflow Boundaries (Railty vs. Upstream Ghostty)

Railty maintains two dedicated workflows while keeping the remaining upstream Ghostty workflows untouched in `.github/workflows/` and disabled at the GitHub repository level (`disabled_manually`):

- **Railty workflows (active)**:
  - `.github/workflows/ci-railty.yml`: Lightweight daily CI on `ubuntu-latest` for `push` / `pull_request` to `main`.
  - `.github/workflows/release-railty.yml`: Apple Silicon (`arm64`) macOS release build, artifact packaging, GitHub Release publishing, and Homebrew Tap update.
- **Upstream Ghostty workflows (disabled in GitHub Actions, files kept unmodified)**:
  - `test.yml`, `publish-tag.yml`, `nix.yml`, `flatpak.yml`, `snap.yml`, `clean-artifacts.yml`, `milestone.yml`, `update-colorschemes.yml`, `vouch-check-issue.yml`, `vouch-check-pr.yml`, `vouch-manage-by-discussion.yml`, `vouch-manage-by-issue.yml`, `vouch-sync-codeowners.yml`.
  - Keeping these files unmodified prevents merge conflicts when pulling from upstream Ghostty / Sidegeist while ensuring they never consume runners or attempt upstream R2/Sentry/nightly publishes.

## Daily Development (`ci-railty.yml`)

Runs automatically on `push` to `main` and `pull_request` targeting `main` (`ubuntu-latest`, `contents: read`):

1. Validates `.github/workflows/ci-railty.yml` and `.github/workflows/release-railty.yml` YAML syntax.
2. Runs `shellcheck` on `dist/macos/*.sh`.
3. Runs `py_compile` and a temporary-file smoke test on `dist/homebrew/update_cask.py` plus `ruby -c`.
4. Checks `zig fmt --check build.zig src/` only when `build.zig`, `build.zig.zon`, or `*.zig` files changed (doc/asset-only changes skip Zig entirely and never launch macOS builds).

## Manual Test Builds (`workflow_dispatch`)

Run **Railty Release** manually from the GitHub Actions UI (or `gh workflow run release-railty.yml`):

- `version`: Version string in `vX.Y.Z` format (default `v0.1.0`).
- `create_draft_release`: Defaults to `false`.
  - When `false`, only uploads the `railty-macos-arm64` workflow artifact (retained for 14 days).
  - When `true`, also creates a Draft GitHub Release tagged `test-vX.Y.Z`.
- Manual runs never update `vendettar/homebrew-railty`.

## Official Releases (`vX.Y.Z` Tag Push)

1. Push a semantic version tag matching `v[0-9]*.[0-9]*.[0-9]*` (e.g., `git tag v0.1.2 && git push origin v0.1.2`).
2. `build-macos` checks that `vX.Y.Z` is not already published with `Railty-macos-arm64.zip` (failing fast instead of overwriting), builds `GhosttyKit` (`arm64` native with `-Dxcframework-target=native` and pinned Zig `0.17.0`) and `Railty.app`, verifies `com.vendettar.railty` metadata and Railty icon assets, and publishes the GitHub Release once.
3. `update-homebrew-tap` runs on `ubuntu-latest`, verifies the published Release ZIP is downloadable and matches the build SHA-256, updates `Casks/railty.rb` in `vendettar/homebrew-railty`, verifies Ruby syntax, and commits/pushes if changed.

## Secrets & Homebrew Tap Setup

- `HOMEBREW_TAP_DEPLOY_KEY` (**required for automated Tap updates**): Private key of a write-capable deploy key installed on `vendettar/homebrew-railty`.
  - If unset, `update-homebrew-tap` fails explicitly and prints manual update details in the job summary rather than reporting a false success.
- Optional Apple signing & notarization secrets (workflow defaults to consistent ad-hoc signing when omitted):
  - `RAILTY_SIGNING_IDENTITY`, `RAILTY_SIGNING_CERTIFICATE_B64`, `RAILTY_SIGNING_CERTIFICATE_PASSWORD`, `RAILTY_KEYCHAIN_PASSWORD`
  - `APPLE_NOTARIZATION_ISSUER`, `APPLE_NOTARIZATION_KEY_ID`, `APPLE_NOTARIZATION_KEY`

## Syncing Upstream Ghostty / Sidegeist

1. Fetch and merge/rebase upstream changes as usual (`git fetch upstream && git merge upstream/<branch>`).
2. Because upstream workflow files in `.github/workflows/` are untouched, upstream workflow edits should merge cleanly without touching Railty's `ci-railty.yml` or `release-railty.yml`.
3. If upstream introduces any new workflow file, disable it immediately so it does not run in `vendettar/railty`:

```bash
gh workflow list --all --repo vendettar/railty
gh workflow disable <new-workflow.yml> --repo vendettar/railty
```

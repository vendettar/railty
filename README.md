# 🛤️ Railty

**A lightweight, native macOS terminal with vertical tabs.**

Keep the speed and simplicity of Ghostty, with a better tab experience.

Railty is a free, open-source, community-driven macOS terminal fork maintained independently. It is derived from Ghostty Sidegeist, which is itself based on Ghostty.

## Features

- **Native vertical tabs** — a sidebar shows tab titles, working directories, Git branches, and custom status entries.
- **Tab management** — rename, color, close, and reorder tabs; drag tabs between windows or out into a new window.
- **Attention indicators** — identify tabs with terminal bells or notifications.
- **Git panel** — inspect the selected tab's branch, sync status, and changed files; checkout branches, commit, push, and pull. Open changed files in your configured editor.
- **Ghostty terminal engine** — terminal rendering and core terminal behavior are powered by Ghostty.
- **macOS-native interface** — built with the platform's native app and window frameworks. Sidebar colors follow the terminal palette, with controls for card borders and inactive tab colors.
- **Tab control CLI** — the included `ghosttyctl` utility can rename tabs, set status and color metadata, send notifications, and query tab state.

## Screenshots

![Railty's vertical sidebar showing terminal tabs, working directories, Git branches, and status](https://github.com/user-attachments/assets/919a9220-4e07-4b2e-b491-c9d385b6585f)

## Installation

Install with Homebrew from the Railty tap:

```sh
brew tap vendettar/railty
brew install --cask railty
```

Update or uninstall later with:

```sh
brew update
brew upgrade --cask railty
brew uninstall --cask railty
```

You can also download `Railty-macos-arm64.zip` directly from
[GitHub Releases](https://github.com/vendettar/railty/releases) and copy
`Railty.app` into `/Applications`. Releases are built by the
`Railty Release` workflow when a `v*` tag is pushed.

- Supported macOS: 13.0 (Ventura) or later.
- Supported CPU: Apple Silicon (arm64) only at present. The published ZIP is
  **not** a Universal binary; Intel builds are not shipped yet.
- Signing: release builds use a stable ad-hoc signature unless Developer ID
  signing and notarization secrets are configured. Unsigned builds do not
  enable Hardened Runtime, because the bundled Sparkle framework has no
  matching Team ID. Such builds may be blocked by macOS Gatekeeper; Homebrew
  installs normally clear the download quarantine. To approve a manually
  downloaded copy, use System Settings → Privacy & Security, or right-click
  the app and choose Open.
- Coexistence: `Railty.app` uses the bundle ID `com.vendettar.railty`
  and its own Application Support directory, so it does not replace or delete
  an official `Ghostty.app`. The shared Ghostty config file
  (`~/.config/ghostty/config.ghostty`) is still read.
- App icon: Railty ships a single original icon (see [`branding/`](branding/))
  used in Finder, the Dock, Launchpad, the app switcher, and About. The upstream
  Ghostty icon variants and custom-style layers are not distributed. Legacy
  `macos-icon` values from upstream configs are still accepted but fall back to
  the Railty icon; `macos-icon = custom` with `macos-custom-icon` still works.

To build from source instead, see [HACKING.md](HACKING.md); the pinned Zig
version is declared in [`build.zig.zon`](build.zig.zon). Building the macOS app
requires Xcode, the macOS SDK, and the Metal Toolchain.

### Releasing

Push a `vX.Y.Z` tag to build and publish a release:

```sh
git tag v0.1.0
git push origin v0.1.0
```

`workflow_dispatch` on the same workflow creates a **draft** test release
instead of a public one. Optional repository secrets:

| Secret | Purpose |
| --- | --- |
| `RAILTY_SIGNING_IDENTITY`, `RAILTY_SIGNING_CERTIFICATE_B64`, `RAILTY_SIGNING_CERTIFICATE_PASSWORD`, `RAILTY_KEYCHAIN_PASSWORD` | Developer ID signing |
| `APPLE_NOTARIZATION_ISSUER`, `APPLE_NOTARIZATION_KEY_ID`, `APPLE_NOTARIZATION_KEY` | Notarization |
| `HOMEBREW_TAP_TOKEN` | Fine-grained PAT with write access to `vendettar/homebrew-railty`, used to update the Cask after a published release |

Without `HOMEBREW_TAP_TOKEN`, update `Casks/railty.rb` in the tap manually
using the version, URL, and SHA-256 printed in the release workflow summary.

## Configuration

Add these supported settings to your Ghostty configuration file:

```ini
# Tab card fields: title, directory, git-branch, status (all shown by default)
sidebar-fields = title,directory,git-branch,status

# Show the Git panel at the bottom of the sidebar (default: true)
sidebar-git = true
```

Set `sidebar-git = false` to hide the Git panel. Status entries can be set from the CLI:

```sh
ghosttyctl rename "Build"
ghosttyctl set-status task "Compiling" --icon hammer
ghosttyctl notify --title "Build" --body "Finished"
ghosttyctl list
```

The CLI script is `cli/ghosttyctl`. From the repository root, you can put it on your `PATH` with:

```sh
mkdir -p "$HOME/.local/bin"
ln -s "$PWD/cli/ghosttyctl" "$HOME/.local/bin/ghosttyctl"
```

Ensure `$HOME/.local/bin` is on your `PATH`.

## Development

Use `zig build` to build the app and `zig build test` to run the Zig test suite. [AGENTS.md](AGENTS.md) lists repository commands, and [HACKING.md](HACKING.md) documents the inherited build environment and technical workflow.

Contributions should target this repository. Submit proposed changes as pull requests to Railty.

## Upstream and Credits

Railty is independently maintained and derived from [Ghostty Sidegeist](https://github.com/tomreinert/ghostty-sidegeist), created by [Tom Reinert](https://github.com/tomreinert). Ghostty Sidegeist is based on [Ghostty](https://github.com/ghostty-org/ghostty). Thanks to Tom Reinert, Mitchell Hashimoto, and the contributors to both upstream projects for the work Railty builds on.

Railty is not an official Ghostty project or release.

## License

Railty is distributed under the MIT License. See [LICENSE](LICENSE) for the full text and preserved copyright notice for Mitchell Hashimoto and Ghostty contributors.

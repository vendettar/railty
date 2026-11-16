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

There is no Railty-specific macOS release package yet. Build from source on macOS:

```sh
git clone https://github.com/vendettar/railty.git
cd railty
zig build
```

Install the Zig version specified in [`build.zig`](build.zig). Building the macOS app also requires Xcode, the macOS SDK, and the Metal Toolchain. See [HACKING.md](HACKING.md) for build environment details.

The macOS app target still uses the inherited Ghostty app name and bundle identity.

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

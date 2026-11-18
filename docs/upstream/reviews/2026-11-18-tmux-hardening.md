# tmux Hardening & DEFER Priority Correction (2026-11-18)

Upstream: Ghostty `7e4cc4fae0`, `51e7fe51db`; Railty `main` at `a805f5a38` (start of round).

## 1. Is tmux Control Mode enabled in the release build?

**Yes.**

- `src/terminal/build_options.zig` sets `tmux_control_mode = self.oniguruma`.
- `Config.terminalOptions(.ghostty, …)` sets `oniguruma = true` unconditionally (`src/build/Config.zig`).
- `SharedDeps` applies those `.ghostty` options to every executable/app core step (`src/build/SharedDeps.zig`), and links the bundled Oniguruma dependency.
- Therefore the macOS app / GhosttyKit includes `terminal.tmux` and the control parser; a user running tmux in control mode can reach these paths.

## 2. Which `7e4cc4fae0` problems exist in Railty?

| Upstream problem | In Railty? | Notes |
|---|---|---|
| `%window-close` / `%unlinked-window-close` oversized id | **No handler** | Those notifications are part of the still-deferred tmux feature chain; Railty logs them as unknown. |
| `%session-window-changed` oversized id | **No handler** | Same; feature chain not integrated. |
| Oversized ids crash other notifications | **Yes** | Seven `std.fmt.parseInt(...) catch unreachable` sites existed: `%output`, `%session-changed`, `%layout-change`, `%window-add`, `%window-renamed`, `%window-pane-changed` (window + pane), `%client-session-changed`. |
| `list-windows` partial parse leaks layout arenas | **Yes** | `receivedListWindows` used `defer windows.deinit(...)`, which frees the list buffer but not each `Window.layout_arena` when a later line fails. |

## 3. Adaptation (branch `sync/ghostty-tmux-hardening`)

- Added `parseDecimalId` (digits only, `usize` overflow → null) and replaced every existing `catch unreachable` id parse with it; invalid ids are logged and the notification is dropped. This is broader than the upstream commit because Railty does not carry the two notifications the upstream patch targets.
- Ported the `receivedListWindows` ownership fix: `errdefer` frees already-parsed windows (layout arenas), then transfers the list to `self.windows` without freeing arenas after `syncLayouts`.
- `%output` now uses byte-safe manual parsing (no Oniguruma regex): pane id via `parseDecimalId`, data taken verbatim to end of line, empty data accepted. `std.mem.findScalar` was replaced with `std.mem.indexOfScalar` for Zig `0.17.0` compatibility.
- No notification/feature semantics were added; no Sidegeist files touched.

Commits:

| Commit | Content |
|---|---|
| `a08a3f354` | oversized-id hardening + list-windows arena cleanup |
| `d754c5520` | `%output` byte-safe parsing |
| `1eca92330` | regression test for partial `list-windows` failure |

## 4. Tests and build

| Check | Result |
|---|---|
| `zig build test -Demit-macos-app=false -Dtest-filter=tmux` | passed |
| `zig build test -Demit-macos-app=false -Dtest-filter=list-windows` | passed |
| New: notification ids reject overflow (8 inputs, incl. both pane ids) | passed |
| New: `%output` invalid UTF-8 / empty data / oversized id / malformed lines | passed |
| New: partial `list-windows` failure frees parsed layouts (testing allocator leak check) | passed |
| macOS arm64 build, run `44136063086` | success (workflow_dispatch, no Release/Cask changes) |
| Runtime smoke (experimental build) | passed: tmux 3.8 client `control=1`; echo, split-window, and non-UTF-8 pane output all stable, app stayed alive |

Runtime smoke notes: the app was launched with `-e tmux -CC` from the downloaded arm64 artifact; `tmux list-clients` reported `control=1`, AppleScript reported one window/tab named `tmux`, and `echo RUNTIME_OK`, `split-window`, and `printf '\377\376\n'` did not terminate the app or disconnect the control client. The macOS app still leaves `Viewer.Action.windows` unimplemented (TODO in `stream_handler.zig`), so tmux windows do not become Railty tabs; this test covers the parser/command path, not multi-window UI.

## 5. Integration status

**Merged into `main`** as `c6ba91955` (oversized-id hardening + list-windows arena cleanup), `5b68f2b74` (`%output` byte-safe parsing), and `4a61fda77` (list-windows leak regression test). Branch `sync/ghostty-tmux-hardening` was the validation branch and is deleted after merge. No Sidegeist conflict was found. No release was created.

## 6. DEFER priority corrections

Kept the ledger `category` untouched; only queue execution priority changed:

| Commit(s) | Was | Now | Reason |
|---|---|---|---|
| `faa346b068`, `22b8451441`, `4c92f80954` | P1 | P2 | Follow-up fixes for the unintegrated Print Fast Path (`68750a1be2`); not current Railty bugs. |
| `636c1d7805`, `738d8f7f5b`, `38f4a710e3`, `31a52992f1` | P1 | P2 | Follow-up fixes for the unintegrated RefCountedSet change (`d03983f02c`). |
| `9b848b0f5c` (snapshot capacity) | P1 | P2 | No macOS snapshot consumer; no runtime path. |
| `0e067ded70` (nullability) | P1 | P1 | Kept as the one non-tmux item worth watching; not executed this round. |

Queue now: `P1 4 / P2 40 / P3 102` (146 entries; the two tmux entries moved to `INCLUDE`), statuses `candidate_next_batch 1` (CR pin), `awaiting_validation 20`, others unchanged.

The only new upstream commit since the last review is `b634352b7` (VOUCHED list update, docs/CI) — no security or stability impact.

## 7. Remaining DEFER items worth active attention

1. **macOS C API nullability `0e067ded70`** — source-breaking; only with a dedicated Swift pass or a Sidegeist core upgrade.
2. **tmux feature chain `7e7968826f`, `c2d93620ef`, `9a92081882`** — only if fuller tmux control-mode behavior (e.g. tmux windows as tabs) is wanted; not needed for the hardening above.

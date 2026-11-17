# macOS C API Nullability — Compatibility Assessment

> **历史记录（重写前）**：评估基线 `ab61a1099` 已不在当前 `main` 历史中。当前 SHA 见 [2026-11-17-v1.2-lite.md](2026-11-17-v1.2-lite.md#当前-sha强推后)。

**Upstream commit:** `0e067ded703c4212248daf996f97c62f2f13114a`
**Subject:** `core: declare pointer nullability in ghostty.h`
**Assessed:** 2026-11-17 against Railty `ab61a1099`

## 1. What the commit does

- Adds `GHOSTTY_NONNULL` / `GHOSTTY_NULLABLE` / `GHOSTTY_NULL_UNSPECIFIED` macros to `include/ghostty.h` and wraps the header in `#pragma clang assume_nonnull begin/end`.
- Annotates the genuinely nullable pointers (clipboard contents, preedit, etc.) instead of relying on implicit-optional import.
- Fixes call sites that previously passed NULL where the Zig side requires non-null:
  - `ghostty_set_window_background_blur` callers now guard their optional value.
  - `readSelection` guards optional data.
  - `Config.backgroundColor` guards its optional value.
- Makes `ghostty_surface_preedit` accept a nullable pointer on the Zig side because clearing the preedit passes NULL.

Size: 12 files, +139/−153 (`include/ghostty.h` alone is ~102 changed lines). The commit explicitly calls itself **source-breaking for Swift embedders**.

## 2. Railty conflict surface

| File | Overlap with Railty / Sidegeist | Risk |
|---|---|---|
| `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` | Railty ported `4edde79c03` (split activation) here | Medium — small hunks but same file |
| `macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift` | **Sidegeist core** (vertical tabs / window chrome) | High |
| `macos/Sources/Features/QuickTerminal/QuickTerminalController.swift` | Sidegeist quick terminal behavior | Medium |
| `macos/Sources/Ghostty/Ghostty.App.swift` | C bridge callbacks used by all surfaces | Medium |
| `macos/Sources/Ghostty/Ghostty.Action.swift`, `Ghostty.Config.swift`, `GhosttyPackage.swift` | Shared bridge types | Medium |
| `macos/Sources/Helpers/Extensions/Array+Extension.swift` | Small helper | Low |
| `src/apprt/embedded.zig` | Shared app runtime | Low–Medium |
| `macos/Tests/.../SurfaceView+SearchStateTests.swift` | Test expectations | Low |

## 3. Why it was not ported in this round

1. **Verification barrier.** Nullability errors are Swift *type-check* errors, not syntax errors. This host has only Command Line Tools; `swiftc -parse` cannot validate them and `xcodebuild` is unavailable. A branch could only be verified by the `xcode-27` CI build, which compiles but does not exercise the new guards at runtime.
2. **Safety requirement.** The task explicitly forbids masking nil with force unwraps (`!`). Every changed call site needs a semantic audit against the Zig declaration (`src/apprt/embedded.zig`, `include/ghostty.h`) before accepting the upstream `guard` choices.
3. **Sidegeist merge cost.** `TerminalWindow.swift` is the highest-conflict file in the repo; combining this commit with a window-theme port or a Sidegeist upgrade would multiply conflicts.

## 4. Decision

| Field | Value |
|---|---|
| Integration | **Not integrated** |
| Ledger decision | `DEFER` (unchanged) |
| Queue group | `macos-c-api-nullability` |
| Priority | `P1` |
| Review status | `awaiting_validation` |
| Revisit trigger | `manual_dedicated_port` |

## 5. Required plan before any merge

1. Create `sync/ghostty-macos-nullability` from current `main`; cherry-pick `0e067ded70` (expect conflicts in `TerminalWindow.swift` and `SurfaceView_AppKit.swift`).
2. Resolve conflicts by **semantic equivalence**, not by restoring unsafe implicit-optional signatures or adding `!`.
3. For each of `set_window_background_blur`, `readSelection`, `Config.backgroundColor`, and preedit clearing, add or keep an explicit optional guard and record why the pointer can be NULL.
4. Run full `xcodebuild -target Ghostty` via the `xcode-27` `release-railty.yml` `workflow_dispatch` build.
5. Runtime smoke on a GUI host: launch/quit, new/close tab, split focus + mouse, quick terminal, clipboard confirmation, search, background blur. Mark `NOT_TESTED` items explicitly until done.
6. Only then consider merging; otherwise keep this commit deferred.

## 6. Value

This is a correctness/safety improvement rather than a performance one: it turns silent NULL-passing bugs into compile-time errors. It does not fix an observed Railty crash today, which is why it stays `P1 / awaiting_validation` instead of being forced in.

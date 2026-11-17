# Railty Upstream Initial Baseline Audit (2026-11-17)

> **Historical snapshot (archived)**: This report preserves the original conclusions from the initial audit. Its statement that "no upstream code has yet been merged or cherry-picked into Railty `main` (Integrated = 0)" describes the state at that time only and **is no longer valid**. All 45 `INCLUDE` items have been ported, validated, and released. For the current authoritative status, read [2026-11-17-integration-complete.md](2026-11-17-integration-complete.md), [state.json](../state.json), and [ledger.jsonl](../ledger.jsonl). **Do not repeat the ports described in Section 6 of this report.**

This report was generated from real local Git history, actual `git show` diffs, and the per-entry ledger [ledger.jsonl](../ledger.jsonl). It records the results of the first complete baseline audit performed when the Railty dual-upstream sync mechanism was established.

> **Status statement**: This task completed baseline verification, established the process, and performed a **commit-by-commit review (Reviewed)** of all 395 Ghostty post-`v1.4.0` commits, aggregating them by **PR, feature topic (`topic`), and dependency chain (`dependencies`)**, while retaining an independent tracking record for each commit in [ledger.jsonl](../ledger.jsonl). **No upstream code has yet been merged or cherry-picked into Railty `main` (Integrated = 0)**; subsequent workers only need to review incrementally after `5ebe501a63425b13d9952e8c54682c046386e5af`.

---

## 1. Three-Repository Baselines and Git Topology

| Repository / Ref | Actual Commit SHA | Commit Date | Tag / Version Notes |
|---|---|---|---|
| **Railty (`HEAD` / `origin/main`)** | `f81a05d702f6f757fd6715833d7f7b4c107f6641` | 2026-11-17 | `v0.1.2` (includes Railty branding, icon, CI/CD, Homebrew Tap) |
| **Sidegeist (`sidegeist/main`)** | `5904a523477542b114939d93594f82348f27b3b5` | 2026-10-28 | `v1.4.0-fork.1` (`Merge upstream v1.4.0`) |
| **Ghostty Stable (`v1.4.0`)** | `83fb95624b0439ee660c2679b43b38c8b63769cd` | 2026-10-27 | Latest stable release `v1.4.0` (tag object `ce787fc18a`) |
| **Ghostty Main (`ghostty/main`)** | `5ebe501a63425b13d9952e8c54682c046386e5af` | 2026-11-16 | Development mainline (`1.4.1-dev`; `vt-1.0.1` was branched off in 2026-11) |

### Measured Topology Results

- **`merge-base(HEAD, sidegeist/main)`** = `5904a523477542b114939d93594f82348f27b3b5`
  - **Sidegeist ahead of Railty**: `0` commits (Railty already fully contains the entire history of Sidegeist `main`).
  - **Railty ahead of Sidegeist**: `8` commits (`9ebc075a7..f81a05d70`, all Railty branding, icon, `railtyctl` identifier, `ci-railty.yml`, `release-railty.yml`, packaging/signing scripts, and Homebrew Tap).
- **`merge-base(HEAD, ghostty/main)`** = `83fb95624b0439ee660c2679b43b38c8b63769cd` (Ghostty `v1.4.0`)
- **`merge-base(sidegeist/main, ghostty/main)`** = `83fb95624b0439ee660c2679b43b38c8b63769cd` (Ghostty `v1.4.0`)
- **Total new commits in Ghostty `v1.4.0..ghostty/main`**: `395` commits
  - `--first-parent` commits: `162`
  - Merge commits: `128` (diff verification found `0` evil merges / extra conflict-resolution changes)
  - Non-merge substantive commits: `267`
- **Patch-ID overlap detection**: `git patch-id --stable` comparison between the commits where `HEAD` is ahead of `v1.4.0` and Ghostty's 267 non-merge commits found an overlap count of `0`.
- **Fetch caveat**: Both `ghostty` and `sidegeist` have a `tip` tag with the same name, and `v0.1.0`/`v0.1.1` already exist locally. Fetching the two upstreams must use `git fetch --no-tags <remote> +refs/heads/main:refs/remotes/<remote>/main`, together with a read-only check of remote tags via `git ls-remote --tags <remote>`.

---

## 2. Per-Commit Audit Statistics

Review range: `83fb95624b0439ee660c2679b43b38c8b63769cd..5ebe501a63425b13d9952e8c54682c046386e5af` (`395` entries total, 100% written to [ledger.jsonl](../ledger.jsonl)).

### Distribution by Decision and Risk

| Decision Status | All 395 Commits | Non-Merge 267 Commits | Risk Distribution (`risk`) | Notes |
|---|---:|---:|---|---|
| **`INCLUDE`** | **45** | **45** | `low`: 40, `medium`: 5 | Determined suitable for Railty, placed in the priority port queue (including prerequisite dependency chains) |
| **`DEFER`** | **149** | **149** | `high`: 118, `medium`: 31 | Constrained by Zig `0.17.1`, chained refactors/performance waves, Swift conflicts, or waiting on Sidegeist |
| **`SKIP`** | **201** | **73** | `none`: 201 | 128 pure merge wrapper nodes + 73 unrelated commits (translations, VOUCHED, Linux/GTK/Win/Android, website/official CI) |
| **`ALREADY_INCLUDED`** | **0** | **0** | — | No pre-ported or overlapping patches at present |
| **`NEEDS_REVIEW`** | **0** | **0** | — | All 395 commits have been classified and judged based on real diffs |

### Distribution by Commit Category

| Category (`category`) | Count | Main Composition |
|---|---:|---|
| `Build / Toolchain` | 107 | `libghostty-vt` 1.0 C ABI/dependency cleanup, Zig `0.17.1` upgrade, build scaffolding |
| `Docs / CI` | 78 | VOUCHED, translations (`po/`), website docs, GitHub Actions |
| `Refactor` | 71 | Internal architecture cleanup, Unicode/PageList/Render refactors |
| `Critical Bug` | 57 | Terminal core resize/reflow, Kitty graphics memory, config/cli/simdutf/font stability fixes |
| `Performance` | 26 | PageList `carried_capacity`, packed `u128` Style, blank row fast path, SIMD optimizations |
| `Tests` | 17 | Regression tests and test infrastructure fixes |
| `macOS Bug` | 16 | macOS 27 tab bar frame, Swift MainActor isolation, clipboard quit, split mouse, selection copy |
| `Platform-specific` | 13 | Linux/GTK, FreeBSD, Windows, Android specific changes |
| `New Feature` | 7 | DECIC/DECDC/DECBI/DECFI, tmux active_window, `set_window_theme`, iTerm2 color updates |
| `Security` | 3 | `circ_buf` arithmetic overflow and capacity overflow checks, `os/exe` path null terminator space reservation |

---

## 3. Aggregated View by Feature Topic (`topic`) and PR (all 395 entries)

Each commit's individual `sha`, `pr`, `merge_commit`, `dependencies`, and `risk` are stored in [ledger.jsonl](../ledger.jsonl); the table below gives an aggregated view of all 395 records by feature topic:

| Feature Topic (`topic`) | Commit Count | INCLUDE | DEFER | SKIP | Risk Level | Notes |
|---|---:|---:|---:|---:|---|---|
| `security-circbuf` | 6 | 4 | 0 | 2 | **Low** | `#14958` + `#14987` complete 4-fix chain + 2 merges |
| `security-exe-path` | 2 | 1 | 0 | 1 | **Low** | `#15058` standalone fix + 1 merge |
| `macos-ui-input` | 18 | 6 | 1 | 11 | **Low–Medium** | `#14999`, `#14971`, `#15040`, `#15029`, `#15190`, `#15147` included; `#15039` deferred |
| `terminal-core-resize-render` | 20 | 10 | 2 | 8 | **Low** | resize/reflow/formatter/OOM retry fixes (`#14918`..`#15237`) |
| `terminal-kitty-graphics` | 10 | 4 | 1 | 5 | **Low** | `#15094`, `#15086`, `#15103`, `#15184` included; `#15225` test adjustment deferred |
| `config-cli-split` | 15 | 9 | 0 | 6 | **Low** | `#14876`, `#14879`, `#14904`, `#14908`, `#14921`, `#14950`, `#15073` |
| `cli-ssh-terminfo` | 7 | 4 | 0 | 3 | **Low** | `#14916` → `#15061` → `#15112` complete SSH terminfo chain |
| `simd-utf8` | 10 | 2 | 3 | 5 | **Low** | `#15156`/`#15162` UTF-8 error-code fixes included; x86 AVX-512 deferred |
| `font-discovery-fallback` | 5 | 3 | 1 | 1 | **Low** | `#15216` 3 font discovery/fallback fixes included; fontconfig bump deferred |
| `build-darwin-quirk` | 4 | 2 | 0 | 2 | **Medium** | `#15189` Darwin memset quirk fix (note: separate the `.github/workflows/test.yml` change) |
| `libghostty-vt-and-deps` | 119 | 0 | 76 | 43 | **High** | `libghostty-vt 1.0` C ABI/doxygen/dependency split, pending Sidegeist major version integration |
| `terminal-perf-pagelist-fastpath` | 48 | 0 | 28 | 20 | **High** | `carried_capacity`, `Style` bit packing, `RowBuilder/print` fast path and the subsequent regression fix chain |
| `terminal-refcounted-set` | 8 | 0 | 7 | 1 | **High** | `#15121` dead-ID reuse and paged reference counting refactor chain |
| `terminal-misc-refactor` | 34 | 0 | 12 | 22 | **Medium** | Internal refactors, CSI parsing cleanups, and differential test tuning |
| `tmux-control-mode` | 10 | 0 | 8 | 2 | **Medium** | `#14273`, `#14947` tmux protocol and test change chain |
| `new-features-themes` | 10 | 0 | 6 | 4 | **Medium–High** | `DECIC/DECDC/DECBI/DECFI`, `set_window_theme` (conflicts with Config), iTerm2 color schemes |
| `toolchain-zig-upgrade` | 6 | 0 | 4 | 2 | **High** | `#15230` Zig `0.17.1` upgrade (Railty CI currently pins `0.17.0`) |
| `platform-non-macos` | 10 | 0 | 0 | 10 | **None** | Linux/GTK/FreeBSD/Windows/Android specific commits |
| `i18n-docs-ci` | 53 | 0 | 0 | 53 | **None** | `po/` translations, `VOUCHED`, website docs, upstream CI |

---

## 4. Priority Inclusion List and Risk Levels (`INCLUDE` = 45)

> The standalone fixes and dependency chains below have all passed `git apply --check` or conflict pre-checks, and can be ported group by group on the sync branch `sync/ghostty-fixes-*` with `git cherry-pick -x`, followed by build/test validation.

### A. Security Fixes (`Low` Risk — 5)

| Order / PR | Commit SHA | Content | Dependency Chain | Risk Level | Validation Requirement |
|---|---|---|---|---|---|
| `#145` / `#15058` | `2d1f9cf109` | `os: reserve space for executable path terminator` | Standalone | **Low** | `zig build test -Dtest-filter=exe` |
| `#61` / `#14958` | `9644c7571d` | `datastruct: fix clearing circular buffers with zero capacity` | Chain start | **Low** | `zig build test -Dtest-filter=circ_buf` |
| `#88` / `#14987` | `5e7714e71c` | `datastruct: prevent overflow in circular buffer arithmetic` | `← 9644c7571d` | **Low** | Same as above |
| `#89` / `#14987` | `0aa2f7caf5` | `datastruct: use checked addition for buffer capacity` | `← 5e7714e71c` | **Low** | Same as above |
| `#90` / `#14987` | `c7eb3e8b96` | `datastruct: restore circular buffer explanations` | `← 0aa2f7caf5` | **Low** | Same as above |

### B. macOS-Specific Fixes (`Low`–`Medium` Risk — 6)

| Order / PR | Commit SHA | Content | Risk Level | Cautions |
|---|---|---|---|---|
| `#100` / `#14971` | `f7b25c8129` | `termio: don't require RFC 1123 hostnames in OSC 7` | **Low** | Directly fixes Sidebar directory display for non-RFC 1123 hostnames |
| `#138` / `#15040` | `b148bf7285` | `macos: allow quitting with a clipboard confirmation open` | **Low** | Requires a macOS Xcode build + manual test of quitting with a dialog open |
| `#147` / `#15029` | `0edfc656fa` | `macOS: fix tab bar frame on macOS 27 when it first appears.` | **Low** | Requires verifying Sidegeist vertical/native tab bar display state |
| `#98` / `#14999` | `fd29936f09` | `macos: make Surface main actor-isolated` | **Medium** | Requires validating Sidegeist `SurfaceView` / `TerminalController` Swift 6 concurrency compilation |
| `#349` / `#15190` | `4edde79c03` | `macos: fix split activation mouse handling` | **Medium** | Verify Sidegeist `TerminalWindow`/`BaseTerminalController` mouse focus logic before porting |
| `#375` / `#15147` | `a0fe573fe3` | `config: copy-on-select defaults to the selection clipboard on macOS` | **Medium** | Touches `Config.zig`; confirm it does not override Sidegeist config defaults |

### C. Terminal Core, Resize, Rendering, and Kitty Graphics (`Low` Risk — 14)

- **Resize / Formatter / Selection / Render (10, Low Risk)**:
  - `f761046d6b` (`#36`, `#14918`): `formatter: restore a pending wrap at the right margin`
  - `5ce2325ec6` (`#191`, `#15085`): `terminal: clear cursor pin garbage flag after resize`
  - `de202be94a` (`#230`, `#15113`): `terminal: keep triple-click selection over blank lines`
  - `1b8b3f55bc` (`#275`, `#15134`): `terminal: remap pins when the column growth backfill stops early`
  - `b543fbed1a` (`#281`, `#15127`) → `3e29fcd628` (`#282`, `#15127`): rendering OOM regression test and `dirty rows` failure retry
  - `321a32a423` (`#291`, `#15141`): `terminal: fix scrollback not pulled down when growing rows and shrinking cols`
  - `8ad3f607fd` (`#351`, `#15199`): `terminal: prompt redraw on resize no longer leaves stale prompts`
  - `f7d91fa456` (`#354`, `#15200`): `terminal: search thread test no longer crashes on timeout`
  - `dcdb1674cf` (`#365`, `#15222`): `terminal: clear a clone's padding rows to their page's width`
  - `f4830b2f18` (`#390`, `#15237`): `terminal: don't check PageList integrity mid-way through growing rows`
- **Kitty Graphics Protocol Stability (4, Low Risk)**:
  - `383a6f6ae3` (`#199`, `#15094`) → `4441aabcaf` (`#228`, `#15103`): look up the latest numbered image by transmission order and evict the oldest image
  - `44385f07c3` (`#201`, `#15086`): `terminal/kitty: only target virtual placements from placeholders`
  - `c4b91fe4c7` (`#337`, `#15184`): `terminal/kitty: keep a replaced image until its transmission ends`

### D. Config / CLI / SSH / SIMD UTF-8 / Font / Darwin Build (`Low`–`Medium` Risk — 20)

- **Config / Split Tree / CLI (9, Low Risk)**:
  - `241a7bca3b` (`#2`, `#14876`): `cli: fix Unicode escape validation`
  - `5c1d15f9b5` (`#6`, `#14879`): `config: prevent panic on truncated UTF-8`
  - `0cb81fe084` (`#17`, `#14904`): `datastruct/split_tree: assert goto() is given a valid handle`
  - `4c8ad9817e` (`#19`, `#14908`) → `9ee1031ba7` (`#20`, `#14908`): long environment variable formatting and tests
  - `8c04d7c2e8` (`#50`, `#14921`) → `90ed851dea` (`#54`, `#14950`): direct commands empty command and extra whitespace validation
  - `def58d386b` (`#168`, `#15073`): `cli: flush plain color list output`
- **SSH Terminfo Installation Chain (4, in order, Low Risk)**:
  - `4d7de0a483` (`#63`, `#14916`) → `9b4a0076d2` (`#225`, `#15061`) → `6283611ddf` (`#226`, `#15061`) → `3c3f33121a` (`#272`, `#15112`)
- **SIMD UTF-8 Decoding (2, in order, Low Risk)**:
  - `0f10e6698e` (`#302`, `#15156`) → `c1f4409661` (`#312`, `#15162`)
- **Font Discovery / Fallback (3, Low Risk)**:
  - `ba283a6f90` (`#378`, `#15216`)
  - `efd4a82bda` (`#379`, `#15216`) → `ef21f065f8` (`#380`, `#15216`)
- **Darwin Build Fixes (2, Medium Risk)**:
  - `9899c07077` (`#339`, `#15189`) → `a5eeb89790` (`#340`, `#15189`): `9899c07077` also modified upstream `.github/workflows/test.yml`; when porting, keep only the `build.zig` and `libsystem_override.sh` fixes to avoid introducing unrelated conflicts that disable workflows.

---

## 5. Key `DEFER` High-Risk Dependency Chains and Reasons for Deferral

1. **Zig `0.17.1` toolchain upgrade (`High Risk` — `#15230` / `1d84459682`)**:
   - Ghostty raised `.minimum_zig_version` to `0.17.1` on 2026-11-16. Railty `build.zig.zon`, `ci-railty.yml`, and `release-railty.yml` pin `0.17.0`; the decision to upgrade the CI/Release toolchain and cache keys must be made before following suit uniformly.
2. **`libghostty-vt 1.0` C ABI and dependency refactor wave (`High Risk` — `#15068`..`#15196`, 76 `DEFER` items)**:
   - Involves `deps/` directory migration, ABI exported symbols, Doxygen, and callback struct revisions; provides no direct benefit to the Railty desktop app and has a wide merge-conflict surface, so wait for Sidegeist's next major version to inherit it uniformly.
3. **`PageList` / `Style` / `RowBuilder` performance and `RefCountedSet` refactor chain (`High Risk` — 35 `DEFER` items)**:
   - `#14985`..`#15163` and `#15121` have dense forward/backward dependencies and regression fixes (e.g. `#15030`, `#15032`, `#15034`, `#15111` fixed boundary errors introduced by the earlier fast paths); never pick them piecemeal.
4. **PRs that conflict with Sidegeist-specific code (`High Risk`)**:
   - `#15039` (`0e067ded70`) modifies `TerminalWindow.swift`, and `#14208` (`6ba2c2b270`/`dce5a9464a`) modifies `Config.zig` and the multi-platform window theme interface; both overlap with Sidegeist vertical tab bar/Sidebar changes and need dedicated adaptation or should follow Sidegeist.

---

## 6. Next Worker's Starting Point (Incremental Review Mechanism Ready)

> **Outdated**: This section was written before the porting work. All 45 `INCLUDE` items have been merged into `main`; follow the "Next Steps" of the [Integration Complete Report](2026-11-17-integration-complete.md) directly, and do not re-port the commits listed in Section 4 of this report.

- Baseline audit and ledger persistence for all 395 commits in `v1.4.0..5ebe501a63` are complete; subsequent workers **do not need to re-review these 395 commits**.
- Next time, simply run `./tools/upstream/check.sh`, which automatically lists the incremental commits added after `5ebe501a63425b13d9952e8c54682c046386e5af`.
- If actual porting is started, work on a separate branch `sync/ghostty-fixes-2026-11`, beginning with the **Low Risk Security/Core** group in Section 4, cherry-pick in batches, and run full build and runtime validation.

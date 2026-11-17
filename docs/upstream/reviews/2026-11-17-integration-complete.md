# Railty Upstream Integration Complete (2026-11-17)

This report is the **follow-up integration report** to [2026-11-17-initial-audit.md](2026-11-17-initial-audit.md). It records the final state of the 45 `INCLUDE` upstream fixes across porting, validation, merge into `main`, and release as `v0.1.3` / `v0.1.4`.

> **Conclusion for the next worker**:
> - All 45 `INCLUDE` items have **fully** merged into `main`; `pending = 0` in `ledger.jsonl`.
> - **Do not** re-cherry-pick any commit from Section 4 of the initial audit report, otherwise duplicate patches and conflicts will result.
> - The next upstream sync only needs to start incremental review after `ghostty/main = 5ebe501a63425b13d9952e8c54682c046386e5af`, and should first run `./tools/upstream/check.sh`.

---

## 1. Integration Results Overview

| Metric | Value |
|---|---:|
| Upstream commits reviewed (Ghostty `v1.4.0..5ebe501a63`) | 395 |
| `INCLUDE` decisions | 45 |
| Integrated (`integrated`) | 44 |
| Integrated after adaptation (`adapted`) | 1 |
| Still pending porting (`pending`) | **0** |
| `DEFER` | 149 |
| `SKIP` | 201 |
| `NEEDS_REVIEW` / `ALREADY_INCLUDED` | 0 / 0 |

### Categories and Risks of Integrated Commits

| Category | Count | Risk |
|---|---:|---|
| `Critical Bug` | 30 | `low` 40 / `medium` 5 (combined) |
| `macOS Bug` | 6 | Same as above |
| `Security` | 3 | Same as above |
| `Tests` | 3 | Same as above |
| `Build / Toolchain` | 2 | Same as above |
| `Performance` | 1 | Same as above |

All 45 entries have `integration` of `integrated`/`adapted`, `validation` of `macos-build-passed`, and every `railty_commit` can be found in the `main` history (`tools/upstream/check.sh` validates this automatically).

### 3 Adaptation Points That Must Be Recorded

1. **`9899c0707767d93ad26e587c896a9a2761273b26` (Darwin memset quirk)**: Upstream also modified `.github/workflows/test.yml`; that file belongs to a disabled upstream workflow, so it was stripped during porting, keeping only the `build.zig` and `src/build/libsystem_override.sh` fixes, and the ledger records it as `adapted`.
2. **`f4830b2f18785aba11af9d92239f35c6e211abca` (PageList integrity check during growth)**: The end of `src/terminal/Terminal.zig` conflicts with the test context of the already `DEFER`red `ce920296c`; only the two resize regression tests belonging to this commit itself were kept, and the `eraseDisplay` test that does not belong to this commit was removed.
3. **`fd29936f09` (Surface `@MainActor` isolation)**: Sidegeist, App Intents, AppleScript, IPC, and `SidebarTabManager` callers were all checked and are all in `@MainActor` context, so no extra `MainActor.assumeIsolated` is needed.

---

## 2. Git History and Merge Method

- All sync work was completed on `sync/ghostty-fixes-2026-11`, using `git cherry-pick -x` to retain source tracking.
- Merging into `main` used a **linear rebase** (no merge commit), keeping the history single-line.
- The sync branch was deleted after merging and pushing (both local and remote).

Key commits on `main`:

| Commit | Content |
|---|---|
| `a4bacdff5` | Ledger update: 45 `INCLUDE` entries marked `macos-build-passed`; `state.json` records the validation results |
| `21ceebc39` | Renamed macOS app menu and quit confirmation (`Ghostty` → `Railty`) |
| `be61dbaeb` | User-visible copy branding cleanup (window titles, dialogs, Shortcuts/AppleScript/IPC, Dock Tile plugin) |

## 3. Release Results

| Version | Tag points to | Release workflow | Result |
|---|---|---|---|
| `v0.1.3` | `a4bacdff5` | [run 44050630021](https://github.com/vendettar/railty/actions/runs/44050630021) | Success: Release published, Homebrew Cask updated to `0.1.3` (sha256 `102d95ab…`) |
| `v0.1.4` | `be61dbaeb` | [run 44053591222](https://github.com/vendettar/railty/actions/runs/44053591222) | Success: Release published, Homebrew Cask updated to `0.1.4` (sha256 `8a8fcfe9…`) |

- `v0.1.3` contains all 45 upstream fixes.
- `v0.1.4` contains only branding copy cleanup and does not change terminal core behavior.
- Both official releases completed `GhosttyKit.xcframework` + `Railty.app` compilation, packaging, and optional signing/notarization via `release-railty.yml` on the `xcode-27` self-hosted Runner, and automatically updated `vendettar/homebrew-railty`.

## 4. Validation Matrix

| Validation Item | Scope | Result |
|---|---|---|
| `zig build test-lib-vt` | Full libghostty-vt test suite | Passed |
| `zig test src/os/path.zig` | Path null terminator fix | 4/4 passed |
| `zig fmt --check build.zig src/` | Formatting | Passed |
| `swiftc -parse` | All modified `.swift` | Passed |
| `xmllint --noout` | All modified `.xib` | Passed |
| `git diff --check` | Whitespace errors | Passed |
| macOS Release build | `xcode-27`, run 44042567498 | Success (full sync branch code) |
| Release build | `v0.1.3` / `v0.1.4` tag pushes | Both successful (run 44050630021 / 44053591222) |

Not performed: GUI runtime manual testing (tab dragging, Sidebar, Git Panel, etc.). A successful release build does not equal runtime behavior validation; if subsequent changes involve UI/Window/Input, they still need to be supplemented per Section 9 of [README.md](../README.md).

## 5. Consistency of the Ledger and State Files

- [state.json](../state.json) now records: `railty.head_sha = be61dbaeb…`, `latest_release_tag = v0.1.4`, `last_validated_commit = be61dbaeb…`, `active_task.status = completed`, `sync_branch = null`.
- [tools/upstream/check.sh](../../../tools/upstream/check.sh) adds a **State Consistency** check, which warns directly at runtime about the following drift:
  1. `railty.head_sha` is behind the real `HEAD` and there are code changes in between (protocol/documentation drift limited to `docs/`, `tools/upstream/`, and `AGENTS.md` is output only as a notice, not a warning);
  2. `latest_release_tag` is behind the newest `vX.Y.Z` tag on `origin`;
  3. the latest Release tag is not an ancestor of `HEAD`;
  4. the `railty_commit` of an `integrated`/`adapted` record in the ledger is missing or not in the `HEAD` history.
- Note: `railty.head_sha` cannot point to "the commit that contains itself", so after committing this report there will be one docs-only drift notice; this is expected behavior.

## 6. Sampling Re-Review of Templated `DEFER` Records (2026-11-17)

75 `DEFER` entries in the initial audit shared the same `libghostty-vt 1.0 / ABI / dependency` reason. The method and results of this re-review:

1. Read the real changed paths of all 75 commits using `git show --name-only`;
2. Classify by path: `include/`, `src/terminal/c/`, `src/lib*`, `example/`, `dist/`, `pkg/`, `nix/`, `build.zig*`, `test/abi/`, `PACKAGING*`;
3. For the 35 entries touching shared core such as `src/terminal/PageList.zig`, `src/terminal/snapshot/*`, `src/terminal/lib.zig`, the diffs were checked in detail.

Conclusions:

- **73/75** confirmed to be libghostty-vt 1.0 C ABI, Doxygen, examples, CMake/pkg-config, dependency manifests, or ABI test infrastructure, with no direct runtime benefit to the macOS app; `DEFER` stands.
- **2/75** had a reason template that did not match the actual diff and were corrected in the ledger (decision remains `DEFER`):
  - `9b848b0f5c` — `libghostty: restored snapshot keeps final page capacity max size` (#15192): this is actually a snapshot restore page capacity allocation optimization in the shared terminal core, changing `PageList.fillPooled` and `snapshot/{page,screen,snapshot}.zig`, unrelated to the C ABI. Its category has been changed to `Performance`, `risk: medium`, and it is listed as a **next-batch candidate**.
  - `ef1649c853` — `ci: shard the unit tests, run one test shard per core` (#15169): this belongs to the test sharding runner and `build.zig`/CI changes; the `PageList` `pauseIntegrityChecks` only takes effect under `slow_runtime_safety` (debug/test). The reason has been changed to an accurate description of the test build.
- The remaining `DEFER` groups (PageList fast path 28 entries, `terminal-misc-refactor` 12 entries, tmux 8 entries, etc.) are outside this templated scope and retain the original audit conclusions.

## 7. Next Steps

1. Use `./tools/upstream/check.sh` to review incrementally after `5ebe501a63`; when `Security` / `Critical Bug` is found, evaluate it first per protocol.
2. Evaluate whether to include `9b848b0f5c` (snapshot restore page capacity) in the next batch; the session restore path needs extra validation.
3. The Zig `0.17.1` upgrade (`1d84459682`) remains `DEFER`; do not introduce 0.17.1-only syntax before upgrading the CI/CD toolchain.
4. If continuing with the `libghostty-vt-and-deps` wave, it is recommended to wait for a Sidegeist major version integration to avoid repeated conflicts with the C ABI refactor.

# Railty Deferred Review & High-Value Candidate Analysis (2026-11-17)

> **Historical record (before rewrite)**: The baseline `ab61a1099` of this report and the branch SHA at that time are no longer in the current `main` history, and the DEFER count has also dropped from 149 to 148. Do not treat this report as the current starting point for operations; for the current SHA and queue status, see [2026-11-17-v1.2-lite.md](2026-11-17-v1.2-lite.md#current-sha-after-force-push) and `state.json`.

This report is the review and experiment record for **Upstream Sync v1.1**, with a baseline of `main = ab61a1099` and release `v0.1.4`. It does not overturn the existing 395-entry ledger; instead, it establishes an actionable re-review queue for the 149 `DEFER` entries and evaluates the applicability of high-value candidates.

---

## 1. Prerequisite Verification (real command results, not historical assumptions)

| Check Item | Measured Result |
|---|---|
| Railty `HEAD` | `ab61a1099f96668492a4341570e43e8a4e2e7279` |
| Ghostty `main` | `5ebe501a63425b13d9952e8c54682c046386e5af` (same as the previous review, 0 new) |
| Sidegeist `main` | `5904a523477542b114939d93594f82348f27b3b5` (0 new) |
| Unreviewed Ghostty commits | 0 |
| Unreviewed Sidegeist commits | 0 |
| `INCLUDE` pending integration | 0 (all 45 integrated/adapted) |
| Ancestor validation for the 45 `railty_commit` entries | All passed |
| Latest Release | `v0.1.4` (`be61dbaeb`, Homebrew Cask updated) |
| CI/CD Zig | `0.17.0` (local machine has `zig 0.17.1`, used only for local testing) |
| Local Xcode | Command Line Tools only, no `metal` / `xcodebuild` |
| New security/critical fixes | None new (Ghostty `main` has not advanced) |

`./tools/upstream/check.sh` outputs `All state consistency checks passed`, `DEFER Re-assessment Gates: 0 satisfied`.

---

## 2. DEFER Re-Review Queue (new mechanism)

Added [defer-queue.json](../defer-queue.json), which retains an independent SHA for each of the 149 `DEFER` entries and adds:

| Field | Description |
|---|---|
| `group` | Feature group (e.g. `terminal-refcounted-set`) |
| `priority` | `P1` / `P2` / `P3` |
| `revisit_trigger` | Trigger condition for re-evaluation (enum) |
| `validation_plan` | Validation steps required for the group |
| `review_status` | `awaiting_validation` / `awaiting_dependencies` / `awaiting_toolchain` / `awaiting_upstream` / `no_runtime_path` / `candidate_next_batch` |
| `last_reassessed_at` | Most recent re-review date |
| `notes` | Conclusions and cautions |

Current distribution:

| Dimension | Distribution |
|---|---|
| Priority | `P1: 14`, `P2: 32`, `P3: 103` |
| Status | `awaiting_upstream 75`, `awaiting_dependencies 45`, `awaiting_validation 23`, `awaiting_toolchain 4`, `no_runtime_path 1`, `candidate_next_batch 1` |
| Largest feature groups | `libghostty-vt-1.0-abi 75`, `terminal-misc-refactor 12`, `tmux-control-mode 8`, `terminal-refcounted-set 7`, `terminal-print-fastpath 5`, `terminal-style-packing 6`, `terminal-blank-row 5`, `terminal-pagelist-capacity 5`, `terminal-rowbuilder-render 5` |

Trigger condition semantics (implemented by [defer_queue.py](../../../tools/upstream/defer_queue.py) and invoked by `check.sh`):

- `on_toolchain_upgrade`: `state.railty.pinned_zig_version >= 0.17.1`
- `on_sidegeist_upgrade`: Sidegeist advances beyond `last_integrated_sha`
- `on_upstream_dependency_update`: Ghostty advances beyond `last_reviewed_sha`
- `on_macos_snapshot_consumer`: `ghostty_snapshot` calls appear in `macos/` or `src/apprt`
- `on_next_sync_review`: either upstream advances
- `manual_dedicated_port` / `on_user_request`: can only be triggered manually

`check.sh` now also outputs: the number of unreviewed upstream commits, the number of INCLUDE entries pending integration, the P1 count, a per-group summary, satisfied re-review triggers, and a "DEFER commit already present in sidegeist/main" detection. 27 unit tests were added, covering scenarios such as empty queues, duplicate SHAs, invalid states, trigger conditions, and history rewrites:

```bash
python3 -m unittest tools/upstream/test_defer_queue.py   # 27 tests OK
```

---

## 3. PageList / Terminal Performance Group Dependency Analysis

Current state verification: the current `src/terminal/PageList.zig` does **not** have `carried_capacity`; `src/terminal/Style.zig` is still a plain `struct` (not packed into `u128`); `Terminal.zig` already has `printSliceFast`/`printSliceStoreRun`, which shows the baseline already contains an earlier fast path, but not this series.

| Group | Commits (short SHA) | Dependencies / Follow-up fixes | Main Value | Risk | Conclusion |
|---|---|---|---|---|---|
| A. PageList capacity | `a3b5946a59` (base, +555/−48), `0d4418ac20` (+321/−22), `9113da0298`, `f0d8cb7762`, `d20d208c51` | Must be taken as a whole chain: edge-case fixes immediately follow the base; `d20d` adjusts hyperlink map capacity | Reduces page reallocation in output-heavy scenarios | High (major PageList/page changes) | Keep `DEFER`; needs a dedicated branch + benchmarks |
| B. Print Fast Path | `68750a1be2` (+768), `faa346b068`, `4c92f80954`, `22b8451441`, `c12d42eaf8` | `faa3`/`22b8`/`4c92` are follow-up correctness fixes for the same fast path | ASCII/wide-character mixed output throughput | High (must be taken together with the fixes) | Keep `DEFER` |
| C. Style packing | `41557e2ccf` (u128), `73a2a1d06e`, `72bc97a9ed`, `de16f08dcf`, `fad1133619`, `54d162da5b` | Requires changing the Screen/Terminal/C style API together | SGR-heavy output and memory | High (affects the C API) | Keep `DEFER` |
| D. Blank Row | `881fc68902`, `2178e635df`, `8484146c74`, `25de649dde`, `a227276b77` | `a227` is a snapshot test correction and must be included | Clear screen/blank rows/scrolling | Medium-high | Keep `DEFER` |
| E. RowBuilder / Render | `020a0a0998`, `d1ce0c4657`, `96d379822f`, `15a4432340` | `d1ce` fixes a regression introduced by `020a` | Style run lookup and endUpdate | Medium | Keep `DEFER`; `96d3` can be tested independently |
| F. OSC 133 Prompt | `ce920296c8` | Includes the synthetic Erase corpus and snapshot test updates; previously deferred only due to test conflicts | `ED2` clear-screen scan | Medium | Keep `DEFER`; can be experimented with independently |
| G. Carriage Return Pin | `8434d0900e` | Standalone 2 lines | Scrolling stream (upstream 1.02–1.06x) | Low | The only experiment item this round |
| H. PageList Prune memory | `d0addb9cdf` | Standalone Critical Bug fix | grow-prune discarding page memory | Medium | **P1**, recommend experimenting first |

Common conclusion: A–F are all "dependency chains of follow-up upstream fixes"; taking only the first performance commit is prohibited. This machine has no `ghostty-bench` (blocked by Metal), so credible throughput data cannot be produced; therefore no performance patch is merged this round.

---

## 4. RefCountedSet Whole-Chain Evaluation

7 commits: `d03983f02c` (add reuses dead IDs, replacing NeedsRehash), `636c1d7805` (reclaim only displaceable dead items), `738d8f7f5b` (membership check replacing sentinel), `38f4a710e3` (releaseMultiple assertion), `31a52992f1` (reclaim dead IDs skipped on insert), `aef8b7b38d` (tighten tests), `5d3f653329` (docs).

Current state verification: `src/terminal/ref_counted_set.zig` (890 lines) is exactly identical to the Ghostty `v1.4.0` baseline; `add` still returns `NeedsRehash` when there are no free slots, and callers compact IDs by cloning the whole page. This series introduces dead-ID reuse into `add`.

Upstream data (from commit messages, not measured locally): 1.35x for `links.vt` without scrollback, 1.17x for `styled-heavy`; real workloads such as `rg --hyperlink-format`, `chafa`, and `eza --hyperlink` reduce instruction counts by 3.6%–14.2%. The potential value for Railty is mainly in hyperlink/style-heavy output; plain ASCII is basically unchanged.

Conclusion: keep `DEFER` (`P2 / awaiting_dependencies`); it must be ported as a whole in topological order, since taking `d039` alone would break the assumptions of `add`/`insert`/`deleteItem`. Recommended as the first experiment group in the next batch.

---

## 5. New Features and High-Conflict Candidates

| Candidate | Scale | Judgment |
|---|---|---|
| Window theme `6ba2c2b270` + `dce5a9464a` | `include/ghostty.h`, `AppDelegate.swift`, `TerminalWindow.swift`, Config | Highly overlaps with Sidegeist window/config and depends on the preceding action mechanism; keep `P3 / awaiting_validation` and only adapt specifically when there is an explicit need |
| tmux control mode (8 entries) | Terminal/Termio protocol chain | Feature chain incomplete and overlaps with Sidegeist session/tab behavior; keep `P3` |
| DECIC/DECDC/DECBI/DECFI `44a4911e91` | Terminal +297, stream +138 | New VT420 protocol, no user demand; keep `P3 / on_user_request` |
| iTerm2 color schemes (3 entries) | Only `build.zig.zon` / `deps/packages.*` data updates | No code behavior change; can be evaluated separately in the next sync window, not touched this round |

---

## 6. Experiment: carriage-return pin fast path

- Branch: `sync/ghostty-pagelist-cr-pin`
- Commit: `f6cd5e4fd` (`git cherry-pick -x 8434d0900e`, 2-line change)
- Change: `Screen.cursorHorizontalAbsolute` moves the cached cell pointer by column difference, avoiding the pin lookup in `rowAndCell()`.
- Local tests: `zig fmt --check src/terminal/Screen.zig` passed; `zig build test-lib-vt -Dtest-filter=Screen` passed; full `zig build test-lib-vt` passed (exit 0).
- macOS build: `xcode-27` `release-railty.yml` run `44062908329` (workflow_dispatch, `create_draft_release=false`, produces no Release / Cask changes).
- Performance: `NOT_TESTED` (this machine cannot build `ghostty-bench`, Metal is missing); the upstream-reported 1.02–1.06x cannot be treated as a local conclusion.
- Conclusion: keep the branch, **do not merge into main**; decide later once an environment with Xcode can supplement the benchmark.

Full lib-vt result: **Passed** (`FULL_TEST_EXIT=0`)
CI result: **Success** (run `44062908329`, `Build Railty.app (Apple Silicon)` completed; a manual build produces no Release/Cask changes)

---

## 7. Final Questions Answered

1. **Of the 149 DEFERs, how many remain deferred?** All 149 remain deferred this round; 14 of them are `P1` and require dedicated scheduling (12 Critical Bug, nullability, snapshot/prune related).
2. **How many can be safely included?** 0 this round. No candidate simultaneously satisfies "reachable path + correctness test + local performance data".
3. **How many are actually no longer needed?** 0 can be directly changed to `SKIP`; the 75 libghostty-vt ABI entries merely have no benefit for the current macOS app and still need to be retained for Sidegeist/embedding scenarios.
4. **Which ones need to wait for the Zig upgrade?** 4 `toolchain-zig-upgrade` entries; the PageList/RefCountedSet chains themselves do not depend on 0.17.1.
5. **Which ones need to wait for Sidegeist?** The 75 `libghostty-vt-1.0-abi` entries, plus high-conflict feature groups such as window theme and tmux.
6. **Which performance optimizations can be introduced independently?** Only `8434d0900e` has been verified to compile independently (this round's experiment); `96d379822f` and `ce920296c8` are also relatively independent but were not experimented with.
7. **Which features have Sidegeist conflicts?** Window theme (2), tmux (8), the `TerminalWindow.swift` part of nullability, and shared files in `terminal-misc-refactor`.
8. **Which candidates have passed a macOS ARM64 build?** This round's experiment branch `f6cd5e4fd` passed run `44062908329`; all `v0.1.4` official release builds passed.
9. **Which ones have completed runtime validation?** 0; this machine has no GUI/Xcode, so all are marked `NOT_TESTED`.
10. **Which ones achieved measured performance gains?** 0 locally; benchmark data in upstream commit messages is for reference only and was not reproduced.
11. **What should the next worker continue with?** First the `terminal-refcounted-set` whole chain and `terminal-pagelist-prune-memory` (P1), then evaluate the PageList capacity chain; each step should collect data according to the benchmark protocol in [benchmarks/2026-11-17-baseline.md](../benchmarks/2026-11-17-baseline.md).

## 8. Related Reports

- [Snapshot applicability assessment](2026-11-17-snapshot-assessment.md)
- [macOS C API nullability assessment](2026-11-17-macos-nullability-assessment.md)
- [Performance baseline (NOT_TESTED records)](../benchmarks/2026-11-17-baseline.md)
- [Integration complete report](2026-11-17-integration-complete.md)

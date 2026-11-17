# PageList Prune Memory Fix — Applicability & Experiment

**Upstream commit:** `d0addb9cdf9a30901bd953421dccada3bf610d7c`
**Subject:** `terminal: keep the pruned page's memory when grow prunes by lines`
**Upstream issue / PR:** #15157 / #15173
**Assessed:** 2026-11-17 against Railty `0d80ab1bd`

## 1. Problem and upstream fix

With a line-based scrollback limit (`scrollback-limit` set in lines), the limit is enforced in the middle of `PageList.grow()`. Each pruned page was fully decommitted and then faulted back in on the next page allocation, causing decommit/fault churn. Upstream measured (166 MB ASCII, 200×50):

| Scrollback limit | Linux before | Linux after | macOS before | macOS after |
|---|---:|---:|---:|---:|
| default 10 MB | 2,003 MB/s | 2,041 MB/s | 4,242 MB/s | 4,326 MB/s |
| max lines 1,000 | 298 MB/s | 1,983 MB/s | 2,214 MB/s | 4,093 MB/s |
| max lines 10,000 | 293 MB/s | 1,861 MB/s | 2,157 MB/s | 4,010 MB/s |

The fix adds a `DestroyMode` (`reclaim` vs `retain`): line-limit pruning in `grow` uses `retain`, so the pooled page keeps its zeroed memory for immediate reuse. Trade-off: one extra pooled page (~300 KB) for an idle terminal at its line limit.

## 2. Is the problem present in Railty?

**Yes.** Current `src/terminal/PageList.zig` matches the pre-fix shape:

- `destroyNodeExt(pool, node, total_size)` has no destroy mode and always calls `terminal_mem.decommit`.
- `erasePage(node)` has no mode.
- `Limits.enforce(pagelist, key)` always decommits.
- `grow()`'s line-limit paths call `enforce(..., .lines)` with no retain option.

The ledger's original `DEFER` reason claimed a dependency on the unmerged carried-capacity chain. A full diff review shows that is **not** true: the commit only threads a destroy mode through existing functions.

## 3. Adaptation

Branch: `sync/ghostty-pagelist-prune-memory`
Commit: `04c6deea1`

- Added the `DestroyMode` enum and threaded it through `destroyNode`, `destroyNodeExt`, `erasePage`, `Limits.enforce`, `PageAllocation.deinit`, and `Builder.deinit`.
- Line-limit pruning in `grow()` uses `.retain`; shrink/byte-limit/teardown paths use `.reclaim`.
- Omitted two upstream hunks that do not exist in Railty's baseline and are unrelated to this fix: the `.bytes` enforce calls in the recycle path and the `page_preheat` free-list logic. Adding them would have pulled in additional unported behavior.

Diff: only `src/terminal/PageList.zig`, 43 insertions / 17 deletions.

## 4. Validation

| Check | Result |
|---|---|
| `zig fmt --check src/terminal/PageList.zig` | passed |
| `zig build test-lib-vt -Dtest-filter=PageList` | passed |
| Full `zig build test-lib-vt` | not completed in this session (debug suite ran >25 min; stopped). Targeted PageList tests used instead |
| `xcode-27` macOS arm64 build, run `44075475339` | success (workflow_dispatch, no Release/Cask changes) |
| Runtime / performance | `NOT_TESTED` (no Xcode/GUI; `ghostty-bench` blocked by missing Metal) |

Regression coverage reuses existing tests: `PageList set max lines prunes immediately and can be raised`, `PageList max lines uses one-page minimum`, `PageList max lines does not round larger limits`, `PageList grow prune required with a single page`, plus the full PageList suite. Upstream added no new test because the decommit behavior is not observable through the public API.

## 5. Recommendation

- The fix is small, self-contained, and addresses a real 2x throughput cliff for line-limited scrollback users.
- Recommend merging `04c6deea1` into `main` after review; it does not touch Sidegeist, branding, CI/CD, or the build system.
- Performance remains `NOT_TESTED` on Railty hardware; do not claim the upstream numbers as measured here.

# Snapshot Page Capacity Optimization — Applicability Assessment

> **Historical record (before the rewrite)**: The assessment baseline `ab61a1099` is no longer in the current `main` history. See [2026-11-17-v1.2-lite.md](2026-11-17-v1.2-lite.md#current-sha-after-force-push) for the current SHA.

**Upstream commit:** `9b848b0f5c1f5e18611d89a570540df9ad2333d1`
**Subject:** `libghostty: restored snapshot keeps final page capacity max size`
**Upstream issue:** #15192
**Assessed:** 2026-11-17 against Railty `ab61a1099`

## 1. What the commit changes

| File | Change |
|---|---|
| `src/terminal/PageList.zig` | Adds `fillPooled`, which grows a page's row capacity to fill the pooled allocation without extra memory. |
| `src/terminal/snapshot/page.zig` | The page decoder accepts a destination with more rows than the snapshot advertises. |
| `src/terminal/snapshot/screen.zig` | The screen decoder sizes the final active page with `fillPooled`. |
| `src/terminal/snapshot/snapshot.zig` | Test helper support for the larger final page. |

Total: 4 files, +108/−10. The snapshot wire format is unchanged; only the in-memory destination page is pre-sized so the next write does not immediately force a new page allocation.

## 2. Is the path reachable from the Railty macOS app?

**No.** Evidence:

1. `grep -rn "ghostty_snapshot|snapshot_decoder|snapshot_encode" macos src/apprt` returns no matches. The app runtime never calls the snapshot C API.
2. macOS window restoration uses `TerminalRestorableState` (`macos/Sources/Features/Terminal/TerminalRestorable.swift`), which encodes the surface tree with `Codable` and recreates surfaces from configuration; it restores tab/window metadata, not terminal contents.
3. The snapshot codec is exported for embedders via `src/lib_vt.zig` (`ghostty_snapshot_encode`, `ghostty_snapshot_decoder_*`), plus internal tests/benchmarks. Railty ships the macOS app, not an embedding SDK use case.

## 3. Dependency and conflict check

- No dependency on the deferred PageList capacity chain (`carried_capacity` does not exist in Railty).
- No Zig 0.17.1 requirement; the commit predates the toolchain bump.
- Low Sidegeist conflict risk (shared Zig core only), but the change is unreachable in the product.
- If Railty later adopts snapshot-based session persistence or a C-API embedding, this commit becomes relevant immediately.

## 4. Decision

| Field | Value |
|---|---|
| Integration | **Not integrated** |
| Ledger decision | `DEFER` (unchanged) |
| Queue group | `snapshot-page-capacity` |
| Priority | `P1` (tracked, but not actionable yet) |
| Review status | `no_runtime_path` |
| Revisit trigger | `on_macos_snapshot_consumer` — reactivate when the macOS app (or `src/apprt`) starts calling `ghostty_snapshot_*` |

**No experiment branch was created**: cherry-picking an unreachable optimization would add maintenance surface without a measurable product benefit. The commit remains recorded in `ledger.jsonl` and `defer-queue.json`.

## 5. Validation plan when the trigger fires

1. Cherry-pick `9b848b0f5c` onto a dedicated `sync/ghostty-snapshot-*` branch.
2. Run `zig build test-lib-vt` (snapshot/PageList tests) plus `zig build test -Dtest-filter=snapshot` on an Xcode host.
3. Run `ghostty-bench +terminal-snapshot --mode=encode/decode` before and after; record allocation counts and decode latency with warmup and repeated runs.
4. Verify restore-then-write and repeated restore/resize flows.
5. macOS arm64 build through `release-railty.yml` `workflow_dispatch`.

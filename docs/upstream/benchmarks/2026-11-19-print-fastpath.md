# Print Fast Path Port Measurement (2026-11-19)

Purpose: measure the upstream print fast-path chain before merging it into
Railty. The chain is `68750a1be2` (mixed narrow/wide) plus its four follow-up
fixes, and it required three prerequisite groups (blank-row hint, OSC 133
prompt scan, SGR style packing).

## 1. Environment

| Item | Value |
|---|---|
| Hardware | Apple M4 Pro, 48 GiB |
| OS | macOS 26.7.2, arm64 |
| Local Zig | `0.17.1` (CI/CD pins `0.17.0`) |
| Xcode | 27.2 (27B52) |
| Build | `zig build -Demit-bench -Doptimize=ReleaseFast -Demit-macos-app=false` |
| Base binary | `main` at `66e46463d` (core identical to `c6fadc8da`) |
| Candidate | `sync/ghostty-print-fastpath` tip after the 12-commit port |

Both binaries were built with the same command on the same host.

## 2. Ported commits

Prerequisites (needed for the print chain to compile and keep the blank-row
invariant correct):

| Upstream | Subject |
|---|---|
| `881fc68902` | terminal: skip clearing rows that are already blank |
| `2178e635df` | terminal: mark reset rows blank and test the blank bit bookkeeping |
| `8484146c74` | terminal: skip erasing and scanning rows that are already blank |
| `25de649dde` | terminal: write the blank row once when scrolling a region up |
| `a227276b77` | terminal: clear the blank hint where a snapshot test writes cells |
| `ce920296c8` | terminal: skip the ED2 prompt scan when OSC 133 was never seen |
| `54d162da5b` | terminal: apply every attribute of an SGR sequence at once |

Print chain:

| Upstream | Subject |
|---|---|
| `68750a1be2` | terminal: support mixed narrow/wide in print fast path |
| `faa346b068` | terminal: print uses the right margin after wrapping |
| `22b8451441` | terminal: re-read the style per row in the mixed-width print fast path |
| `4c92f80954` | terminal: print fast stays active while a hyperlink is open |
| `c12d42eaf8` | terminal: print ASCII runs as u8 slices from input instead of u32 |

`c12d42eaf8` also pulls in the SGR style packing prerequisite: its stream test
records a `set_attributes` action tag that only exists after `54d162da5b`.

## 3. Corpora

All corpora are 1 GiB, deterministic, generated outside the repository and
reused for both binaries.

| Name | Content |
|---|---|
| ascii | `A` x119, no newlines; pure ASCII print stream |
| scroll | `A` x119 + `\n`; one row per line |
| wide | 35 CJK ideographs + 10 ASCII per line (80 cells) |
| mixed | `中a文b字c符d测e试f` repeated: width alternates every codepoint |
| mixed2027 | same as mixed with `ESC[?2027h` at the start (app default mode) |
| cjkprose | `ghostty-gen +utf8` with ASCII:CJK weight 0.3:1, width-2 ideographs |
| cjkspaces | `ghostty-gen +utf8` CJK-only with `--space-rate=0.3` |

Benchmark command (identical for both binaries):

```bash
ghostty-bench +terminal-stream \
  --terminal-rows=50 --terminal-cols=120 \
  --max-lines=10000 --max-bytes=10000000000 \
  --data=<corpus>
```

## 4. Results (interleaved A/B, medians)

Interleaving matters: host drift on this machine is 2-4%, larger than several
of the effects measured here.

| Corpus | Base | Candidate | Speedup |
|---|---:|---:|---:|
| ascii | 0.6871 s | 0.4414 s | **1.56x** |
| scroll | 0.8981 s | 0.6196 s | **1.45x** |
| mixed | 4.7049 s | 1.7824 s | **2.64x** |
| mixed2027 | 4.8393 s | 1.8801 s | **2.57x** |
| cjkprose | 3.0766 s | 1.4569 s | **2.11x** |
| cjkspaces | 3.8074 s | 1.5218 s | **2.50x** |
| wide (11 rounds) | 1.1458 s | 1.1725 s | 0.98x |

Peak RSS is unchanged: 18.8 MB for both binaries on mixed and wide.

## 5. Interpretation

- ASCII-heavy output gains from the u8-slice fast path (`c12d42eaf8`), while
  CJK/ASCII alternation gains from the mixed-width path (`68750a1be2`).
- The `wide` corpus (a long CJK run followed by a short ASCII run, repeated per
  line) is about 2% slower. The vectorized run fill was already optimal there
  and the transition now costs a small amount per line. No other corpus shows
  a regression, and common CJK shapes (`cjkprose`, `cjkspaces`, alternating
  text) improve 2.1x-2.5x.
- Upstream's own numbers are 2.05x for cjk-prose and 1.65x for cjk-spaces; the
  direction and magnitude reproduce here.

## 6. Validation

- `zig build test -Dtest-filter=printSlice|Screen|Page|Cursor|Terminal` passed
  at the branch tip, including the printSlice differential fuzz test.
- `zig build test-lib-vt` passed.
- `zig build -Demit-macos-app=false -Dxcframework-target=native` (GhosttyKit)
  passed.
- `zig fmt --check` on every changed Zig file passed.

## 7. Not tested

GUI runtime validation (no UI surface is changed; the app core is exercised
through the benchmark and unit tests), and `0ae4cb559f` (halving the op counts
of the differential tests) remains deferred because it only affects test
runtime.

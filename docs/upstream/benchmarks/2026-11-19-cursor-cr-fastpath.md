# Cursor CR Fast Path Measurement (2026-11-19)

Purpose: measure upstream `8434d0900e` ("terminal: avoid the pin lookup on a
carriage return") on arm64 macOS before merging it into Railty. Upstream
reported 1.02x-1.06x on Windows x86-64 scrolling corpora; this run checks
whether the win reproduces on Apple Silicon.

## 1. Environment

| Item | Value |
|---|---|
| Hardware | Apple M4 Pro, 48 GiB |
| OS | macOS 26.7.2, arm64 |
| Local Zig | `0.17.1` (CI/CD pins `0.17.0`) |
| Xcode | 27.2 (27B52) at `/Applications/Xcode.app` |
| Build | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer zig build -Demit-bench -Doptimize=ReleaseFast -Demit-macos-app=false` |
| Base binary | `main` at `66e46463d` |
| Fast-path binary | `sync/ghostty-cursor-cr-fastpath` at `9a0705bf4` (2-line change in `Screen.cursorHorizontalAbsolute`) |

Both binaries were built from the same machine, in `ReleaseFast`, and kept in
`/tmp` so that only the benchmarked code differs.

## 2. Corpora

All corpora are deterministic files generated outside the repository and
reused for both binaries.

| Name | Size | Content |
|---|---|---|
| ascii | 1 GiB | `A` repeated, no newlines; pure print path |
| cr | 1 GiB | `progress ` + 30x"# " + `\r`, repeated 200x, then `\n`; one CR per ~70 bytes |
| scroll | 1 GiB | 119x`A` + `\n`; one full row per line |
| wide | 1 GiB | CJK + ASCII line (`中文宽字符测试` x5 + 10 ASCII); mixed-width print |
| cronly | 256 MiB | `\r` only; isolates `Screen.carriageReturn` |

Benchmark command (identical for both binaries):

```bash
ghostty-bench +terminal-stream \
  --terminal-rows=50 --terminal-cols=120 \
  --max-lines=10000 --max-bytes=10000000000 \
  --data=<corpus>
```

Each run starts a fresh process; the file is warm in the page cache after a
single untimed warm-up.

## 3. Sequential runs (7 each)

The machine drifted between measurement blocks, so these numbers are only
indicative; the interleaved A/B below is authoritative.

| Corpus | base (run 1) | fast path | base (run 2) |
|---|---:|---:|---:|
| ascii | 0.6961 s | 0.7068 s | 0.7102 s |
| cr | 0.6117 s | 0.6420 s | 0.6359 s |
| scroll | 0.9188 s | 0.9154 s | 0.9144 s |
| wide | 1.1687 s | 1.1726 s | 1.1889 s |

`base (run 2)` is 2-4% slower than `base (run 1)` on ascii/cr/wide, which is
larger than the expected effect. Sequential blocks cannot separate the change
from host drift.

## 4. Interleaved A/B (9 rounds, alternating base/fast path)

| Corpus | base median | fast path median | Speedup | Per-round ratio median (min-max) |
|---|---:|---:|---:|---|
| cr (1 GiB) | 0.6208 s | 0.6135 s | **1.012x** | 1.013 (0.899-1.110) |
| cronly (256 MiB) | 0.6676 s | 0.6442 s | **1.036x** | 1.041 (1.017-1.410) |

## 5. Conclusion

- The change is a real but small win on carriage-return-heavy input: +3.6% on
  a pure-CR stream (consistent across rounds, min ratio 1.017) and +1.2% on a
  progress-bar-style stream. This matches the upstream 1.02x-1.06x range
  rather than contradicting it.
- ASCII, scrolling, and mixed-width streams show no regression beyond host
  noise.
- Cost is two lines in `Screen.cursorHorizontalAbsolute`; `Screen`, `Page`,
  and `Cursor` test filters pass and the GhosttyKit/macOS build succeeds.
- Merged as `9a0705bf4`.

## 6. Not tested

GUI runtime behavior (no UI surface is touched by this change), and memory
RSS deltas (the change only moves a cached pointer; no allocation change was
expected or observed in the 18-19 MB range across both binaries).

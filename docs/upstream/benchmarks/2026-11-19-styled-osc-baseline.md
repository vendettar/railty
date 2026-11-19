# Styled / OSC Baseline and RSS (2026-11-19)

Purpose: measure the current cost of SGR-, hyperlink-, and OSC-heavy output
before deciding whether to port the upstream PageList capacity chain, and
record the current memory footprint.

## 1. Environment

| Item | Value |
|---|---|
| Hardware | Apple M4 Pro, 48 GiB |
| OS | macOS 26.7.2, arm64 |
| Zig | 0.17.1 local (CI pins 0.17.0) |
| Xcode | 27.2 (27B52) |
| Binary | `main` at `d5fba5406`, built with `zig build -Demit-bench -Doptimize=ReleaseFast -Demit-macos-app=false` |
| Comparison binary | `main` at `66e46463d` (before the print fast-path chain) |
| Terminal | `--terminal-rows=50 --terminal-cols=120 --max-lines=10000 --max-bytes=10000000000` |

## 2. Corpora (256 MiB each)

```bash
ghostty-gen +styled --seed=1
ghostty-gen +styled --seed=1 --style-rate=0.8 --sgr-attrs=3
ghostty-gen +styled --seed=1 --style-rate=0.3 --weight-two=0.5 \
  --weight-three=0.25 --weight-four=0.1 --grapheme-rate=0.05 --osc8-rate=0.1
ghostty-gen +styled --seed=1 --osc8-rate=1
ghostty-gen +osc
```

## 3. Throughput (5 interleaved rounds, medians)

| Corpus | Before print chain | Current main | Speedup | Current MB/s |
|---|---:|---:|---:|---:|
| styled-plain | 0.3029 s | 0.2186 s | 1.39x | 1228 |
| styled-heavy (SGR) | 1.6853 s | 1.1226 s | 1.50x | 239 |
| styled-mixed (SGR + Unicode + graphemes + links) | 19.8127 s | 17.5915 s | 1.13x | 15 |
| hyperlinks (OSC 8) | 9.0990 s | 8.6201 s | 1.06x | 31 |
| osc | 12.6335 s | 12.3360 s | 1.02x | 22 |

Plain ASCII (1 GiB corpus) for scale: 1471-1550 MB/s.

## 4. Memory

Core benchmark with the app's default scrollback (`--max-bytes=50000000`):

| Corpus | Peak RSS |
|---|---:|
| ascii (1 GiB) | 56.2 MB |
| styled-mixed | 57.9 MB |
| hyperlinks | 57.6 MB |
| osc | 62.9 MB |

Running `Railty.app` (Debug build from 2026-11-19 09:59, one window, idle):
**67.7 MB RSS** (69,296 KB), 0.1% CPU, plus a 7.6 MB login shell child.

## 5. Interpretation

- The print fast-path chain already helps styled text (1.39x plain styled,
  1.50x heavy SGR) but leaves the grapheme/hyperlink/OSC paths roughly where
  they were.
- Those paths are still 50-100x slower than plain text: 15-31 MB/s versus
  ~1.5 GB/s. This is the bottleneck the upstream PageList capacity chain
  targets (`styled-mixed` 3.74x, `hyperlinks` 3.83x, `osc` 2.23x upstream).
- Memory is dominated by the 50 MB scrollback limit, not page structure:
  core RSS stays at 56-63 MB across all shapes, and the running app is
  ~68 MB. The capacity chain's memory effect is density only (upstream:
  rows/MiB 624 -> 694 for OSC, 681 -> 775 for hyperlinks; no change for
  plain text).
- Caveat: these corpora are homogeneous and adversarial. Upstream reports no
  change on a 2.6 GB real-world asciinema dump, so these numbers are a
  worst-case bound, not an everyday average.

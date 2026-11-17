# Railty Upstream Sync Protocol & Worker Guide

This document is the authoritative operating protocol for **Railty**'s dual-upstream sync and commit-by-commit review mechanism. Any AI worker or maintainer taking over Railty maintenance, development, or upstream sync must strictly follow this guide.

---

## 1. Three-Repository Relationship and Maintenance Goals

| Repository | URL | Role and responsibility |
|---|---|---|
| **Railty** (`origin`) | `https://github.com/vendettar/railty` | A personally maintained native macOS terminal distribution. Owns its independent branding, `com.vendettar.railty`, the `Railty R` icon, `railtyctl`, dedicated CI/CD (`ci-railty.yml` / `release-railty.yml`), and the Homebrew Tap (`vendettar/homebrew-railty`). |
| **Ghostty Sidegeist** (`sidegeist`) | `https://github.com/tomreinert/ghostty-sidegeist` | **Upstream B (primary source of feature integrations)**. Provides the vertical tab bar, Sidebar, tab dragging and cross-window moves, tab state/notifications, the Git Panel, and adaptation to major Ghostty releases. |
| **Ghostty** (`ghostty`) | `https://github.com/ghostty-org/ghostty` | **Upstream A (primary source of core technical updates)**. Provides the terminal core engine, rendering/CPU/memory optimizations, input and macOS compatibility fixes, security fixes, terminal protocols, the Zig build system, and new configuration options. |

**Core principles**:
- By default, integrate Ghostty major releases through stable Sidegeist updates (Strategy A).
- Do not ignore Ghostty `main` just because Sidegeist has not released yet; for high-value security/crash/macOS/core fixes, Strategy B may selectively port them early after commit-by-commit review.
- **Judge by Railty's functional value, stability, and maintenance cost; never merge Ghostty `main` wholesale.**

---

## 2. Git Remote Configuration and Safe Fetching

Verify or configure the three remotes (if they already exist, verify the URLs; do not add duplicates):

```bash
git remote -v
git remote add ghostty https://github.com/ghostty-org/ghostty.git
git remote add sidegeist https://github.com/tomreinert/ghostty-sidegeist.git
```

### Mandatory Fetch Rules (Avoid Tag Conflicts)

Both `ghostty` and `sidegeist` contain a `tip` tag with the same name, and Railty already has its own `v0.1.0` / `v0.1.1` release tags locally. Running `git fetch sidegeist main --tags` directly fails due to tag collisions (`would clobber existing tag`).

**You must use `--no-tags` to fetch branch history, and use `git ls-remote --tags` to inspect remote release versions read-only:**

```bash
git fetch --no-tags origin +refs/heads/main:refs/remotes/origin/main
git fetch --no-tags ghostty +refs/heads/main:refs/remotes/ghostty/main
git fetch --no-tags sidegeist +refs/heads/main:refs/remotes/sidegeist/main

# Read-only query of remote tags; never force-overwrite local tags
git ls-remote --tags ghostty | tail -n 10
git ls-remote --tags sidegeist | tail -n 10
```

Never use `--tags --force` or force-move an existing tag.

---

## 3. Ghostty and Sidegeist Sync Strategy

### Strategy A — Normal Sidegeist Upgrade (preferred for major version integration)

Applies when: Sidegeist has published a new stable release or valuable standalone commits.

1. Fetch both upstreams and inspect new commits on `sidegeist/main` relative to the current integration baseline (`upstreams.sidegeist.last_integrated_sha` in `state.json`).
2. Distinguish **Sidegeist-only commits** from **commits Sidegeist merged in from Ghostty**:
   - For Ghostty-side commits, reuse the review conclusions in `docs/upstream/ledger.jsonl` (review any new unreviewed ones first).
   - Review Sidegeist-only commits one by one and write them to `ledger.jsonl` (`source: "sidegeist"`).
3. Check whether Railty already cherry-picked any of those Ghostty fixes early via Strategy B, to identify potential duplicates or conflicts in advance.
4. On a dedicated sync branch `sync/sidegeist-<version-or-date>`, perform a real `git merge --no-ff sidegeist/main` (preserve history; do not squash unconditionally).
5. Resolve conflicts and protect Railty-specific assets (see Section 7).
6. Run full tests and build validation (see Section 9); only merge into `main` after confirming everything passes.

### Strategy B — Early Porting of Important Ghostty Updates

Applies when: Sidegeist has not caught up yet, but Ghostty `main` has fixed a security vulnerability, severe crash, macOS compatibility issue, or provides a clearly required capability.

1. Confirm in `docs/upstream/ledger.jsonl` that the commit has been reviewed with `decision == "INCLUDE"`, and check its `dependencies` field.
2. If prerequisite commits exist, you must **evaluate and port them together with the prerequisites in topological order**; do not extract isolated fragments that break prior assumptions, and do not drag in large unknown commits along the way.
3. Create a dedicated sync branch `sync/ghostty-fixes-<YYYY-MM-DD>`.
4. Use `git cherry-pick -x <FULL_SHA>` to preserve provenance.
5. If Sidegeist/Railty modifications prevent a direct apply, adapt manually and record the original SHA and adaptation notes in the commit message and the ledger `notes`.
6. After validation passes, merge into `main`, and update `ledger.jsonl` (`integration: "integrated"`, `railty_commit`, `validation`) and `state.json`.

### Strategy Switching Principles (exceptional cases)

Only when Sidegeist has been unmaintained for a long time and this affects critical security or macOS SDK compatibility may you evaluate using the official Ghostty stable release as the primary upstream; you must first produce an impact analysis report and obtain the user's explicit confirmation. Never change the primary upstream unilaterally during routine syncs.

---

## 4. Commit Review Rules

Before fetching unreviewed commits, first verify `merge-base`, ancestry, and any non-fast-forward anomalies:

```bash
git merge-base HEAD ghostty/main
git merge-base HEAD sidegeist/main
git log --reverse --topo-order --format='%H %ad %s' --date=short <LAST_REVIEWED_SHA>..<REMOTE>/main
```

If `LAST_REVIEWED_SHA` is unreachable (upstream force-rewrote history or a non-fast-forward), **stop advancing the cursor immediately and report the anomaly to the user**.

### Mandatory Checklist per Commit

Do not decide based on the commit title alone; you must run `git show --stat <SHA>` and `git show <SHA>` to check:

1. Commit SHA, commit date, commit message, and linked PR/issue.
2. The actual diff and changed file list (note: Linux/GTK PRs sometimes also modify shared core such as `src/terminal/`; conversely, a title that looks generic may only touch `po/` or website docs).
3. **Merge commit deduplication and Evil Merge checks**:
   - For each merge commit, run `git show <SHA>` (or compare `^1..SHA` against `^2`). If its diff is empty (no additional conflict-resolution code), record that merge wrapper as `SKIP` (`integration: "not-applicable"`) and review the real code in its branch's standalone commits; if it contains a non-empty conflict-resolution diff, that diff must be reviewed separately.
4. Affected subsystem and whether it is a Bug Fix / Security / Performance / macOS Fix / Feature / Toolchain.
5. Whether it depends on a Zig version upgrade (e.g. `0.17.1`), Xcode/SDK changes, or `build.zig.zon` changes.
6. Whether it conflicts with Sidegeist-specific code (`TerminalWindow.swift`, `AppDelegate.swift`, `Sidebar/`, `IPC/`, `Config.zig`, etc.) or Railty-specific code.
7. If context is insufficient, mark it `NEEDS_REVIEW`; never guess and skip.

---

## 5. Classification Standards and Decision Criteria

### Commit Categories (`category`)

| Category | Typical content | Default direction |
|---|---|---|
| `Security` | Out-of-bounds memory access, integer overflow, path/command injection | High-priority evaluation |
| `Critical Bug` | Crashes, data corruption, resize/reflow errors, severe compatibility issues | High-priority evaluation |
| `macOS Bug` | macOS input, windows, tab bar, clipboard, Swift concurrency, Metal | Consider first |
| `Performance` | CPU, memory, rendering, PageList/SIMD optimizations | Evaluate real gains and dependency-chain risk |
| `New Feature` | New terminal protocols, config options, CLI capabilities | Decide by value to Railty's personal use |
| `Build / Toolchain` | Zig version, `build.zig.zon`, Xcode, C ABI/dependencies | Review together with CI/CD compatibility |
| `Refactor` | Internal code cleanup and structural refactoring | Evaluate merge benefits vs. future conflict cost |
| `Tests` | Test cases or test framework fixes | Include with the related fix or skip |
| `Docs / CI` | Translations (`po/`), VOUCHED, documentation, upstream GitHub Actions | Mostly `SKIP` |
| `Platform-specific` | Linux/GTK/FreeBSD/Windows/Android-only paths | `SKIP` after confirming shared core is untouched |

### Decision Enum (`decision`)

- `INCLUDE`: Confirmed suitable for Railty; add to the porting plan (each batch can complete 30-50 reviews and persist them immediately, so no progress is lost).
- `DEFER`: Potentially valuable, but blocked by the current Zig toolchain version (`0.17.0`), chained refactor dependencies, Swift conflict cost, or awaiting a Sidegeist major release.
- `SKIP`: No practical value; pure merge-wrapper node; upstream-only CI/docs/non-macOS platform code.
- `ALREADY_INCLUDED`: The code or equivalent logic already entered Railty via a Sidegeist merge, cherry-pick, or local fix.
- `NEEDS_REVIEW`: Still lacking sufficient evidence or requiring real runtime validation before deciding.

---

## 6. Preventing Duplicate Code Introduction and Handling Conflicts

### Deduplication Checks

Before deciding to cherry-pick or merge, use the following commands to verify whether an equivalent change is already included (do not rely on SHA alone):

```bash
# 1. Check ancestry
git merge-base --is-ancestor <SHA> HEAD && echo "Already in HEAD"

# 2. Compare by patch content (ignoring context line-number differences)
git cherry -v HEAD <UPSTREAM_REF>
git show <SHA> | git patch-id --stable

# 3. Manually compare at the function and behavior level against the local candidate diff
git diff <BASE>..HEAD -- <affected_files>
```

### Conflict Resolution Rules

1. Conflicts must be resolved on a dedicated `sync/*` branch; never force-resolve in a dirty worktree or directly on `main`.
2. When Sidegeist UI/window/tab/Sidebar/Git Panel or Railty branding/CI files are involved, **always protect Railty + Sidegeist logic first**; if necessary, port the underlying Ghostty fix manually instead of overwriting Swift files.
3. After resolving, you must run `git diff --check`, scan for conflict markers (`grep -rn '<<<<<<<' .`), and run build tests.

---

## 7. Protected Boundaries for Railty-Specific Code

Every upstream sync must fully verify that the following assets are neither broken nor overwritten:

- **Branding and identity**: app name `Railty`, bundle ID `com.vendettar.railty`, single `Railty R` icon (`branding/` and asset catalogs; never restore `Ghostty.icns`), the About page, `cli/railtyctl`, and documentation references.
- **Sidegeist core capabilities**: Vertical Tabs, tab drag reordering, cross-window moves, Sidebar, Git Panel, tab notifications and state, IPC protocol.
- **Railty build and release pipeline**:
  - `.github/workflows/ci-railty.yml` and `.github/workflows/release-railty.yml`
  - `dist/macos/{package-railty,sign-railty,notarize-railty}.sh`, `dist/homebrew/update_cask.py`
  - Zig `0.17.0` caching strategy, ARM64 packaging and signing, GitHub Release and automatic Homebrew Tap updates.
- **Upstream workflow isolation**: the 15 unmodified upstream workflows kept in `.github/workflows/` are already disabled in the repository settings; if a sync introduces a new workflow file, it must be disabled immediately per `.github/CI.md`.
- **Absolutely forbidden**: running a repository-wide `Ghostty -> Railty` text replacement; re-enabling upstream release workflows; force-moving published tags; automatically tagging or publishing releases.

---

## 8. Toolchain and Compatibility Checks

Railty CI/CD currently pins **`ZIG_VERSION = "0.17.0"`** (`build.zig.zon`, `ci-railty.yml`, `release-railty.yml`).

Upstream commits touching `build.zig`, `build.zig.zon`, `pkg/`, or `.github/workflows/` must be checked for:
1. Whether `minimum_zig_version` is still compatible with `0.17.0` (note Ghostty `#15230` already bumped it to `0.17.1`).
2. Whether `build.zig.zon` dependency hashes or external fetches affect offline/CI caching.
3. Whether `zig build -Doptimize=ReleaseFast -Demit-macos-app=false -Dxcframework-target=native` can produce `macos/GhosttyKit.xcframework`.
4. Whether Xcode can correctly build `Railty.app` (`xcodebuild -target Ghostty -configuration Release -arch arm64`) and pass validation by `dist/macos/package-railty.sh`.
5. If the Zig version is upgraded, `build.zig.zon`, `ci-railty.yml` (Linux x64 SHA-256), and `release-railty.yml` (macOS arm64 SHA-256 + cache keys) must be updated together.

---

## 9. Post-Sync Validation Process

Run the following validation according to the scope of changes; **a single passing CI run must never replace real build validation**:

1. **Git and formatting checks**:
   - `git diff --check`
   - `zig fmt --check build.zig src/` (or only the changed files)
   - `shellcheck dist/macos/*.sh` (if scripts changed)
2. **Zig tests**:
   - `zig build test -Dtest-filter=<relevant module>` (e.g. `datastruct`, `terminal`, `config`, `simd`, `font`)
   - If `src/vt` or the C ABI is involved, additionally run `zig build test-lib-vt -Dtest-filter=<relevant module>`
3. **GhosttyKit and macOS build**:
   - `zig build -Demit-macos-app=false -Dxcframework-target=native` (or a full `zig build`)
   - Confirm the output `zig-out/Railty.app` (or `macos/build/*/Railty.app`) has `CFBundleIdentifier == com.vendettar.railty`.
4. **Runtime validation (if changes involve UI / Window / Tab / Input / Sidebar)**:
   - Launch `Railty.app` and check creating/closing tabs, Vertical Tabs state, tab drag reordering, cross-window moves, Sidebar refresh, Git Panel, terminal input/output, Shell Integration, and `cli/railtyctl`.
   - If the worker environment has no GUI/interactive capability, the report must **explicitly state which runtime checks were not performed**.

---

## 10. Review Ledger and State File Maintenance

- **`docs/upstream/ledger.jsonl`**:
  - One JSON object per line, corresponding to a unique `(source, sha)`; never append the same SHA from the same source twice.
  - Preserve historical decisions; when a commit is integrated into Railty, **update that record's `integration`, `railty_commit`, `validation`, and `notes`** rather than deleting the original review rationale.
  - `integration` values: `pending` | `integrated` | `adapted` | `not-applicable` | `rejected`.
  - `validation` values: `not-run` | `zig-test-passed` | `macos-build-passed` | `runtime-verified` | `failed`.
- **`docs/upstream/defer-queue.json`**:
  - Create a separate index entry for every `DEFER` record, keep the SHA, and add `group`, `priority` (`P1`/`P2`/`P3`), `revisit_trigger`, `validation_plan`, `review_status`, `last_reassessed_at`, and `notes`.
  - The queue must correspond one-to-one with the ledger: exactly one entry per `DEFER`, and no non-`DEFER` SHA may be included; `tools/upstream/check.sh` enforces this.
  - `revisit_trigger` uses a fixed enum (`on_toolchain_upgrade`, `on_sidegeist_upgrade`, `on_upstream_dependency_update`, `on_macos_snapshot_consumer`, `on_next_sync_review`, `manual_dedicated_port`, `on_user_request`), and every `DEFER` must have a clear trigger condition.
  - When new upstream commits, Sidegeist upgrades, toolchain upgrades, or macOS beginning to use the snapshot API occur, `check.sh` lists entries whose re-review conditions are met; meeting a condition does not mean automatic integration.
- **`docs/upstream/benchmarks/`**: environment, commands, and results of performance experiments; when measurement is impossible, you must write `NOT_TESTED` and the blocking reason, and never pass off CI build time as runtime performance.
- **`docs/upstream/state.json`**:
  - Strictly distinguish `last_reviewed_sha` (how far commit-by-commit review has progressed) from `last_integrated_sha` (the baseline the code history actually contains).
  - Advance `last_reviewed_sha` only after every commit in the range has a ledger record; never guess or skip numbers.
- **`docs/upstream/reviews/YYYY-MM-DD-*.md`**: produce a readable report after every batch review or sync.

---

## 11. Mandatory Startup and Checkpoint Recovery Process for New Workers

### Startup Preflight (required before every task)

1. Read: `AGENTS.md` → `docs/upstream/README.md` → `docs/upstream/state.json` → `docs/upstream/ledger.jsonl` (tail/summary) → `docs/upstream/defer-queue.json` → the latest `docs/upstream/reviews/*.md` → `.github/CI.md`.
2. Run the read-only check script: `./tools/upstream/check.sh`.
3. Confirm unreviewed commits, the pending `INCLUDE` queue, and whether the current task's module is affected by existing upstream fixes:
   - If the feature/bugfix module you are working on already has a fix in Ghostty/Sidegeist, review it first and prefer referencing or porting the upstream solution to avoid reinventing the wheel.
   - If an unintegrated `Security` or `Critical Bug` fix is found, you must proactively flag it in your reply to the user.
   - If the user asked for ordinary feature development, completing the above checks and notifications is enough; **do not start a large upstream merge on your own initiative**.
4. **Check high-priority `DEFER` entries (as important as new commits)**:
   - Read the `DEFER Review Queue` and `DEFER Re-assessment Gates` output of `check.sh`, paying attention to `P1` entries and satisfied `revisit_trigger` values.
   - Verify whether new upstream fixes make an old `DEFER` easier to integrate, whether a new Sidegeist release resolves the conflict, whether the toolchain now permits an old performance patch, or whether a better upstream alternative has appeared.
   - New commits may invalidate an earlier `SKIP` conclusion; when this happens, update the ledger and explain why.
   - For ordinary feature development, only check and notify; **never force a large upstream sync just because of the preflight**; real integration still requires a dedicated branch, the full dependency chain, and tests.

### Resuming an Unfinished Task from a Checkpoint

1. Check `active_task` and `pending_ranges` in `state.json`, and use `./tools/upstream/check.sh` to verify the actual `(source, sha)` set covered by `ledger.jsonl`.
2. Prioritize finishing existing checkpoint ranges with `status != "completed"` or `NEEDS_REVIEW` records; **never re-review from scratch commits already recorded in `ledger.jsonl`**.
3. If a previous worker left an unmerged `sync/*` branch, first verify its build and ledger consistency with `git status` and `git log main..sync/*` before continuing.

---

## 12. Common Mistakes and Prohibitions

The following behaviors are strictly forbidden:
- Directly running `git merge ghostty/main` or bulk blind `git cherry-pick` without review.
- Judging a commit irrelevant from its subject (title) alone and writing it as `SKIP`.
- Writing "reviewed up to some SHA" as "synced/integrated up to some SHA".
- Missing the correspondence between merge commits and the ordinary commits inside their branches (or missing evil merge changes).
- Estimating commit counts or writing fabricated results without running `./tools/upstream/check.sh` and real git commands.
- Overwriting the Railty icon, `com.vendettar.railty`, `railtyctl`, Sidegeist features, or Railty CI/CD.
- Automatically pushing official `v*` tags, triggering official releases, or modifying the Homebrew Tap (unless the user explicitly requests it).

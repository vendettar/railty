# Railty Upstream Initial Baseline Audit (2026-11-17)

本报告基于本地 Git 真实历史、`git show` 实际 diff 与逐条台账 [ledger.jsonl](../ledger.jsonl) 生成，记录 Railty 双上游同步机制建立时的首次完整基线审计结果。

> **状态声明**：本次任务完成了基线验证、制度建设及全部 395 个 Ghostty post-`v1.4.0` 提交的**逐条审查（Reviewed）**，按 **PR、功能主题（`topic`）与依赖链（`dependencies`）** 完成聚合，同时在 [ledger.jsonl](../ledger.jsonl) 中为每个 Commit 保留了独立追踪记录。**尚未向 Railty `main` 合并或 Cherry-pick 任何上游代码（Integrated = 0）**，后续 Worker 只需从 `5ebe501a63425b13d9952e8c54682c046386e5af` 之后增量审查。

---

## 1. 三仓库基线与 Git 拓扑关系

| 仓库 / 引用 | 真实 Commit SHA | 提交日期 | 标签 / 版本说明 |
|---|---|---|---|
| **Railty (`HEAD` / `origin/main`)** | `f81a05d702f6f757fd6715833d7f7b4c107f6641` | 2026-11-17 | `v0.1.2`（含 Railty 品牌、图标、CI/CD、Homebrew Tap） |
| **Sidegeist (`sidegeist/main`)** | `5904a523477542b114939d93594f82348f27b3b5` | 2026-10-28 | `v1.4.0-fork.1`（`Merge upstream v1.4.0`） |
| **Ghostty Stable (`v1.4.0`)** | `83fb95624b0439ee660c2679b43b38c8b63769cd` | 2026-10-27 | 最新稳定发布版 `v1.4.0`（tag 对象 `ce787fc18a`） |
| **Ghostty Main (`ghostty/main`)** | `5ebe501a63425b13d9952e8c54682c046386e5af` | 2026-11-16 | 开发主线（`1.4.1-dev`；`vt-1.0.1` 已于 2026-11 切出） |

### 拓扑关系实测结果

- **`merge-base(HEAD, sidegeist/main)`** = `5904a523477542b114939d93594f82348f27b3b5`
  - **Sidegeist 领先 Railty**：`0` 个提交（Railty 已完整包含 Sidegeist `main` 全部历史）。
  - **Railty 领先 Sidegeist**：`8` 个提交（`9ebc075a7..f81a05d70`，均为 Railty 品牌、图标、`railtyctl` 标识、`ci-railty.yml`、`release-railty.yml`、打包/签名脚本与 Homebrew Tap）。
- **`merge-base(HEAD, ghostty/main)`** = `83fb95624b0439ee660c2679b43b38c8b63769cd`（Ghostty `v1.4.0`）
- **`merge-base(sidegeist/main, ghostty/main)`** = `83fb95624b0439ee660c2679b43b38c8b63769cd`（Ghostty `v1.4.0`）
- **Ghostty `v1.4.0..ghostty/main` 新增提交总数**：`395` 个提交
  - `--first-parent` 提交：`162` 个
  - Merge Commit：`128` 个（经 diff 核查，`0` 个 evil merge / 冲突解决额外修改）
  - 非合并实质提交：`267` 个
- **Patch-ID 重合检测**：对 `HEAD` 领先 `v1.4.0` 与 Ghostty 267 个非合并提交进行 `git patch-id --stable` 比对，重合数为 `0`。
- **Fetch 注意事项**：`ghostty` 与 `sidegeist` 均存在同名 `tip` tag，且本地已存在 `v0.1.0`/`v0.1.1`。拉取双上游必须使用 `git fetch --no-tags <remote> +refs/heads/main:refs/remotes/<remote>/main`，配合 `git ls-remote --tags <remote>` 只读检查远端 tag。

---

## 2. 逐 Commit 审查统计

审查区间：`83fb95624b0439ee660c2679b43b38c8b63769cd..5ebe501a63425b13d9952e8c54682c046386e5af`（共 `395` 条，100% 写入 [ledger.jsonl](../ledger.jsonl)）。

### 按决策与风险分布

| 决策状态 | 全部 395 提交 | 非合并 267 提交 | 风险分布 (`risk`) | 说明 |
|---|---:|---:|---|---|
| **`INCLUDE`** | **45** | **45** | `low`: 40, `medium`: 5 | 确定适合 Railty，列入优先移植队列（含前置依赖链） |
| **`DEFER`** | **149** | **149** | `high`: 118, `medium`: 31 | 受制于 Zig `0.17.1`、成链重构/性能波次、Swift 冲突或等待 Sidegeist |
| **`SKIP`** | **201** | **73** | `none`: 201 | 128 个纯 Merge 包装节点 + 73 个无关提交（翻译、VOUCHED、Linux/GTK/Win/Android、官网/官方 CI） |
| **`ALREADY_INCLUDED`** | **0** | **0** | — | 当前无提前移植或重合补丁 |
| **`NEEDS_REVIEW`** | **0** | **0** | — | 全部 395 个提交均已基于真实 diff 完成分类与判断 |

### 按提交类别分布

| 类别 (`category`) | 数量 | 主要构成 |
|---|---:|---|
| `Build / Toolchain` | 107 | `libghostty-vt` 1.0 C ABI/依赖清理、Zig `0.17.1` 升级、构建脚手架 |
| `Docs / CI` | 78 | VOUCHED、翻译（`po/`）、官网文档、GitHub Actions |
| `Refactor` | 71 | 内部架构整理、Unicode/PageList/Render 重构 |
| `Critical Bug` | 57 | 终端核心 resize/reflow、Kitty 图形内存、config/cli/simdutf/font 稳定性修复 |
| `Performance` | 26 | PageList `carried_capacity`、packed `u128` Style、blank row fast path、SIMD 优化 |
| `Tests` | 17 | 回归测试与测试基础设施修复 |
| `macOS Bug` | 16 | macOS 27 tab bar frame、Swift MainActor 隔离、clipboard quit、split mouse、selection copy |
| `Platform-specific` | 13 | Linux/GTK、FreeBSD、Windows、Android 专用修改 |
| `New Feature` | 7 | DECIC/DECDC/DECBI/DECFI、tmux active_window、`set_window_theme`、iTerm2 配色更新 |
| `Security` | 3 | `circ_buf` 算术溢出与容量溢出检查、`os/exe` 路径空终止符空间预留 |

---

## 3. 按功能主题（`topic`）与 PR 聚合视图（全量 395 条）

每个 Commit 的独立 `sha`、`pr`、`merge_commit`、`dependencies` 与 `risk` 均保存在 [ledger.jsonl](../ledger.jsonl)；下表给出全部 395 条记录按功能主题的聚合视图：

| 功能主题 (`topic`) | 提交数 | INCLUDE | DEFER | SKIP | 风险等级 | 说明 |
|---|---:|---:|---:|---:|---|---|
| `security-circbuf` | 6 | 4 | 0 | 2 | **Low** | `#14958` + `#14987` 完整 4 连修复链 + 2 merge |
| `security-exe-path` | 2 | 1 | 0 | 1 | **Low** | `#15058` 独立修复 + 1 merge |
| `macos-ui-input` | 18 | 6 | 1 | 11 | **Low–Medium** | `#14999`, `#14971`, `#15040`, `#15029`, `#15190`, `#15147` 纳入；`#15039` 暂缓 |
| `terminal-core-resize-render` | 20 | 10 | 2 | 8 | **Low** | resize/reflow/formatter/OOM 重试修复（`#14918`..`#15237`） |
| `terminal-kitty-graphics` | 10 | 4 | 1 | 5 | **Low** | `#15094`, `#15086`, `#15103`, `#15184` 纳入；`#15225` 测试调整暂缓 |
| `config-cli-split` | 15 | 9 | 0 | 6 | **Low** | `#14876`, `#14879`, `#14904`, `#14908`, `#14921`, `#14950`, `#15073` |
| `cli-ssh-terminfo` | 7 | 4 | 0 | 3 | **Low** | `#14916` → `#15061` → `#15112` SSH terminfo 完整链 |
| `simd-utf8` | 10 | 2 | 3 | 5 | **Low** | `#15156`/`#15162` UTF-8 错码修复纳入；x86 AVX-512 暂缓 |
| `font-discovery-fallback` | 5 | 3 | 1 | 1 | **Low** | `#15216` 3 个 font discovery/fallback 修复纳入；fontconfig bump 暂缓 |
| `build-darwin-quirk` | 4 | 2 | 0 | 2 | **Medium** | `#15189` Darwin memset quirk 修复（注意分离 `.github/workflows/test.yml` 改动） |
| `libghostty-vt-and-deps` | 119 | 0 | 76 | 43 | **High** | `libghostty-vt 1.0` C ABI/doxygen/依赖拆分，待 Sidegeist 大版本整合 |
| `terminal-perf-pagelist-fastpath` | 48 | 0 | 28 | 20 | **High** | `carried_capacity`、`Style` 位压缩、`RowBuilder/print` 快路径及后续回归修补链 |
| `terminal-refcounted-set` | 8 | 0 | 7 | 1 | **High** | `#15121` 死 ID 复用与分页引用计数重构链 |
| `terminal-misc-refactor` | 34 | 0 | 12 | 22 | **Medium** | 内部重构、CSI 解析整理与差分化测试调参 |
| `tmux-control-mode` | 10 | 0 | 8 | 2 | **Medium** | `#14273`、`#14947` tmux 协议与测试变更链 |
| `new-features-themes` | 10 | 0 | 6 | 4 | **Medium–High** | `DECIC/DECDC/DECBI/DECFI`、`set_window_theme`（冲突 Config）、iTerm2 配色 |
| `toolchain-zig-upgrade` | 6 | 0 | 4 | 2 | **High** | `#15230` Zig `0.17.1` 升级（当前 Railty CI 固定 `0.17.0`） |
| `platform-non-macos` | 10 | 0 | 0 | 10 | **None** | Linux/GTK/FreeBSD/Windows/Android 专用提交 |
| `i18n-docs-ci` | 53 | 0 | 0 | 53 | **None** | `po/` 翻译、`VOUCHED`、官网文档、上游 CI |

---

## 4. 优先纳入清单与风险等级（`INCLUDE` = 45 个）

> 以下独立修复与依赖链均已通过 `git apply --check` 或冲突预检，可在同步分支 `sync/ghostty-fixes-*` 按组使用 `git cherry-pick -x` 移植并完成编译/测试验证。

### A. 安全修复（`Low` 风险 — 5 个）

| 顺序 / PR | Commit SHA | 内容 | 依赖链 | 风险等级 | 验证要求 |
|---|---|---|---|---|---|
| `#145` / `#15058` | `2d1f9cf109` | `os: reserve space for executable path terminator` | 独立 | **Low** | `zig build test -Dtest-filter=exe` |
| `#61` / `#14958` | `9644c7571d` | `datastruct: fix clearing circular buffers with zero capacity` | 链起点 | **Low** | `zig build test -Dtest-filter=circ_buf` |
| `#88` / `#14987` | `5e7714e71c` | `datastruct: prevent overflow in circular buffer arithmetic` | `← 9644c7571d` | **Low** | 同上 |
| `#89` / `#14987` | `0aa2f7caf5` | `datastruct: use checked addition for buffer capacity` | `← 5e7714e71c` | **Low** | 同上 |
| `#90` / `#14987` | `c7eb3e8b96` | `datastruct: restore circular buffer explanations` | `← 0aa2f7caf5` | **Low** | 同上 |

### B. macOS 专属修复（`Low`–`Medium` 风险 — 6 个）

| 顺序 / PR | Commit SHA | 内容 | 风险等级 | 注意事项 |
|---|---|---|---|---|
| `#100` / `#14971` | `f7b25c8129` | `termio: don't require RFC 1123 hostnames in OSC 7` | **Low** | 直接修复非 RFC 1123 主机名下 Sidebar 目录显示 |
| `#138` / `#15040` | `b148bf7285` | `macos: allow quitting with a clipboard confirmation open` | **Low** | 需 macOS Xcode 编译 + 弹窗退出手测 |
| `#147` / `#15029` | `0edfc656fa` | `macOS: fix tab bar frame on macOS 27 when it first appears.` | **Low** | 需核对 Sidegeist 垂直/原生 tab bar 显示状态 |
| `#98` / `#14999` | `fd29936f09` | `macos: make Surface main actor-isolated` | **Medium** | 需验证 Sidegeist `SurfaceView` / `TerminalController` Swift 6 并发编译 |
| `#349` / `#15190` | `4edde79c03` | `macos: fix split activation mouse handling` | **Medium** | 移植前核对 Sidegeist `TerminalWindow`/`BaseTerminalController` 鼠标焦点逻辑 |
| `#375` / `#15147` | `a0fe573fe3` | `config: copy-on-select defaults to the selection clipboard on macOS` | **Medium** | 触及 `Config.zig`，确认不覆盖 Sidegeist 配置默认值 |

### C. 终端核心、Resize、渲染与 Kitty 图形（`Low` 风险 — 14 个）

- **Resize / Formatter / Selection / Render（10 个，Low Risk）**：
  - `f761046d6b` (`#36`, `#14918`): `formatter: restore a pending wrap at the right margin`
  - `5ce2325ec6` (`#191`, `#15085`): `terminal: clear cursor pin garbage flag after resize`
  - `de202be94a` (`#230`, `#15113`): `terminal: keep triple-click selection over blank lines`
  - `1b8b3f55bc` (`#275`, `#15134`): `terminal: remap pins when the column growth backfill stops early`
  - `b543fbed1a` (`#281`, `#15127`) → `3e29fcd628` (`#282`, `#15127`): 渲染 OOM 回归测试与 `dirty rows` 失败重试
  - `321a32a423` (`#291`, `#15141`): `terminal: fix scrollback not pulled down when growing rows and shrinking cols`
  - `8ad3f607fd` (`#351`, `#15199`): `terminal: prompt redraw on resize no longer leaves stale prompts`
  - `f7d91fa456` (`#354`, `#15200`): `terminal: search thread test no longer crashes on timeout`
  - `dcdb1674cf` (`#365`, `#15222`): `terminal: clear a clone's padding rows to their page's width`
  - `f4830b2f18` (`#390`, `#15237`): `terminal: don't check PageList integrity mid-way through growing rows`
- **Kitty 图形协议稳定性（4 个，Low Risk）**：
  - `383a6f6ae3` (`#199`, `#15094`) → `4441aabcaf` (`#228`, `#15103`): 按传输序查找最新编号图像与淘汰最老图像
  - `44385f07c3` (`#201`, `#15086`): `terminal/kitty: only target virtual placements from placeholders`
  - `c4b91fe4c7` (`#337`, `#15184`): `terminal/kitty: keep a replaced image until its transmission ends`

### D. Config / CLI / SSH / SIMD UTF-8 / Font / Darwin 构建（`Low`–`Medium` 风险 — 20 个）

- **Config / Split Tree / CLI（9 个，Low Risk）**：
  - `241a7bca3b` (`#2`, `#14876`): `cli: fix Unicode escape validation`
  - `5c1d15f9b5` (`#6`, `#14879`): `config: prevent panic on truncated UTF-8`
  - `0cb81fe084` (`#17`, `#14904`): `datastruct/split_tree: assert goto() is given a valid handle`
  - `4c8ad9817e` (`#19`, `#14908`) → `9ee1031ba7` (`#20`, `#14908`): 长环境变量格式化与测试
  - `8c04d7c2e8` (`#50`, `#14921`) → `90ed851dea` (`#54`, `#14950`): direct commands 空命令与多余空格校验
  - `def58d386b` (`#168`, `#15073`): `cli: flush plain color list output`
- **SSH Terminfo 安装链（4 个按序，Low Risk）**：
  - `4d7de0a483` (`#63`, `#14916`) → `9b4a0076d2` (`#225`, `#15061`) → `6283611ddf` (`#226`, `#15061`) → `3c3f33121a` (`#272`, `#15112`)
- **SIMD UTF-8 解码（2 个按序，Low Risk）**：
  - `0f10e6698e` (`#302`, `#15156`) → `c1f4409661` (`#312`, `#15162`)
- **Font Discovery / Fallback（3 个，Low Risk）**：
  - `ba283a6f90` (`#378`, `#15216`)
  - `efd4a82bda` (`#379`, `#15216`) → `ef21f065f8` (`#380`, `#15216`)
- **Darwin 构建修复（2 个，Medium Risk）**：
  - `9899c07077` (`#339`, `#15189`) → `a5eeb89790` (`#340`, `#15189`)：`9899c07077` 附带修改了上游 `.github/workflows/test.yml`，移植时仅保留 `build.zig` 与 `libsystem_override.sh` 修复，避免引入禁用工作流的无关冲突。

---

## 5. 关键 `DEFER` 高风险依赖链与暂缓原因

1. **Zig `0.17.1` 工具链升级（`High Risk` — `#15230` / `1d84459682`）**：
   - Ghostty 已于 2026-11-16 将 `.minimum_zig_version` 升至 `0.17.1`。Railty `build.zig.zon`、`ci-railty.yml` 与 `release-railty.yml` 固定 `0.17.0`；需决定升级 CI/Release 工具链与 cache key 后再统一跟进。
2. **`libghostty-vt 1.0` C ABI 与依赖重构波次（`High Risk` — `#15068`..`#15196`，76 个 `DEFER`）**：
   - 涉及 `deps/` 目录迁移、ABI 导出符号、Doxygen 与回调结构体改版，对 Railty 桌面应用无直接收益且合并冲突面广，等待 Sidegeist 下个大版本统一继承。
3. **`PageList` / `Style` / `RowBuilder` 性能与 `RefCountedSet` 重构链（`High Risk` — 35 个 `DEFER`）**：
   - `#14985`..`#15163` 与 `#15121` 存在密集的前后依赖与回归修补（如 `#15030`, `#15032`, `#15034`, `#15111` 修补了前期快路径引入的边界错误），切勿零散摘取。
4. **Sidegeist 专属代码冲突 PR（`High Risk`）**：
   - `#15039`（`0e067ded70`）修改 `TerminalWindow.swift`，`#14208`（`6ba2c2b270`/`dce5a9464a`）修改 `Config.zig` 与多端窗口主题接口，均与 Sidegeist 垂直标签栏/Sidebar 修改重叠，需专门适配或随 Sidegeist 跟进。

---

## 6. 下一位 Worker 行动起点（增量审查机制已就绪）

- 已完成 `v1.4.0..5ebe501a63` 全量 395 个提交的基线审计与台账持久化，后续 Worker **无需重审这 395 个提交**。
- 下次只需执行 `./tools/upstream/check.sh`，即可自动列出 `5ebe501a63425b13d9952e8c54682c046386e5af` 之后新增的增量提交。
- 若开始执行实际移植，请在独立分支 `sync/ghostty-fixes-2026-11` 从第 4 节的 **Low Risk Security/Core** 组开始分批 Cherry-pick 并运行完整编译与运行时验证。

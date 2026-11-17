# Railty Upstream Sync Protocol & Worker Guide

本文件是 **Railty** 双上游同步与逐 Commit 审查机制的权威操作规范。任何接手 Railty 维护、开发或上游同步的 AI Worker 与维护者都必须严格遵守本指南。

---

## 1. 三仓库关系与维护目标

| 仓库 | 地址 | 角色与职责 |
|---|---|---|
| **Railty** (`origin`) | `https://github.com/vendettar/railty` | 个人维护的 macOS 原生终端发行版。拥有独立品牌、`com.vendettar.railty`、`Railty R` 图标、`railtyctl`、专用 CI/CD（`ci-railty.yml` / `release-railty.yml`）和 Homebrew Tap（`vendettar/homebrew-railty`）。 |
| **Ghostty Sidegeist** (`sidegeist`) | `https://github.com/tomreinert/ghostty-sidegeist` | **Upstream B（主要功能集成来源）**。提供垂直标签栏、Sidebar、Tab 拖拽与跨窗口移动、Tab 状态/通知、Git Panel 及针对 Ghostty 大版本的适配。 |
| **Ghostty** (`ghostty`) | `https://github.com/ghostty-org/ghostty` | **Upstream A（核心技术更新来源）**。提供终端核心引擎、渲染/CPU/内存优化、输入与 macOS 兼容修复、安全修复、终端协议、Zig 构建系统与新配置项。 |

**核心原则**：
- 默认通过 Sidegeist 稳定更新整合 Ghostty 大版本（Strategy A）。
- 不因 Sidegeist 尚未发版而忽视 Ghostty `main`；对高价值安全/崩溃/macOS/核心修复，允许经逐 Commit 审查后通过 Strategy B 选择性提前移植。
- **以 Railty 的功能价值、稳定性和维护成本为准则，严禁无差别全量合并 Ghostty `main`。**

---

## 2. Git Remote 配置与安全拉取

验证或配置三个 Remote（若已存在则核对 URL，不要重复添加）：

```bash
git remote -v
git remote add ghostty https://github.com/ghostty-org/ghostty.git
git remote add sidegeist https://github.com/tomreinert/ghostty-sidegeist.git
```

### 强制拉取规则（避免 Tag 冲突）

`ghostty` 与 `sidegeist` 均包含同名 `tip` tag，且 Railty 本地已有自己的 `v0.1.0` / `v0.1.1` 发布标签。直接运行 `git fetch sidegeist main --tags` 会因 tag 碰撞而失败（`would clobber existing tag`）。

**必须使用 `--no-tags` 拉取分支历史，并用 `git ls-remote --tags` 只读查看远端发布版本：**

```bash
git fetch --no-tags origin +refs/heads/main:refs/remotes/origin/main
git fetch --no-tags ghostty +refs/heads/main:refs/remotes/ghostty/main
git fetch --no-tags sidegeist +refs/heads/main:refs/remotes/sidegeist/main

# 只读查询远端标签，不强制覆盖本地 Tag
git ls-remote --tags ghostty | tail -n 10
git ls-remote --tags sidegeist | tail -n 10
```

严禁使用 `--tags --force` 或强行移动已有 tag。

---

## 3. Ghostty 与 Sidegeist 同步策略

### Strategy A — Sidegeist 正常升级（优先用于大版本整合）

适用条件：Sidegeist 发布了新的稳定版本或有价值的独立提交。

1. 拉取双上游，检查 `sidegeist/main` 相对当前整合基线（`state.json` 的 `upstreams.sidegeist.last_integrated_sha`）的新增提交。
2. 区分 **Sidegeist 独有提交** 与 **Sidegeist 从 Ghostty 合并进来的提交**：
   - Ghostty 侧提交直接复用 `docs/upstream/ledger.jsonl` 中的审查结论（如有新增未审先补审）。
   - Sidegeist 独有提交逐条审查并写入 `ledger.jsonl`（`source: "sidegeist"`）。
3. 核对 Railty 是否已通过 Strategy B 提前 Cherry-pick 过其中的 Ghostty 修复，提前识别潜在重复或冲突。
4. 在独立同步分支 `sync/sidegeist-<version-or-date>` 执行真实 `git merge --no-ff sidegeist/main`（保留历史，不无条件 squash）。
5. 解决冲突并保护 Railty 专属资产（见第 7 节）。
6. 执行完整测试与构建验证（见第 9 节），确认无误后再合入 `main`。

### Strategy B — Ghostty 重要更新提前移植

适用条件：Sidegeist 尚未跟进，但 Ghostty `main` 已修复安全漏洞、严重崩溃、macOS 兼容问题或提供明确所需能力。

1. 在 `docs/upstream/ledger.jsonl` 确认该提交已审查且 `decision == "INCLUDE"`，并检查 `dependencies` 字段。
2. 若存在前置依赖提交，必须**按拓扑顺序连同前置依赖一起评估与移植**，不得孤立摘取破坏前序假设的片段，也不得顺带拖入大规模未知提交。
3. 创建独立同步分支 `sync/ghostty-fixes-<YYYY-MM-DD>`。
4. 使用 `git cherry-pick -x <FULL_SHA>` 保留来源追踪。
5. 若因 Sidegeist/Railty 修改导致不能直接应用，可手动适配，并在 commit message 与台账 `notes` 中记录原 SHA 及适配说明。
6. 验证通过后合入 `main`，并更新 `ledger.jsonl`（`integration: "integrated"`, `railty_commit`, `validation`）及 `state.json`。

### 策略切换原则（特殊情况）

仅当 Sidegeist 长期停止维护且影响关键安全/macOS SDK 兼容时，方可评估直接以 Ghostty 官方稳定版作为主上游；必须先输出影响分析报告并获得用户明确确认，严禁在日常同步中擅自变更主上游。

---

## 4. Commit 审查规则

获取未审查提交前，先核对 `merge-base`、祖先关系与非 fast-forward 异常：

```bash
git merge-base HEAD ghostty/main
git merge-base HEAD sidegeist/main
git log --reverse --topo-order --format='%H %ad %s' --date=short <LAST_REVIEWED_SHA>..<REMOTE>/main
```

若发现 `LAST_REVIEWED_SHA` 不可达（上游强制重写历史或非 fast-forward），**立即停止推进游标并向用户报告异常**。

### 每个 Commit 必查清单

不能只看 Commit 标题做决定，必须运行 `git show --stat <SHA>` 与 `git show <SHA>` 检查：

1. Commit SHA、提交日期、Commit Message 及关联 PR/Issue。
2. 实际 Diff 与修改文件清单（注意：Linux/GTK PR 有时也修改 `src/terminal/` 等共享核心；反之标题看似通用也可能仅改 `po/` 或官网文档）。
3. **Merge Commit 防重与 Evil Merge 检查**：
   - 对每个 merge commit，运行 `git show <SHA>`（或对比 `^1..SHA` 与 `^2`）。若其 diff 为空（无额外冲突解决代码），将该 merge wrapper 记为 `SKIP`（`integration: "not-applicable"`），真实代码归属其分支内独立 commit 审查；若包含非空冲突解决 diff，须单独审查该 diff。
4. 影响子系统、是否属于 Bug Fix / Security / Performance / macOS Fix / Feature / Toolchain。
5. 是否依赖 Zig 版本升级（如 `0.17.1`）、Xcode/SDK 变更或 `build.zig.zon` 改动。
6. 是否与 Sidegeist 专属代码（`TerminalWindow.swift`、`AppDelegate.swift`、`Sidebar/`、`IPC/`、`Config.zig` 等）或 Railty 专属代码冲突。
7. 上下文不足时标记 `NEEDS_REVIEW`，严禁猜测跳过。

---

## 5. 分类标准与决策准则

### 提交分类 (`category`)

| Category | 典型内容 | 默认方向 |
|---|---|---|
| `Security` | 内存越界、整数溢出、路径/命令注入 | 高优先级评估 |
| `Critical Bug` | 崩溃、数据损坏、resize/reflow 错误、严重兼容问题 | 高优先级评估 |
| `macOS Bug` | macOS 输入、窗口、tab bar、剪贴板、Swift 并发、Metal | 优先考虑 |
| `Performance` | CPU、内存、渲染、PageList/SIMD 优化 | 评估真实收益与依赖链风险 |
| `New Feature` | 新终端协议、配置项、CLI 能力 | 按 Railty 个人使用价值决定 |
| `Build / Toolchain` | Zig 版本、`build.zig.zon`、Xcode、C ABI/依赖 | 联合 CI/CD 兼容性审查 |
| `Refactor` | 内部代码清理与结构重构 | 评估合并收益与后续冲突成本 |
| `Tests` | 测试用例或测试框架修正 | 随关联修复纳入或跳过 |
| `Docs / CI` | 翻译 (`po/`)、VOUCHED、文档、上游 GitHub Actions | 多数 `SKIP` |
| `Platform-specific` | 仅 Linux/GTK/FreeBSD/Windows/Android 路径 | 确认未改共享核心后 `SKIP` |

### 决策枚举 (`decision`)

- `INCLUDE`：确定适合 Railty，列入移植计划（每批可执行 30~50 条审查并即时持久化，不丢失进度）。
- `DEFER`：有潜在价值，但受制于当前 Zig 工具链版本（`0.17.0`）、成链重构依赖、Swift 冲突成本或等待 Sidegeist 大版本整合。
- `SKIP`：确定无实际价值、纯 Merge wrapper 节点、上游专属 CI/文档/非 macOS 平台代码。
- `ALREADY_INCLUDED`：代码或等效逻辑已通过 Sidegeist Merge、Cherry-pick 或本地修复进入 Railty。
- `NEEDS_REVIEW`：尚缺足够证据或需要真实运行验证才能定性。

---

## 6. 防止重复引入代码与冲突处理

### 去重检查方法

在决定 Cherry-pick 或合并前，用以下命令核查是否已被等效包含（不要仅靠 SHA 判断）：

```bash
# 1. 检查祖先关系
git merge-base --is-ancestor <SHA> HEAD && echo "Already in HEAD"

# 2. 基于补丁内容比对（忽略上下文行号差异）
git cherry -v HEAD <UPSTREAM_REF>
git show <SHA> | git patch-id --stable

# 3. 与本地候选 diff 做函数与行为级人工核对
git diff <BASE>..HEAD -- <affected_files>
```

### 冲突处理规范

1. 冲突解决必须在独立分支 `sync/*` 完成，严禁在脏工作区或直接 `main` 上强行解决。
2. 涉及 Sidegeist UI/窗口/Tab/Sidebar/Git Panel 或 Railty 品牌/CI 文件时，**始终以保护 Railty + Sidegeist 逻辑为前提**，必要时人工移植 Ghostty 底层修复而非覆盖 Swift 文件。
3. 解决后必须运行 `git diff --check`、冲突标记扫描（`grep -rn '<<<<<<<' .`）及构建测试。

---

## 7. Railty 专属代码保护边界

每次上游同步必须完整核对以下资产不被破坏或覆盖：

- **品牌与身份**：应用名称 `Railty`、Bundle ID `com.vendettar.railty`、Single `Railty R` 图标（`branding/` 及资产目录，禁止恢复 `Ghostty.icns`）、About 页面、`cli/railtyctl` 与文档引用。
- **Sidegeist 核心能力**：Vertical Tabs、Tab 拖拽排序、跨窗口移动、Sidebar、Git Panel、Tab 通知与状态、IPC 协议。
- **Railty 构建与发布体系**：
  - `.github/workflows/ci-railty.yml` 与 `.github/workflows/release-railty.yml`
  - `dist/macos/{package-railty,sign-railty,notarize-railty}.sh`、`dist/homebrew/update_cask.py`
  - Zig `0.17.0` 缓存策略、ARM64 打包签名、GitHub Release 与 Homebrew Tap 自动更新。
- **上游 Workflow 隔离**：`.github/workflows/` 中保留未修改的 15 个上游工作流已在仓库设置中禁用；同步若引入新 workflow 文件，必须按 `.github/CI.md` 立即禁用。
- **绝对禁止**：对全仓库执行 `Ghostty -> Railty` 全局文本替换；重新启用上游发布流；强制移动已发布 Tag；自动打 Tag 或发布 Release。

---

## 8. 工具链与兼容检查

Railty CI/CD 当前固定 **`ZIG_VERSION = "0.17.0"`**（`build.zig.zon`、`ci-railty.yml`、`release-railty.yml`）。

涉及 `build.zig`、`build.zig.zon`、`pkg/` 或 `.github/workflows/` 的上游提交必须检查：
1. `minimum_zig_version` 是否仍兼容 `0.17.0`（注意 Ghostty `#15230` 已升至 `0.17.1`）。
2. `build.zig.zon` 依赖哈希或外部拉取是否影响离线/CI 缓存。
3. `zig build -Doptimize=ReleaseFast -Demit-macos-app=false -Dxcframework-target=native` 能否生成 `macos/GhosttyKit.xcframework`。
4. Xcode 能否正确编译 `Railty.app`（`xcodebuild -target Ghostty -configuration Release -arch arm64`）并通过 `dist/macos/package-railty.sh` 校验。
5. 若升级 Zig 版本，必须同步更新 `build.zig.zon`、`ci-railty.yml`（Linux x64 SHA-256）与 `release-railty.yml`（macOS arm64 SHA-256 + 缓存键）。

---

## 9. 同步后的验证流程

按改动范围执行以下验证，**禁止以单一 CI 通过替代真实构建验证**：

1. **Git 与格式检查**：
   - `git diff --check`
   - `zig fmt --check build.zig src/`（或仅修改文件）
   - `shellcheck dist/macos/*.sh`（若改脚本）
2. **Zig 测试**：
   - `zig build test -Dtest-filter=<相关模块>`（如 `datastruct`、`terminal`、`config`、`simd`、`font`）
   - 如涉及 `src/vt` 或 C ABI，追加 `zig build test-lib-vt -Dtest-filter=<相关模块>`
3. **GhosttyKit 与 macOS 编译**：
   - `zig build -Demit-macos-app=false -Dxcframework-target=native`（或完整 `zig build`）
   - 确认输出 `zig-out/Railty.app`（或 `macos/build/*/Railty.app`）且 `CFBundleIdentifier == com.vendettar.railty`。
4. **运行时验证（若变更涉及 UI / Window / Tab / Input / Sidebar）**：
   - 启动 `Railty.app`，检查新建/关闭 Tab、Vertical Tabs 状态、Tab 拖拽排序、跨窗口移动、Sidebar 刷新、Git Panel、终端输入输出、Shell Integration 与 `cli/railtyctl`。
   - 若 Worker 运行环境无 GUI/交互能力，必须在报告中**显式标注哪些运行时检查未执行**。

---

## 10. 审查台账与状态文件维护

- **`docs/upstream/ledger.jsonl`**：
  - 每行一条 JSON，对应唯一 `(source, sha)`，严禁重复追加同一来源的同一 SHA。
  - 保留历史决策；当提交被集成到 Railty 时，**更新该条记录的 `integration`、`railty_commit`、`validation` 与 `notes`**，不要删除原审查理由。
  - `integration` 取值：`pending` | `integrated` | `adapted` | `not-applicable` | `rejected`。
  - `validation` 取值：`not-run` | `zig-test-passed` | `macos-build-passed` | `runtime-verified` | `failed`。
- **`docs/upstream/defer-queue.json`**：
  - 为每一条 `DEFER` 记录建立独立索引项，保留 SHA，并补充 `group`、`priority`（`P1`/`P2`/`P3`）、`revisit_trigger`、`validation_plan`、`review_status`、`last_reassessed_at` 与 `notes`。
  - 队列必须与台账一一对应：每个 `DEFER` 恰好一项，且不得包含非 `DEFER` 的 SHA；`tools/upstream/check.sh` 会强制校验。
  - `revisit_trigger` 使用固定枚举（`on_toolchain_upgrade`、`on_sidegeist_upgrade`、`on_upstream_dependency_update`、`on_macos_snapshot_consumer`、`on_next_sync_review`、`manual_dedicated_port`、`on_user_request`），每条 `DEFER` 必须有明确触发条件。
  - 新的上游提交、Sidegeist 升级、工具链升级或 macOS 开始使用快照 API 时，`check.sh` 会列出已满足复审条件的条目；满足条件不等于自动集成。
- **`docs/upstream/benchmarks/`**：性能实验的环境、命令与结果；无法测量时必须写 `NOT_TESTED` 与阻塞原因，禁止用 CI 构建耗时冒充运行时性能。
- **`docs/upstream/state.json`**：
  - 严格区分 `last_reviewed_sha`（已经逐条审查到的位置）与 `last_integrated_sha`（代码历史已经真正包含的基线）。
  - 仅在区间内全部提交都有台账记录后，才推进 `last_reviewed_sha`；不得猜测或跳号。
- **`docs/upstream/reviews/YYYY-MM-DD-*.md`**：每次批量审查或同步完成后生成可读报告。

---

## 11. 新 Worker 强制启动与断点恢复流程

### 启动 Preflight（每次任务前必须执行）

1. 读取：`AGENTS.md` → `docs/upstream/README.md` → `docs/upstream/state.json` → `docs/upstream/ledger.jsonl`（尾部/汇总）→ `docs/upstream/defer-queue.json` → 最近一次 `docs/upstream/reviews/*.md` → `.github/CI.md`。
2. 运行只读检查脚本：`./tools/upstream/check.sh`。
3. 确认未审查提交、待移植 `INCLUDE` 队列、以及当前任务模块是否受上游已有修复影响：
   - 若正在开发的功能/修 bug 模块在 Ghostty/Sidegeist 已有修复，优先审查并参考或先移植上游方案，避免重复造轮子。
   - 若发现未集成的 `Security` 或 `Critical Bug` 修复，必须在给用户的回复中主动提醒。
   - 若用户要求的是普通功能开发，完成上述检查与提醒即可，**不得擅自启动大规模上游合并**。
4. **检查高优先级 `DEFER`（与新增提交同等重要）**：
   - 读取 `check.sh` 的 `DEFER Review Queue` 与 `DEFER Re-assessment Gates` 输出，关注 `P1` 条目与已满足的 `revisit_trigger`。
   - 核对上游新修复是否让旧 `DEFER` 更容易集成、Sidegeist 新版本是否解决了冲突、工具链是否已允许旧性能补丁、是否出现更好的上游替代方案。
   - 新提交可能使旧 `SKIP` 结论失效；发现这种情况时更新台账并说明原因。
   - 普通功能开发只做检查与提醒，**不得因为 Preflight 就强制展开一次大型上游同步**；真正的集成仍须独立分支、完整依赖链与测试。

### 断点恢复上一次未完成的任务

1. 检查 `state.json` 中的 `active_task` 与 `pending_ranges`，并用 `./tools/upstream/check.sh` 核对 `ledger.jsonl` 实际覆盖的 `(source, sha)` 集合。
2. 优先完成已存在但 `status != "completed"` 的断点区间或 `NEEDS_REVIEW` 记录，**禁止对已记录在 `ledger.jsonl` 中的提交从头重复审查**。
3. 若上一次 Worker 留下了未合入的 `sync/*` 分支，先用 `git status` 和 `git log main..sync/*` 核验其构建与台账一致性再继续。

---

## 12. 常见错误与禁止事项

严禁以下行为：
- 不经审查直接 `git merge ghostty/main` 或批量盲目 `git cherry-pick`。
- 仅凭 commit subject（标题）判断无关并写入 `SKIP`。
- 把“已审查到某 SHA”写成“已同步/已集成到某 SHA”。
- 遗漏 Merge Commit 与其分支内普通 Commit 的对应关系（或漏掉 evil merge 改动）。
- 在不运行 `./tools/upstream/check.sh` 和真实 git 命令的情况下估算提交数量或编写假结果。
- 覆盖 Railty 图标、`com.vendettar.railty`、`railtyctl`、Sidegeist 功能或 Railty CI/CD。
- 自动推送正式 `v*` Tag、触发正式 Release 或修改 Homebrew Tap（除非用户明确要求）。

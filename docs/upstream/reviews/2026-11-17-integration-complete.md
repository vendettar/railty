# Railty Upstream Integration Complete (2026-11-17)

本报告是 [2026-11-17-initial-audit.md](2026-11-17-initial-audit.md) 的**后续集成报告**，记录 45 项 `INCLUDE` 上游修复从移植、验证、合入 `main` 到发布 `v0.1.3` / `v0.1.4` 的最终状态。

> **给下一位 Worker 的结论**：
> - 45 项 `INCLUDE` 已**全部**合入 `main`，`ledger.jsonl` 中 `pending = 0`。
> - **不要**按初次审查报告第 4 节重新 Cherry-pick 任何提交，否则会产生重复补丁与冲突。
> - 下一次上游同步只需从 `ghostty/main = 5ebe501a63425b13d9952e8c54682c046386e5af` 之后开始增量审查，并先运行 `./tools/upstream/check.sh`。

---

## 1. 集成结果总览

| 指标 | 数值 |
|---|---:|
| 上游审查提交（Ghostty `v1.4.0..5ebe501a63`） | 395 |
| `INCLUDE` 决策 | 45 |
| 已集成（`integrated`） | 44 |
| 已适配后集成（`adapted`） | 1 |
| 仍待移植（`pending`） | **0** |
| `DEFER` | 149 |
| `SKIP` | 201 |
| `NEEDS_REVIEW` / `ALREADY_INCLUDED` | 0 / 0 |

### 已集成提交的类别与风险

| 类别 | 数量 | 风险 |
|---|---:|---|
| `Critical Bug` | 30 | `low` 40 / `medium` 5（合计） |
| `macOS Bug` | 6 | 同上 |
| `Security` | 3 | 同上 |
| `Tests` | 3 | 同上 |
| `Build / Toolchain` | 2 | 同上 |
| `Performance` | 1 | 同上 |

全部 45 条的 `integration` 为 `integrated`/`adapted`，`validation` 均为 `macos-build-passed`，且每条 `railty_commit` 都可在 `main` 历史中找到（`tools/upstream/check.sh` 已自动校验）。

### 需要特别记录的 3 个适配点

1. **`9899c0707767d93ad26e587c896a9a2761273b26`（Darwin memset quirk）**：上游同时修改 `.github/workflows/test.yml`，该文件属于已禁用的上游工作流，移植时剥离，仅保留 `build.zig` 与 `src/build/libsystem_override.sh` 修复，台账记为 `adapted`。
2. **`f4830b2f18785aba11af9d92239f35c6e211abca`（PageList 扩容期间完整性检查）**：`src/terminal/Terminal.zig` 末尾与已 `DEFER` 的 `ce920296c` 测试上下文冲突；仅保留该提交自身的两个 resize 回归测试，移除不属于该提交的 `eraseDisplay` 测试。
3. **`fd29936f09`（Surface `@MainActor` 隔离）**：已核查 Sidegeist、App Intents、AppleScript、IPC 与 `SidebarTabManager` 调用方，全部在 `@MainActor` 上下文，无需额外 `MainActor.assumeIsolated`。

---

## 2. Git 历史与合并方式

- 同步工作全部在 `sync/ghostty-fixes-2026-11` 完成，使用 `git cherry-pick -x` 保留来源追踪。
- 合入 `main` 时采用**线性 rebase**（无 merge commit），历史保持单线。
- 同步分支在合入并推送后已删除（本地与远端）。

`main` 上的关键提交：

| Commit | 内容 |
|---|---|
| `a4bacdff5` | 台账更新：45 条 `INCLUDE` 标记 `macos-build-passed`；`state.json` 记录验证结果 |
| `21ceebc39` | macOS 应用菜单与退出确认改名（`Ghostty` → `Railty`） |
| `be61dbaeb` | 用户可见文案品牌清理（窗口标题、弹窗、Shortcuts/AppleScript/IPC、Dock Tile 插件） |

## 3. 发布结果

| 版本 | Tag 指向 | 发布工作流 | 结果 |
|---|---|---|---|
| `v0.1.3` | `a4bacdff5` | [run 44050630021](https://github.com/vendettar/railty/actions/runs/44050630021) | 成功：Release 已发布，Homebrew Cask 更新为 `0.1.3`（sha256 `102d95ab…`） |
| `v0.1.4` | `be61dbaeb` | [run 44053591222](https://github.com/vendettar/railty/actions/runs/44053591222) | 成功：Release 已发布，Homebrew Cask 更新为 `0.1.4`（sha256 `8a8fcfe9…`） |

- `v0.1.3` 包含全部 45 项上游修复。
- `v0.1.4` 仅包含品牌文案清理，不改变终端核心行为。
- 正式发布均通过 `release-railty.yml` 在 `xcode-27` 自托管 Runner 完成 `GhosttyKit.xcframework` + `Railty.app` 编译、打包、可选签名/公证，并自动更新 `vendettar/homebrew-railty`。

## 4. 验证矩阵

| 验证项 | 范围 | 结果 |
|---|---|---|
| `zig build test-lib-vt` | libghostty-vt 全量测试 | 通过 |
| `zig test src/os/path.zig` | 路径空终止符修复 | 4/4 通过 |
| `zig fmt --check build.zig src/` | 格式 | 通过 |
| `swiftc -parse` | 所有修改过的 `.swift` | 通过 |
| `xmllint --noout` | 所有修改过的 `.xib` | 通过 |
| `git diff --check` | 空白错误 | 通过 |
| macOS Release 构建 | `xcode-27`，run 44042567498 | 成功（同步分支代码全量） |
| 发布构建 | `v0.1.3` / `v0.1.4` tag 推送 | 两次均成功（run 44050630021 / 44053591222） |

未执行：GUI 运行时手测（Tab 拖拽、Sidebar、Git Panel 等）。发布构建成功不等于运行时行为验证，后续如改动涉及 UI/Window/Input，仍需按 [README.md](../README.md) 第 9 节补做。

## 5. 台账与状态文件的一致性

- [state.json](../state.json) 现记录：`railty.head_sha = be61dbaeb…`、`latest_release_tag = v0.1.4`、`last_validated_commit = be61dbaeb…`、`active_task.status = completed`、`sync_branch = null`。
- [tools/upstream/check.sh](../../../tools/upstream/check.sh) 新增 **State Consistency** 检查，运行时会对以下漂移直接告警：
  1. `railty.head_sha` 落后于真实 `HEAD` 且中间存在代码改动（仅 `docs/`、`tools/upstream/` 与 `AGENTS.md` 的协议/文档漂移会作为提示输出，不算告警）；
  2. `latest_release_tag` 落后于 `origin` 上最新的 `vX.Y.Z` Tag；
  3. 最新 Release Tag 不是 `HEAD` 的祖先；
  4. 台账中 `integrated`/`adapted` 记录的 `railty_commit` 缺失或不在 `HEAD` 历史中。
- 说明：`railty.head_sha` 无法指向"包含自身的提交"，因此提交本报告后会出现一次 docs-only 漂移提示，这是预期行为。

## 6. 模板化 `DEFER` 记录的抽样复核（2026-11-17）

初审中 75 条 `DEFER` 共用同一条 `libghostty-vt 1.0 / ABI / 依赖` 理由。本次复核方法与结果：

1. 用 `git show --name-only` 读取全部 75 个提交的真实改动路径；
2. 按路径归类：`include/`、`src/terminal/c/`、`src/lib*`、`example/`、`dist/`、`pkg/`、`nix/`、`build.zig*`、`test/abi/`、`PACKAGING*`；
3. 对触及 `src/terminal/PageList.zig`、`src/terminal/snapshot/*`、`src/terminal/lib.zig` 等共享核心的 35 条重点核对 diff。

结论：

- **73/75** 确认为 libghostty-vt 1.0 的 C ABI、Doxygen、示例、CMake/pkg-config、依赖清单或 ABI 测试基础设施，对 macOS 应用无直接运行时收益，`DEFER` 成立。
- **2/75** 理由模板与实际 diff 不符，已在台账中修正（决策维持 `DEFER`）：
  - `9b848b0f5c` — `libghostty: restored snapshot keeps final page capacity max size`（#15192）：实际是共享终端核心的快照恢复页容量分配优化，改动 `PageList.fillPooled` 与 `snapshot/{page,screen,snapshot}.zig`，与 C ABI 无关。类别已改为 `Performance`、`risk: medium`，列为**下一批候选**。
  - `ef1649c853` — `ci: shard the unit tests, run one test shard per core`（#15169）：属于测试分片 runner 与 `build.zig`/CI 改动；其中 `PageList` 的 `pauseIntegrityChecks` 仅在 `slow_runtime_safety`（debug/test）下生效。理由已改为准确的测试构建描述。
- 其余 `DEFER` 组（PageList 快路径 28 条、`terminal-misc-refactor` 12 条、tmux 8 条等）不在本次模板化范围内，维持原审查结论。

## 7. 下一步

1. 用 `./tools/upstream/check.sh` 从 `5ebe501a63` 之后做增量审查；发现 `Security` / `Critical Bug` 时按协议优先评估。
2. 评估 `9b848b0f5c`（快照恢复页容量）是否纳入下一批；需要额外验证会话恢复路径。
3. Zig `0.17.1` 升级（`1d84459682`）仍被 `DEFER`，升级 CI/CD 工具链前不要引入 0.17.1-only 语法。
4. 若继续处理 `libghostty-vt-and-deps` 波次，建议等待 Sidegeist 大版本整合，避免与 C ABI 重构反复冲突。

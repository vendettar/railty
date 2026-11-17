# Railty Deferred Review & High-Value Candidate Analysis (2026-11-17)

> **历史记录（重写前）**：本报告基线 `ab61a1099` 与当时的分支 SHA 已不在当前 `main` 历史中，DEFER 数量也已从 149 降为 148。请勿把本报告当作当前操作起点；当前 SHA 与队列状态见 [2026-11-17-v1.2-lite.md](2026-11-17-v1.2-lite.md#当前-sha强推后) 与 `state.json`。

本报告是 **Upstream Sync v1.1** 的审查与实验记录，基线为 `main = ab61a1099`、发布版 `v0.1.4`。它不推翻既有 395 条台账，而是给 149 条 `DEFER` 建立可执行的复审队列，并对高价值候选做适用性评估。

---

## 1. 前置核实（真实命令结果，非历史假设）

| 检查项 | 实测结果 |
|---|---|
| Railty `HEAD` | `ab61a1099f96668492a4341570e43e8a4e2e7279` |
| Ghostty `main` | `5ebe501a63425b13d9952e8c54682c046386e5af`（与上次审查相同，新增 0） |
| Sidegeist `main` | `5904a523477542b114939d93594f82348f27b3b5`（新增 0） |
| 未审查 Ghostty 提交 | 0 |
| 未审查 Sidegeist 提交 | 0 |
| `INCLUDE` 待集成 | 0（45 条全部 integrated/adapted） |
| 45 条 `railty_commit` 祖先校验 | 全部通过 |
| 最新 Release | `v0.1.4`（`be61dbaeb`，Homebrew Cask 已更新） |
| CI/CD Zig | `0.17.0`（本机 `zig 0.17.1`，仅用于本地测试） |
| 本机 Xcode | 仅 Command Line Tools，无 `metal` / `xcodebuild` |
| 新安全/严重修复 | 无新增（Ghostty `main` 未前进） |

`./tools/upstream/check.sh` 输出 `All state consistency checks passed`，`DEFER Re-assessment Gates: 0 satisfied`。

---

## 2. DEFER 复审队列（新机制）

新增 [defer-queue.json](../defer-queue.json)，为 149 条 `DEFER` 每条保留独立 SHA，并补充：

| 字段 | 说明 |
|---|---|
| `group` | 功能组（如 `terminal-refcounted-set`） |
| `priority` | `P1` / `P2` / `P3` |
| `revisit_trigger` | 重新评估的触发条件（枚举） |
| `validation_plan` | 该组需要的验证步骤 |
| `review_status` | `awaiting_validation` / `awaiting_dependencies` / `awaiting_toolchain` / `awaiting_upstream` / `no_runtime_path` / `candidate_next_batch` |
| `last_reassessed_at` | 最近复核日期 |
| `notes` | 结论与注意事项 |

当前分布：

| 维度 | 分布 |
|---|---|
| 优先级 | `P1: 14`，`P2: 32`，`P3: 103` |
| 状态 | `awaiting_upstream 75`，`awaiting_dependencies 45`，`awaiting_validation 23`，`awaiting_toolchain 4`，`no_runtime_path 1`，`candidate_next_batch 1` |
| 最大功能组 | `libghostty-vt-1.0-abi 75`、`terminal-misc-refactor 12`、`tmux-control-mode 8`、`terminal-refcounted-set 7`、`terminal-print-fastpath 5`、`terminal-style-packing 6`、`terminal-blank-row 5`、`terminal-pagelist-capacity 5`、`terminal-rowbuilder-render 5` |

触发条件语义（由 [defer_queue.py](../../../tools/upstream/defer_queue.py) 实现并被 `check.sh` 调用）：

- `on_toolchain_upgrade`：`state.railty.pinned_zig_version >= 0.17.1`
- `on_sidegeist_upgrade`：Sidegeist 前进超过 `last_integrated_sha`
- `on_upstream_dependency_update`：Ghostty 前进超过 `last_reviewed_sha`
- `on_macos_snapshot_consumer`：`macos/` 或 `src/apprt` 出现 `ghostty_snapshot` 调用
- `on_next_sync_review`：任一上游前进
- `manual_dedicated_port` / `on_user_request`：只能人工触发

`check.sh` 现在还输出：未审查的上游提交数、INCLUDE 待集成数、P1 数量、按组汇总、已满足的复审触发条件，以及“DEFER 提交已出现在 sidegeist/main”检测。新增 27 个单元测试，覆盖空队列、重复 SHA、非法状态、触发条件与历史重写等场景：

```bash
python3 -m unittest tools/upstream/test_defer_queue.py   # 27 tests OK
```

---

## 3. PageList / Terminal 性能组依赖分析

现状核实：当前 `src/terminal/PageList.zig` **没有** `carried_capacity`；`src/terminal/Style.zig` 仍是普通 `struct`（未压缩为 `u128`）；`Terminal.zig` 已有 `printSliceFast`/`printSliceStoreRun`，说明基线已含更早期的快路径，但未含本系列。

| 组 | Commits（短 SHA） | 依赖 / 后续修复 | 主要价值 | 风险 | 结论 |
|---|---|---|---|---|---|
| A. PageList 容量 | `a3b5946a59` (base, +555/−48), `0d4418ac20` (+321/−22), `9113da0298`, `f0d8cb7762`, `d20d208c51` | 必须整链：base 后紧接 edge-case 修复；`d20d` 调整 hyperlink map 容量 | 减少输出密集场景的页面重分配 | 高（PageList/page 大改） | 保持 `DEFER`，需专项分支 + 基准 |
| B. Print Fast Path | `68750a1be2` (+768), `faa346b068`, `4c92f80954`, `22b8451441`, `c12d42eaf8` | `faa3`/`22b8`/`4c92` 是同一快路径的后续正确性修复 | ASCII/宽字符混合输出吞吐 | 高（必须连同修复） | 保持 `DEFER` |
| C. Style 压缩 | `41557e2ccf` (u128), `73a2a1d06e`, `72bc97a9ed`, `de16f08dcf`, `fad1133619`, `54d162da5b` | 需一起改 Screen/Terminal/C style API | SGR 密集输出与内存 | 高（波及 C API） | 保持 `DEFER` |
| D. Blank Row | `881fc68902`, `2178e635df`, `8484146c74`, `25de649dde`, `a227276b77` | `a227` 是快照测试修正，必须带上 | 清屏/空白行/滚动 | 中高 | 保持 `DEFER` |
| E. RowBuilder / Render | `020a0a0998`, `d1ce0c4657`, `96d379822f`, `15a4432340` | `d1ce` 修复 `020a` 引入的回归 | 样式段查找与 endUpdate | 中 | 保持 `DEFER`；`96d3` 可单测 |
| F. OSC 133 Prompt | `ce920296c8` | 含 synthetic Erase corpus 与 snapshot 测试更新；上次仅因测试冲突暂缓 | `ED2` 清屏扫描 | 中 | 保持 `DEFER`，可独立实验 |
| G. Carriage Return Pin | `8434d0900e` | 独立 2 行 | 滚动流（上游 1.02–1.06x） | 低 | 唯一本轮实验项 |
| H. PageList Prune 内存 | `d0addb9cdf` | 独立 Critical Bug 修复 | grow-prune 丢弃页面内存 | 中 | **P1**，建议优先实验 |

共同结论：A–F 都是“上游后续修复依赖链”，禁止只摘第一条性能提交；本机无 `ghostty-bench`（Metal 阻塞），无法给出可信吞吐数据，因此本轮不合并任何性能补丁。

---

## 4. RefCountedSet 整链评估

7 条提交：`d03983f02c`（add 复用 dead ID，替代 NeedsRehash）、`636c1d7805`（只回收可置换的 dead item）、`738d8f7f5b`（成员检查替代 sentinel）、`38f4a710e3`（releaseMultiple 断言）、`31a52992f1`（回收被跳过的 dead ID 插入）、`aef8b7b38d`（收紧测试）、`5d3f653329`（文档）。

现状核实：`src/terminal/ref_counted_set.zig`（890 行）与 Ghostty `v1.4.0` 基线完全一致；`add` 在无空位时仍返回 `NeedsRehash`，调用方通过克隆整页来压缩 ID。该系列把 dead-ID 复用引入 `add`。

上游数据（提交信息内，非本机实测）：`links.vt` 无 scrollback 时 1.35x，`styled-heavy` 1.17x；`rg --hyperlink-format`、`chafa`、`eza --hyperlink` 等真实负载减少 3.6%–14.2% 指令数。对 Railty 的潜在价值主要在 hyperlink/样式密集输出，普通 ASCII 基本无变化。

结论：保持 `DEFER`（`P2 / awaiting_dependencies`）；必须按拓扑整体移植，单独摘 `d039` 会破坏 `add`/`insert`/`deleteItem` 的假设。建议作为下一批首个实验组。

---

## 5. 新功能与高冲突候选

| 候选 | 规模 | 判断 |
|---|---|---|
| 窗口主题 `6ba2c2b270` + `dce5a9464a` | `include/ghostty.h`、`AppDelegate.swift`、`TerminalWindow.swift`、Config | 与 Sidegeist 窗口/配置高度重叠，且依赖前面的 action 机制；保持 `P3 / awaiting_validation`，仅在明确需求时专项适配 |
| tmux control mode（8 条） | Terminal/Termio 协议链 | 功能链不完整、与 Sidegeist 会话/标签行为重叠；保持 `P3` |
| DECIC/DECDC/DECBI/DECFI `44a4911e91` | Terminal +297、stream +138 | 新 VT420 协议，无用户需求；保持 `P3 / on_user_request` |
| iTerm2 配色（3 条） | 仅 `build.zig.zon` / `deps/packages.*` 数据更新 | 无代码行为变化；可在下次同步窗口单独评估，本轮不动 |

---

## 6. 实验：carriage-return pin 快路径

- 分支：`sync/ghostty-pagelist-cr-pin`
- 提交：`f6cd5e4fd`（`git cherry-pick -x 8434d0900e`，2 行改动）
- 改动：`Screen.cursorHorizontalAbsolute` 用列差移动缓存 cell 指针，避免 `rowAndCell()` 的 pin 查找。
- 本地测试：`zig fmt --check src/terminal/Screen.zig` 通过；`zig build test-lib-vt -Dtest-filter=Screen` 通过；完整 `zig build test-lib-vt` 通过（exit 0）。
- macOS 构建：`xcode-27` `release-railty.yml` run `44062908329`（workflow_dispatch，`create_draft_release=false`，不产生 Release / Cask 变更）。
- 性能：`NOT_TESTED`（本机无法生成 `ghostty-bench`，Metal 缺失）；上游报告 1.02–1.06x 不能作为本机结论。
- 结论：分支保留、**不合并 main**；等有 Xcode 的环境补齐 benchmark 后再决定。

完整 lib-vt 结果：**通过**（`FULL_TEST_EXIT=0`）
CI 结果：**成功**（run `44062908329`，`Build Railty.app (Apple Silicon)` 完成；manual build 不产生 Release/Cask 变更）

---

## 7. 最终问题回答

1. **149 个 DEFER 中，多少继续暂缓？** 全部 149 本轮继续暂缓；其中 14 条 `P1` 需要专门排期（12 条 Critical Bug、nullability、snapshot/prune 相关）。
2. **多少可以安全纳入？** 本轮 0 条。没有任何候选同时满足“可达路径 + 正确性测试 + 本机性能数据”。
3. **多少实际已经不需要？** 0 条可直接改 `SKIP`；75 条 libghostty-vt ABI 只是对当前 macOS 应用无收益，仍需保留给 Sidegeist/嵌入场景。
4. **哪些需要等待 Zig 升级？** 4 条 `toolchain-zig-upgrade`；PageList/RefCountedSet 各链本身不依赖 0.17.1。
5. **哪些需要等待 Sidegeist？** 75 条 `libghostty-vt-1.0-abi`，以及窗口主题、tmux 等高冲突功能组。
6. **哪些性能优化可以独立引入？** 已验证可独立编译的只有 `8434d0900e`（本轮实验）；`96d379822f`、`ce920296c8` 也相对独立，但未实验。
7. **哪些功能存在 Sidegeist 冲突？** 窗口主题（2）、tmux（8）、nullability 的 `TerminalWindow.swift` 部分、`terminal-misc-refactor` 中共用文件。
8. **哪些候选已通过 macOS ARM64 构建？** 本轮实验分支 `f6cd5e4fd` 已通过 run `44062908329`；`v0.1.4` 正式发布构建全部通过。
9. **哪些完成运行时验证？** 0；本机无 GUI/Xcode，全部标记 `NOT_TESTED`。
10. **哪些取得实测性能收益？** 本机 0 条；上游提交内的 benchmark 数据仅作参考，未复现。
11. **下一位 Worker 继续什么？** 先做 `terminal-refcounted-set` 整链与 `terminal-pagelist-prune-memory`（P1），再评估 PageList 容量链；每一步都按 [benchmarks/2026-11-17-baseline.md](../benchmarks/2026-11-17-baseline.md) 的基准协议取数。

## 8. 相关报告

- [Snapshot 适用性评估](2026-11-17-snapshot-assessment.md)
- [macOS C API 可空性评估](2026-11-17-macos-nullability-assessment.md)
- [性能基线（NOT_TESTED 记录）](../benchmarks/2026-11-17-baseline.md)
- [集成完成报告](2026-11-17-integration-complete.md)

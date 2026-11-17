# Android 技术面试助手：测试执行结果（2026-11-17）

对应用例：[android-interview-full-test-cases-2026-11-17.md](android-interview-full-test-cases-2026-11-17.md)。基线 `e9614a5` + 本次工作区修复（未提交）。Mac M4 Pro，dev 版 `com.wquguru.cicada.dev`，DeepSeek Flash 卡片，英文教练 + 讲题卡片。

## 执行范围

| 方式 | 本次 | 说明 |
|---|---|---|
| U 单元 | 已执行 | `scripts/test.sh`：655 个测试全部通过（修复前 649，新增 6 个回归测试） |
| I 注入 | 已执行 | `tools/interview-full-cases.json` 共 23 个场景，覆盖 NF-01～18 主流程、CH/ME/VS/RT 中可注入的用例；视频关键帧取自 03:00/15:00/18:10–18:50/21:00/33:00/46:00 |
| V 视频静音回放 | 未执行 | 需要真实屏幕共享捕获 |
| R 真人双路音频 | 未执行 | 需要两人复演或分角色录音；男面试官/女候选人的角色分离（RT-01）、跟读、焦点、共享可见性（UI-01～05）都未验证 |

未注入的用例：CH-02、CH-08、ME-01（30 轮/60–90 分钟）、ME-04、ME-05、ME-07、VS-03、VS-05、VS-06、RT-01～03、RT-05～08、UI-*、QT-03、QT-04 仍为 NOT_RUN。QT-01/QT-02 由已有单元测试覆盖（CoachCardTests、CoachCaseTests），本次没有新增。

判卷：结构检查 + DeepSeek 判卷。判卷模型看不到图片，凡涉及白板内容的 FAIL 都经人工看帧复核。

## 修复的缺陷

| 缺陷 | 用例 | 级别 | 原因 | 修复 | 复跑 |
|---|---|---|---|---|---|
| D1 新题被并入相似旧题，两题约束混在一起 | ME-08 | P0 | 识别新题的正则不认 "new problem"；`withoutSubtaskProblems` 因两题都含 "cache" 把新题判成子任务 | `newQuestionPattern` 加入 new/different problem/topic、next topic，两处共用一个正则 | 修前 0/1，修后 3/3 |
| D2 指代不明的“再加一个”被自行决定 | CH-06 | P0 | 只有提示词约束，模型照样给 TYPE | `unresolvedReference` 检测后带说明重试一次，只要澄清问题；该卡强制不带 TYPE | 修前 FAIL，修后 2/2 |
| D3 约束撤销后反向编造新约束（“不用本地数据库”） | ME-02 | P0 | 模型把“不再需要离线”写成相反的约束 | 提示词：撤销只记 dropConstraint，不记反义约束 | 修后 2/2 |
| D4 讲解白板或参考代码时仍给 TYPE 代码 | NF-05、ME-10 | P0 | 只要求讲解时，原逻辑只去掉 draw 类编辑 | `asksToExplain` 命中时去掉所有编辑 | 修后均通过 |
| D5 "Replace RxJava with Flow" 没有记成已采用方案 | CH-01 | P0 | `decidedApproach` 不识别 replace…with… | 新增该句式，并排除 don't/not replace | 修后通过 |
| D6 “我还没讲数据流”被当成已讲内容去重，卡片跳到无关边界情况 | ME-03 | P0 | 这句话进入“已说过”列表和去重请求 | `saysNotCovered` 过滤这类话，提示词同步说明 | 修前 0/3，第一步修复后 2/3，最终 3/3 |
| D7 白板上有 requestId 就断言服务端幂等；断言 cursor 分页绝不重复 | NF-13、NF-06 | P1 | 没有规则约束这类无依据的保证 | 提示词：服务端行为说成待确认的契约，不说“绝不” | NF-06 已通过；NF-13 修后 3/4 通过，仍有随机失败 |
| D8 结束会议后，新会议里候选人第一句自述不触发核对 | RT-08 相关 | P1 | `reset()` 没有清 `lastCommitCursor`/时钟等会议内状态 | `reset()` 一并清零 | 单元测试修前 FAIL、修后 PASS |
| D9 重试流结束后可能把旧卡应用到已重置的会议 | RT-08 相关 | P1 | `apply` 前缺少 token 检查 | 加 `guard !Task.isCancelled, token == tok` | 代码审查，无法稳定复现 |

测试工具修复（`tools/mock-interviewer.py`，对应用例文档 §3 列出的评测缺口）：
- 每条面试官台词后检查请求数确实增加、且不 busy/failed，否则判 FAIL；
- 读不到状态判 FAIL，没有任何检查项的场景不再算 PASS；
- 每轮结果归档到 `docs/evaluations/runs/<时间>/`，不再覆盖。

## 各轮结果

| 轮次 | 代码 | 结果 | 归档 |
|---|---|---|---|
| 1 | 基线 | 16/23 | runs/20261117-230519 |
| 2 | D1–D3、D7、D8、D9 | 17/23 | runs/20261117-231825 |
| 3 | + D4、D5 | 17/23（CH-01/NF-05/ME-10 转为通过） | runs/20261117-233028 |
| 定向 | + D6 | ME-03 3/3；CH-03 3/3；CH-04 2/3 | runs/20261117-2333xx–2344xx |

## 仍未通过或未定

| 用例 | 情况 | 判断 |
|---|---|---|
| VS-04 | 三轮都被判卷模型判 FAIL | **判卷误判**：人工看 46:00 帧，ObserveFeedItems、GetDetailItems、ObserveCommentsForPost、PostRepository 等方框和箭头都在白板上 |
| NF-05（第 4 轮） | 判卷说 reachedEnd 不在白板上 | **判卷误判**：15:00/18:20 帧上有 `PaginationMetadata(after, before, cursor, reachedEnd, limit…)` |
| NF-18 | 反问 “what would make you feel you hired the right engineer” 被判成提及评分 | 判卷过严，不是 HIRE 污染 |
| NF-15 | 5/5 轮：退出登录时清空待同步队列 | **判据有歧义**：用例禁止的是“淘汰缓存时”丢弃待发送内容；退出登录清空待发送内容出于账号隔离，可能是对的。需要产品决定退出时待发送评论怎么处理 |
| NF-14、NF-16、ME-12 | 多轮中时过时不过（漏讲 UI 状态、页面与媒体分开处理、touch 分发的方法名） | P1 内容深度，模型随机波动，未修 |
| NF-13 | 修后 1/4 仍断言服务端去重 | P1，提示词约束只能降低概率；如需保证，要加确定性检查 |
| CH-04 | 2/3：说完“keep Room”后，卡片自加一层内存缓存并写进 adopted | P1：没有切到纯内存，但 adopted 文本超出了面试官原话 |
| CH-03 | 第 3 轮判卷认为“simplest option is…”像做了决定 | 状态 adopted 正确；措辞问题，1/4 |

## 结论

- 本轮修复的 6 个 P0 缺陷（D1–D6）都有单元测试或注入复跑证明。
- 注入方式不能代替 R：语音识别、真实角色分离、屏幕压缩、焦点和共享可见性都没有测，不能宣称端到端验收通过。
- 模型类场景每个只跑了 1–4 轮，样本小；没有做性能统计（P50/P95）。

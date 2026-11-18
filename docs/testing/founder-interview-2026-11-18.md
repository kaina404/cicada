# 创始人综合面试全流程测试（2026-11-18）

对象：讲题卡片 + 画图（`b2e981f`），英文教练模式，DeepSeek Flash 出卡。仅 Mac：M4 Pro，dev 版 `com.wquguru.cicada.dev`。

## 剧本

[tools/interview-founder.json](../../tools/interview-founder.json)：面试官是 ActAI 创始人，一场会议不重置。

| 段 | 题 |
|---|---|
| 开场 | 自我介绍；为什么离开稳定公司来创业公司 |
| 八股 | SupervisorJob；StateFlow 还是 SharedFlow 做一次性事件；配置变更和进程被杀；Compose 重组问题 |
| 画图 | 画发消息到流式回复上屏的流程图；在图上加断网处理；画登录 + token 过期刷新的时序图；refresh token 存哪（不该画图） |
| 创始人问题 | 15 人团队六周发 Android MVP；反问 |

```bash
scripts/build.sh && open build/Cicada.app
PACE=1 SCENARIOS=interview-founder.json python3 -I -u tools/mock-interviewer.py
```

候选人照卡片念（`me_card`），把卡片 TYPE 写到白板（`ocr_card`）；新增 `render` 步骤，在每张画图卡后存面板截图。

## 结果

两轮：[runs/20261118-132623](../evaluations/runs/20261118-132623/interview-founder.json)（18 分钟）、[runs/20261118-134904](../evaluations/runs/20261118-134904/interview-founder.json)（9.5 分钟）。

| 项 | 第 1 轮 | 第 2 轮 |
|---|---|---|
| 结构检查（type / type_contains / problems_min） | 全过 | 全过 |
| 面试官每句话都出了新卡片 | 8/12（4 次超过脚本 40 s 等待） | 12/12 |
| 判卷 | 11/12 | 11/12 |
| 唯一 FAIL | 反问：卡片先邀请看 Cabinet AI 一分钟演示 | 同左 |
| 卡片流式完成 | 22–42 s（见下） | 1–4 s（73 次） |

- **画图**：两轮都画出 `flowchart TD`（7 个框以内）和 `sequenceDiagram`（第 2 轮带 User / App / Auth server / API）。断网追问只补新框，复用原 id（第 1 轮 `add`，第 2 轮 `draw` 只含新边）。refresh token 存储题没有画图。三张图单独渲染核对过，结构正确、可照着画。
- **反问 FAIL 不是缺陷**：用户确认过的收尾话术（`knowledge/04_talk_tracks.md`，2026-11-16）要求先邀请看演示，再问前三个月目标。判据已按话术改。
- **面板截图里图是空框**：`assistantRender` 固定 420×680、不滚动，图被压成 0 高；真实窗口在 ScrollView 里。已修：截图改为按内容自然高度（见下方复测）。

## 发现并修复：记录窗口搜索拖慢卡片

第 1 轮每张卡要 22–42 s 才出完（首字仍是 1.4 s），所以驱动脚本记了 4 次“answered”超时。看门狗记录了 5–10 s 的主线程卡顿，采样落在 `MainWindowView.filtered`：会议记录窗口开着，搜索框里有字，每来一句话就把 823 场会议的每一行都用 `localizedCaseInsensitiveContains` 搜一遍。卡片的流在主线程上读，所以跟着被拖慢。第 2 轮重启后窗口没开，就没有这个问题。

修复：`RecordSearch`（`RecordList.swift`）按会议缓存搜索结果；只有搜索词变了，或某场会议的标题、行数、最后一行变了，才重新搜这一场。实际上只有正在进行的会议会重新搜。800 场会议的合成数据下，每次界面更新从 253 ms 降到约 1 ms（debug 构建）。测试：`RecordSearchTests`。

未验证：没有在真实窗口里输入搜索词再跑一遍（这次没拿到操作 dev 版窗口的权限），结论来自卡顿采样、基准和单元测试。

## 其他观察

- 新增日志 `coach: card stream done s=… raw_chars=…`，以后区分是模型慢还是主线程慢。

## 复测修复（23:35）

- **问候语**：“Good morning”来自用户预制自我介绍（`04_talk_tracks.md`），模型不知道时间。现在出卡和完整回答的请求末尾都带当地时间和该用的问候语（`CoachPrompt.localTime`，测试 `CoachLocalTimeTests`）。23:35 复测开场为“Good evening”，判卷通过。
- **截图里的图**：`assistantRender` 去掉固定高度，按内容撑开；复测截图 [F1v-flowchart.png](../evaluations/runs/20261118-233504/F1v-flowchart.png) 能看到完整 8 框流程图。截图里底部按钮显示成黄色禁止图标，是 `ImageRenderer` 画不了原生按钮，不影响真实窗口。
- 复测里流程图判卷 FAIL：这次的图没有“本地保存消息”这一框（前两轮都有）。属于模型这次的取舍，没有改提示词；记录在 [runs/20261118-233504](../evaluations/runs/20261118-233504/founder-verify.json)。

## 复测修复（11-19 00:05–00:27）

- **测试脚本**：截图移到画图卡出来之后、候选人照着画之前（原来画完才截，卡片已换成下一张）。发问前一刻才记卡片数：之前等“面试官说话”的 8 秒里，系统声音里冒出的 “how” 先触发了一张卡，被当成了这道题的回答。
- **登录时序图记成了流程图那道题**：四轮（含前两轮完整场景）都是这样，时序图卡片的标题还是 “Draw a flowchart…”。原因是提示词规定“同一个产品的问题都留在原设计题里”。修复：规则里补一句“换一张别的流程的图是新题”；`newQuestionPattern` 认出 “a different one: draw…” / “another diagram”，模型漏了 newProblem 时由 app 补上（测试 `aDifferentDiagramOpensANewProblem`）。只改提示词那次还漏了（新题到 22 s 后的下一张卡才记上），所以加了代码兜底。
- 画图段连跑两轮全过：[runs/20261119-002414](../evaluations/runs/20261119-002414/)、[runs/20261119-002650](../evaluations/runs/20261119-002650/)，题目数 2，时序图卡片标题是登录。

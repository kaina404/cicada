# 讲题卡片完整流程：Facebook News Feed 移动端系统设计（2026-11-17）

题目来自用户提供的 Excalidraw 白板（`Untitled-2026-11-17-1917.excalidraw.svg`，与 `AndroidEngineerMockInterview.mp4` 同一块白板）。剧本：`tools/walkthrough-newsfeed.json`；原始结果：[walkthrough-newsfeed-2026-11-17.json](walkthrough-newsfeed-2026-11-17.json)（最后一轮）。

## 方法

- 开发版，`SCENARIOS=walkthrough-newsfeed.json python3 -I tools/mock-interviewer.py`：14 轮面试官原话（`themSaid`），一句候选人原话（`meSaid`），在对应阶段注入录像里的真实白板帧（`coachBoard`：需求、API、高层架构、分层架构、详细数据流）。
- 面试官台词参照那场真实面试及其评分反馈：需求澄清 → 离线约束 → API → 分页追问 → 高层架构 → 客户端分层 → 数据流 → 试探性提问 → 离线点赞 → 失败重试 → 简历插问 → 回到预取 → 反问。
- 每轮由 DeepSeek 判卷。**没有**真实声音、真实共享屏幕和真人跟读。

## 结果

| 轮次 | 通过 | 说明 |
|---|---|---|
| 第 1 轮 | 11/14 | #2 复述需求；#6、#14 是判卷标准写错（白板上确有 Blob Storage；反问目标公司 A1 语音产品是相关问题） |
| 中间几轮 | 12–13/14 | 暴露：抄上一张卡、卡片过长、把卡片自己的要点记成候选人讲过 |
| 修复后 | **14/14、14/14** | 连续两轮全过 |
| 最后一轮（最终代码） | 13/14 | #11 讲了重试上限和失败回滚，这一张没提指数退避（单张内容遗漏） |

首字延迟（最后一轮，14 张）：0.56–1.17 秒，中位数约 0.79 秒。

## 最后一轮逐卡

| # | 面试官 | 首字 ms | 结果 | 卡片开头 |
|---|---|---|---|---|
| 1 | Let's do a mobile system design question today. Design the news fee… | 1173 | 通过 | Thanks, I can see the two screens and the requirements. Before I design anything, let me confirm the scope… |
| 2 | Posts can be text, images or video… 100 million daily users | 653 | 通过 | Got it, so 100 million daily users worldwide, and posts can be text, images or video. That scale changes the d… |
| 3 | users should still see their feed … offline | 694 | 通过 | Got it, so the feed and likes must work offline too. That means the local cache is the source of truth… |
| 4 | Let's talk about the API | 819 | 通过 | The API you sketched already covers the main calls, so I'll build on it. For the feed I'd use cursor paginatio… |
| 5 | Why cursor-based pagination? | 713 | 通过 | Page numbers break when new posts arrive at the top… |
| 6 | Walk me through the high-level architecture | 1127 | 通过 | Sure. On the left, the client talks to the backend over HTTPS. Images and videos go through the CDN… |
| 7 | How would you structure the Android app? | 1065 | 通过 | I'd split it into three layers. The UI layer has the feed and detail screens, each with its own ViewModel… |
| 8 | How does a feed item get onto the screen? | 805 | 通过 | The ViewModel calls ObserveFeedItems, and the use case asks PostRepository for the feed… |
| 9 | Could we just keep everything in memory? | 1074 | 通过 | We could, but I wouldn't. Memory is lost when the app is killed… |
| 10 | A like while offline? | 789 | 通过 | I'd write the like to the local database first, so the UI updates right away. Then I'd put it in a small queue… |
| 11 | And if that request keeps failing? | 710 | 未过 | Right now the like stays in the queue and retries… (没提指数退避) |
| 12 | Built something similar before? | 558 | 通过 | Yes, at KKday I built the AI trip planner… |
| 13 | Back to the feed: prefetch the next page? | 784 | 通过 | I'd start loading the next page before the user reaches the bottom… |
| 14 | Any questions for me? | 728 | 通过 | Yes, two quick ones. Six months after I join, what would make you feel you hired the right Android engineer?… |

## 这次完整流程发现并修复的问题

1. **面试官问新问题时，模型照抄了屏幕上的旧卡片** → 新卡与当前卡几乎相同时：面试官触发的，点名问题重试一次；其他触发视为 KEEP，不重复发布。
2. **把卡片自己的要点记成候选人讲过**（引用了一句无关的候选人原话） → “讲到了”必须和所引用的原话有足够的内容重叠。
3. **一张卡讲了 12 句**（从需求一路讲到 Redis） → 每张最多 5 句，保留结尾的确认问句；流式显示也按上限。
4. **补充需求后整段复述** → 第一句作为确认保留，后面与面试官原话大面积重复的句子删除。
5. **系统设计题开头没先确认需求** → 提示词规定设计题第一张卡先简短确认范围和需求（评分反馈第一条）。
6. **“写一下 ViewModel”被记成新题** → 模型的 newProblem 只在没有题目、面试官明说新问题、或与当前题毫无关联且不是承接句时保留。
7. **“Let's switch this to Kotlin Flow” 没记成采用**（模型的 adopt 证据无效） → 由面试官原话补记；“rather not use RxJava” 这种否定不算。
8. **试探性提问仍被宣布切换** → 卡片里出现 “I'll switch / fits better” 或代码时，点明规则重试一次。
9. **复核看错了范围**：检查之后再按“下一步”，候选人刚说的话已不在“新原话”里 → 改为“当前卡片显示以来候选人说过的所有话”。

## 还剩的波动

- 单张卡片偶有内容遗漏或知识性小错（例如一轮里说“一次性后台任务用 Service”，应为 WorkManager）。
- DeepSeek 判卷本身也有噪声（一轮里理由自相矛盾）。
- 同一套剧本多轮结果在 13–14/14（完整流程）、14–16/16（标准剧本）之间浮动。

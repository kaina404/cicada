# 任务书：Assistant 改为「实时应聘者」，接入 Qwen Omni Realtime 全双工模型

> 交给实现方（另一个 AI）。开工前先读仓库根目录 `AGENTS.md` 和 `CLAUDE.md`：除本文第 2 节明确改掉的条目外，其余硬规则照旧。
> 分支：`feat/screen-notes`（工作区有大量未提交改动，**不要 reset / stash / checkout 别人的改动**）。只做 Mac。
> 写于 2026-11-07。本文中标「待实测」的事实，文档没写清楚，必须在阶段 0 用真 Key 测出来，不得凭猜测实现。

---

## 0. 一句话目标

面试时，Assistant **扮演应聘者本人**：持续听面试官说话（全双工语音输入）、看共享屏幕，流式、连续地写出「我接下来要做什么」和「具体怎么解决」的英文口语台词，用户照着念；面试官一开口插话，正在写的台词立刻停下，模型带着前面所有上下文改路线重新写。

## 1. 为什么要推翻现有方案

现有 Assistant（`Copilot.swift` 634 行 + `AnswerPlan.swift` + `Ask.swift`）的问题，用户已确认：

1. **它不知道自己在做什么**：每次请求都是无状态的一问一答（HTTP，`AskEngine.stream`），模型只看到被规则切好的一小块（提问 / 路线更新 / 术语 / 局面…），没有「我是应聘者、我正在讲第几步」的连续自我。
2. **输出碎片化**：一会儿一张卡片、一会儿一条路线更新，没有成段的连贯回答。
3. **调度全靠我们手写**：提问检测、轮次判断、打断、优先级队列、静音计时、说话人分边……规则多、易错，而且语音先转文字再给模型，转写错误会传下去。

全双工实时模型天然具备：持续收音、语义级轮次检测、被打断、会话内记忆。所以新方案**把轮次和打断交给模型服务端**，我们只做「接线 + 显示 + 一个续写循环」。

## 2. 本任务改掉的旧决定和硬规则（用户 2026-11-07 已同意）

| 旧的 | 新的 |
|---|---|
| 会中问答只用本机 Gemma（mlx-vlm），不出本机 | Assistant 改用云端 `qwen3.8-omni-flash-realtime`，面试官声音和屏幕截图会上传阿里云百炼 |
| `AGENTS.md`：Every AI call goes through `LingClient` | 增加例外：实时语音会话走新的 `RealtimeClient`（WebSocket），其余 AI 调用仍走 `LingClient`。**必须同步改 `AGENTS.md` 这一条**，并保持 `scripts/check-agents.py` 通过（文件 < 6 KB） |
| 界面文案「全程不出本机」等 | Assistant 相关处改为说明会上传到阿里云；屏幕识别、字幕等其他功能的本机说法不受影响 |
| Copilot 规则调度（提问检测、路线、术语、局面卡片） | 删除，由模型自己判断 |

**仍然有效、不得违反的**：

- Key 只存 0600 文件（`AIKey.save(key, "dashscope")` → `ai-key-dashscope`），绝不进 UserDefaults、日志、导出。日志里连 Key 前缀都不要打。
- **不让 AI 发声**：只要文字，不播放、不送虚拟麦克风（`SpeakEngine` / BlackHole 完全不碰）。
- 笔记窗口是不抢焦点、`sharingType = .none` 的面板，Assistant 的显示继续放在里面。
- UI 与引擎状态 `@MainActor`；音频回调里只做转换和入队，不阻塞 `AudioRouter` 的队列。
- 不加第三方依赖：WebSocket 用系统 `URLSessionWebSocketTask`。
- UI 文案中文为 key，改完跑 `python3 scripts/strings.py --write`，补 `Resources/{en,ja,ko}.lproj`，检查英文 UI 宽度。
- 面试场景、简历与背景：只用 `docs/actai-android-interview-tests.md`、`docs/actai-candidate-hr-summary.md`、`tools/copilot-interview-background.json`；不编造经历、薪资、离职原因。

## 3. 模型与协议（官方文档摘要，2026-11 版）

来源：<https://www.alibabacloud.com/help/en/model-studio/realtime>、<https://help.aliyun.com/zh/model-studio/realtime>。实现前请自己再读一遍完整文档，以文档和实测为准。

- 模型：`qwen3.8-omni-flash-realtime`，全双工，输入文字 / 图片 / 流式音频 / 视频，输出文字和音频。
- 地址（需工作空间专属域名）：
  - 北京：`wss://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3.8-omni-flash-realtime`
  - 新加坡：`wss://{WorkspaceId}.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/realtime?model=...`
  - 鉴权：Header `Authorization: Bearer <DashScope API Key>`；各区 Key 不通用。
- 客户端事件：`session.update`（`modalities`、`instructions`、`voice`、`input_audio_format`、`turn_detection`、`input_audio_transcription`）、`input_audio_buffer.append`（base64 PCM）、`input_audio_buffer.commit`、`input_image_buffer.append`（base64 JPEG）、`conversation.item.create`、`response.create`、`response.cancel`。
- 音频输入：16 kHz、16-bit、单声道、小端 PCM。
- 图片：JPG，建议 480p/720p，最大 1080p；**base64 后每张 < 256 KB（原图建议 < 190 KB）**；约每秒 1 帧；**第一张图之前必须先发过音频**。
- 轮次：`turn_detection` = `semantic_vad`（该模型推荐）/ `server_vad` / `null`（手动：`commit` + `response.create`）。
- 服务端事件：`session.created/updated`、`input_audio_buffer.speech_started/speech_stopped`、`conversation.item.input_audio_transcription.delta/completed`、`response.created`、`response.text.delta`（或 `response.audio_transcript.delta`）、`response.done`（含状态、用量）、`error`。

**待实测（阶段 0 必须回答）**：
1. `modalities: ["text"]` 能否只出文字？不能的话，出音频但客户端丢弃 audio delta，只用 `response.audio_transcript.delta`，并记下额外费用。
2. `speech_started` 时服务端是否自动取消进行中的回答？（不管结果，客户端都要显式发 `response.cancel`。）
3. 单个连接最长能连多久、上下文多长会被截断/报错。
4. 首字延迟：面试官说完到第一个文字 delta 的时间（p50 / p90）。
5. 让它讲系统设计这种长题时，一次 response 能写多长、会不会自己草草收尾。
6. 每小时费用（音频输入 + 图片 + 文字输出 token），从 `response.done` 的用量算。
7. `semantic_vad` 对面试官短暂停顿（思考、"um…"）会不会误判为说完。

## 4. 新架构

```
面试官声音（ListenEngine 的系统声音 tap → AudioRouter）
        │ 16 kHz mono Float → Int16 LE → base64，每 100 ms 一包
        ▼
┌───────────────────────── RealtimeClient（WebSocket）─────────────────────────┐
│ session.update: instructions=应聘者设定+简历+JD, modalities=[text],           │
│                 turn_detection=semantic_vad, input_audio_transcription=on     │
│ input_audio_buffer.append ← 持续推流                                          │
│ input_image_buffer.append ← ScreenWatch 画面变了才发，≤1 帧/秒，≤190 KB      │
└───────────────────────────────────────────────────────────────────────────────┘
        │ speech_started → 客户端 response.cancel，台词标记「被打断」
        │ response.text.delta → 流式追加
        │ response.done → CandidateLoop 判断要不要「接着讲」
        ▼
CandidateEngine（@MainActor，ObservableObject）──→ CandidateFeed（笔记窗口里的提词器）
        │ 每段完成的回答
        ▼
SessionStore：存成 speaker "ai" 的 TranscriptLine（沿用现有记录格式）
```

### 4.1 只推面试官的声音

- 线上面试时，系统声音 tap 录到的是**对方从扬声器出来的声音**，用户自己的麦克风不在里面。所以只把 `listen.router`（系统声音）推给模型，用户照着台词念时不会被模型当成新问题。
- 「会议室」模式（单一麦克风同时录到双方）**本版不支持**：Assistant 打开时若当前听的是会议室，卡片显示一行灰字「Assistant 只支持听电脑声音」，不连接。
- 「电脑和会议室」模式下，仍只推系统声音那一路；会议室麦克风（用户这边）的转写结果见 4.5（P1）。

### 4.2 会话内记忆就是「会思考」的来源

同一个 WebSocket 会话里，面试官的话（音频轮次）和模型写的台词（assistant 轮次）按时间排成一段完整的面试对话。模型自然知道：问的是什么、自己已经讲了哪几步、刚刚被打断在哪。**不要再在客户端拼接上下文、做路线状态机。**

### 4.3 输出格式（写在 instructions 里，客户端只做轻量解析）

每次回答：

```
→ <一行：我接下来要做什么 / 这道题我打算怎么讲，≤20 词>
<口语台词，1~4 句，可直接念，第一人称，英文>
<…>
[[more]]   或   [[end]]
```

- `→ ` 开头的行是「计划行」，灰色小字显示在台词上方。
- `[[more]]`：这道题还没讲完，等面试官没插话就继续下一步；`[[end]]`：讲完了，等面试官。
- 标记不显示给用户；模型没写标记时按 `[[end]]` 处理。
- 解析器要能处理流式半截输出（标记可能被拆在两个 delta 里）。

### 4.4 续写循环（唯一需要我们写的调度，做成纯逻辑可测）

`CandidateLoop`（纯 struct，不碰网络和 UI）：

- 输入事件：`responseDone(marker)`、`speechStarted`、`speechStopped`、`tick(now)`。
- 规则：
  - 上一段以 `[[more]]` 结束，且面试官不在说话，且距 `response.done` 已过 `continueDelay`（默认 1.2 s，给用户念的时间留余量由 4.6 决定），就发 `response.create`，附 `instructions` 覆盖：「Continue with the next step of your answer. Do not repeat what you already said.」
  - 连续续写上限 `maxContinues` = 8，超过就停，等面试官。
  - `speechStarted` 到来：清零续写计数；若有进行中的回答，发 `response.cancel`。
  - 被打断后不主动续写，等服务端 VAD 判定面试官说完后模型自己回答（`semantic_vad` 自动 `response.create`）。
- 默认值放 `AppSettings` 不暴露 UI，只在代码注释里写清楚为什么是这个值。

### 4.5 打断

- 收到 `input_audio_buffer.speech_started`：
  1. 客户端立即 `response.cancel`（不依赖服务端是否自动取消）。
  2. 当前段落已显示的文字保留，末尾加灰色「被打断」标记，存进记录时也带上已写出的部分。
  3. 之后到达的旧 response 的 delta（按 `response_id` 判断）一律丢弃。
- 验收：从面试官开口到台词停止增长 ≤ 0.5 s（以 `speech_started` 到达为准，日志可查）。

### 4.6 （P1）让模型知道用户念到哪了

- 「电脑和会议室」模式下，会议室麦克风的本机转写（用户自己说的话）作为文字送进会话：`conversation.item.create`，role=`user`，内容 `[Candidate actually said] …`，**不触发** `response.create`。
- 作用：用户临场改了说法时，模型下一段能接上用户真正说的内容。P0 不做也能用。

### 4.7 屏幕

- 复用 `ScreenWatch`（`ScreenNotes.swift`）的取帧：`ScreenWatch.start(startedAt:model:)` 传空 `model` 时不会启动 `VisionServer`（见 `ScreenNotes.swift:60`、`:347`），只截帧和 OCR。实现前确认这一点，有出入就加一个「只取帧」开关，不要为此启动本机模型。
- 只在画面有变化时发（沿用 ScreenWatch 已有的变化检测），且两次间隔 ≥ 1 s；缩到长边 1280（或 720p）后 JPEG 压到 < 190 KB（质量从 0.7 往下试）。
- 视频宫格（多人摄像头）不发：沿用现有 `isSlide` 判断。
- 连接后的第一张图必须在至少发过一包音频之后。
- 用户关掉了「屏幕识别」就不发图。

### 4.8 断线与长会话

- 以阶段 0 测到的「单连接最长时长」为准，提前 2 分钟主动换连接；意外断开时立刻重连（指数退避 1/2/4/8 s，最多 5 次，失败在卡片上显示「Assistant 连接断了」+「重试」）。
- 重连后重建上下文：`session.update`（同样的 instructions）+ 一条 `conversation.item.create`，role=`user`，文字内容为「Interview so far」：最近 N 轮面试官原话（来自 `input_audio_transcription.completed`，客户端自己存最近 20 条）和我方最近 10 段台词，总长 ≤ 6000 字符。
- 换连接期间的音频先缓存在内存（最多 10 s），连上后补发。

### 4.9 记录

- 每段回答完成（`response.done`，含被打断的）存一行 `TranscriptLine(speaker: "ai", src: <台词，不含计划行和标记>, …)`，复用 `SessionStore.append` 和现有 AI 行的导出 / 隔离逻辑（参考 `AppModel.tickCopilot` 里现有的写法）。
- 计划行不进记录；中文对照沿用 `AskGloss`（本机翻译，开关 `askGloss`），可选。

## 5. instructions（系统提示词）草稿

放在 Swift 里一个 `CandidatePrompt` 纯函数中生成，输入背景 JSON，输出字符串；不做 `L()` 本地化。实现方可以调措辞，但要保留结构。

```
You are Jianhui Xu, the candidate, in a live job interview for <role from background>.
You hear the interviewer's voice and sometimes see the shared screen. The user reads your words
aloud word for word, so write exactly what the candidate should say, in natural spoken English.

How to answer:
- Think like a candidate who knows where the answer is going. For an open question (a system
  design, "how would you…"), first say the plan in one line, then go step by step: clarify scope,
  then the design, then the deep dives, one step per turn.
- Each turn: one line starting with "→ " saying what you will do next, then 1–4 short spoken
  sentences. End with [[more]] if the answer has further steps, otherwise [[end]].
- If the interviewer interrupts, drop the old route: answer what they just said, then decide
  whether to return to the plan.
- Only claim experience that <background> gives. If the question needs a personal example that
  the background does not have, say so with "[fill in: …]" instead of inventing one.
- Never write advice to the user ("you could say…"). Never translate into Chinese.

<background>
<resume, JD and company brief from tools/copilot-interview-background.json>
</background>
```

- 背景来源：**App 目前没有读取应聘者背景的地方**（`tools/copilot-interview-background.json` 只给评测脚本用，旧 Copilot 的 `<background>` 是会议转写）。本任务新增：
  - 背景存成纯文本文件 `~/Library/Application Support/<LiveSubs 或 LiveSubs Dev>/candidate-background.md`（权限 0600，不进 UserDefaults、不进导出）。
  - 设置页 Assistant 组里加「应聘者背景」：多行文本框，可粘贴简历、JD、公司简介，旁边一个「从文件导入」按钮（`.md` / `.txt` / `.json`）。
  - 测试和评测时，用 `tools/copilot-interview-background.json` 的 `candidate_resume` + `company_brief_user_supplied` 拼成文本导入。
  - 背景为空时照样能用，instructions 里的 `<background>` 写「(none given)」，模型遇到个人经历题一律用 `[fill in: …]`。
- instructions 总长控制在 8000 字符以内，超了先截公司简介。

## 6. 代码改动清单

### 新增

| 文件 | 内容 | 约行数 |
|---|---|---|
| `Sources/Cicada/RealtimeClient.swift` | WebSocket 连接、事件编解码（`Codable`）、发送队列、重连；UI 无关，`actor` 或专用队列 | ≤ 300 |
| `Sources/Cicada/Candidate.swift` | `CandidateEngine`（@MainActor，ObservableObject：连接状态、当前段落、历史段落、是否被打断）、`CandidateLoop`（纯）、`CandidatePrompt`（纯）、输出解析（纯） | ≤ 350 |
| `Sources/Cicada/CandidateFeed.swift` | 笔记窗口里的提词器视图：当前段落大字、计划行灰色、历史段落可回看、连接状态一行灰字 | ≤ 200 |
| `Tests/CicadaTests/CandidateTests.swift` | 见第 8 节 | — |
| `Tests/CicadaTests/RealtimeClientTests.swift` | 事件 JSON 编解码、PCM 转换、图片压缩上限 | — |
| `tools/qwen-realtime-probe.swift` | 阶段 0 的探针（见第 7 节） | ≤ 250 |

### 修改

- `AudioRouter.swift`：加一个 16 kHz 单声道的旁路回调（例如 `setOnRealtimePCM(_:)`），复用已有的 `voiceConverter` / `voiceFormat`，在 `process` 里按需转换；回调在路由队列里调用，接收方自己转 Int16 并入发送队列。不得改变现有识别、录音、说话人识别的行为。
- `AppModel.swift`：
  - 用 `CandidateEngine` 替换 `copilot` / `asker` 的接线：开始听 → 若 Assistant 开着且 Key 有效则连接；停止听 / 结束会议 → 断开并存记录。
  - `askNow()`（快捷键「问」）改为：若未连接则连接；若已连接则发 `response.create`（让它马上就当前内容作答），并取消进行中的回答。
  - `canAsk` 改为看 DashScope Key + WorkspaceId 是否齐全，不再看 `VisionServer`。
  - 调试命令（`debugCommand`）：保留 `ask`、`assistant:on|off`；`assistantState` 改为输出连接状态、当前 response_id、上次首字延迟、续写计数、本场累计用量；新增 `assistantSay:<text>`（不经音频，直接 `conversation.item.create` 一条面试官文字 + `response.create`，方便无声测试）；删除 `assistantPreview` 或改为用假数据渲染新视图。
- `Settings.swift`：新增 `realtimeRegion`（`"cn-beijing"` / `"ap-southeast-1"`，默认北京）、`realtimeWorkspace`、`realtimeModel`（默认 `qwen3.8-omni-flash-realtime`）。Key 不在这里。
- `AISettings.swift`（或 Assistant 现有设置所在处）：新增一组「Assistant 实时模型」：Key（密文输入框，保存到 `AIKey`）、WorkspaceId、地区、「测试连接」按钮（连上 → `session.updated` → 断开，显示 ✓ 或错误原因）、「应聘者背景」文本框与导入按钮（见第 5 节）。一行灰字说明「面试官的声音和共享屏幕会发送到阿里云百炼」。
- `NotesWindow.swift`（约 273、286 行两处）：把 `CopilotFeed` 换成 `CandidateFeed`；`AppModel.swift` 调试命令 `assistantPreview` 里的那处同理。
- `AGENTS.md`：改 `LingClient` 那条硬规则，加实时会话例外；Listening 段落补一句 Assistant 的数据流。保持 < 6 KB。
- `README*.md`、`site/changelog.json`：按 `AGENTS.md` Conventions 更新（中文 changelog 一条）。
- `tools/README.md`：补新的调试命令和测试方法。

### 删除（**单独一个提交，放在新链路验收通过之后**）

- `Copilot.swift`（`CopilotRules`、`Copilot`、`VoiceSides` 等；若 `VoiceSides` / `languageName` 等仍被别处使用，先确认再删）。
- `AnswerPlan.swift`。
- `Ask.swift` 里的 `AskEngine` 与 `AskPrompt` 中只为旧链路服务的部分；`AskPrompt.transcript` 等若记录 / 导出还在用就保留或挪走。
- `AskCard.swift` 里的 `CopilotFeed`、`PlanCard`、`AskCard`。
- 对应测试：`CopilotTests.swift`、`AnswerPlanTests.swift`、`AskModelTests.swift`、`AskTests.swift` 中失效的用例。
- `tools/copilot-eval.py`、`tools/copilot-prompt.json`、`Tests/test_copilot_eval.py`：旧的 Gemma 评测脚本，按需删除或改成实时版（见第 8 节）。
- **不删**：`VisionServer` / `ScreenWatch`（屏幕识别的会议记录行还在用本机模型，不在本任务范围）、`AskGloss`、`tools/copilot-questions.json`（题库保留）。
- 删除前 `grep` 全仓库确认无引用；删完 `scripts/test.sh` 必须全绿。

## 7. 执行阶段

每个阶段结束都要有证据（日志 / 截图 / 测试输出），不得只说「应该可以」。按 `AGENTS.md`，提交用英文 Conventional Commits，一次一件事；每个提交 ≤ 15 文件、≤ 400 行净改动。

### 阶段 0：探针（不改 App）

- 写 `tools/qwen-realtime-probe.swift`（只用 Foundation + AVFoundation，`swift tools/qwen-realtime-probe.swift <audio-file>` 运行）：
  - Key 从 `~/Library/Application Support/LiveSubs Dev/ai-key-dashscope` 读（`DevBuild.supportFolder`；正式版是 `LiveSubs`）（与 App 同一个文件；没有就提示用户在设置里填或手动创建 0600 文件），WorkspaceId / 地区从命令行参数传。
  - 用 `AVAssetReader` 把音频（如仓库里的 `AndroidEngineerMockInterview.mp4`）解成 16 kHz mono Int16，**按真实时间节奏**每 100 ms 推一包。
  - 打印带时间戳的事件流：speech_started/stopped、转写、text delta、response.done 用量。
  - 输出一份 JSON 报告到 `docs/evaluations/qwen-realtime-probe-<date>.json`：第 3 节 7 个待实测项的结果。
- 产出：在本文末尾「实测记录」追加结论。**若出现以下任一情况，停下来找用户**：只能出音频且费用翻倍以上；首字 p50 > 2 s；打断后 1 s 内停不下来；单连接 < 10 分钟且无法续接。

### 阶段 1：RealtimeClient + 纯逻辑 + 单元测试

- 实现 `RealtimeClient`、`CandidateLoop`、`CandidatePrompt`、输出解析器、PCM/图片编码。
- 单元测试全部离线（用 JSON fixture 模拟服务端事件序列，不连网）。

### 阶段 2：接进 App

- `AudioRouter` 旁路、`CandidateEngine`、`AppModel` 接线、设置页、`CandidateFeed`。
- 旧 Copilot 先**不删**，用 `continuousAssistant` 之外的临时开关或直接替换接线均可，但保证旧代码还能编译。

### 阶段 3：端到端验收（见第 8 节）

### 阶段 4：删除旧链路 + 文档

- 单独提交删除；更新 `AGENTS.md`、README（四种语言）、`site/changelog.json`、`tools/README.md`；跑 `python3 scripts/strings.py`。

## 8. 测试与验收

### 单元测试（`scripts/test.sh` 必须全绿）

- 事件编解码：每种客户端事件生成的 JSON 字段名、嵌套结构与文档一致；服务端事件（含未知类型）能解码且不崩。
- 音频：Float → Int16 LE 的截断与舍入；100 ms 分包长度（3200 字节）。
- 图片：超大截图压缩后 < 190 KB；未发音频前不发图；间隔 < 1 s 不发。
- 输出解析：计划行、台词、`[[more]]` / `[[end]]`；标记被拆在两个 delta 里；没写标记；中途被打断只剩半句。
- `CandidateLoop`：`[[more]]` 后静默超时续写；面试官说话中不续写；达到上限停止；`speechStarted` 时取消进行中的回答并清零计数；旧 response 的 delta 被丢弃。
- `CandidatePrompt`：背景超长时截断顺序；不含 `[fill in` 以外的编造指令（快照测试即可）。
- 重连上下文：最近 20 条面试官原话 + 10 段台词，总长 ≤ 6000 字符。
- Key：设置页保存后文件权限是 0600；`UserDefaults` 里没有 Key；日志里搜不到 Key。

### 端到端（用 dev build：`scripts/build.sh && open build/Cicada.app`，用 `tools/lsctl` 驱动，读 `/tmp/livesubs-dev-debug.log`）

| 场景 | 做法 | 通过线 |
|---|---|---|
| 首字 | `afplay` 播一道 ActAI Android 题（`say -o` 生成或从 mp4 截取），听「电脑」 | 面试官说完到首个 delta：p50 ≤ 1.5 s，p90 ≤ 3 s（10 题） |
| 连续讲长题 | 系统设计题（如 offline-first chat），之后保持静音 | 自动续写 ≥ 4 段，步骤不重复，有计划行，最后 `[[end]]` |
| 打断 | 长题讲到第 2 段时播放插话「Wait, why not use Room for that?」 | `speech_started` 后 ≤ 0.5 s 台词停止增长；新回答先回应插话 |
| 用户念台词不触发 | 「电脑和会议室」模式下用户对麦克风念台词 | 模型不把它当新问题（系统声音一路没有用户的声音） |
| 屏幕 | 共享一页含架构图的 PPT，问「What do you think of this diagram?」 | 回答提到图里的具体组件 |
| 长会话 | 播完整个 `AndroidEngineerMockInterview.mp4` | 全程不中断或断线后 ≤ 10 s 自动恢复，恢复后回答仍接得上前文 |
| 记录 | 结束会议后打开会议记录 | 每段台词是一行 AI 行，被打断的有标记；导出正常 |
| 无 Key | 删掉 Key 文件后开始听 | 卡片一行灰字引导去设置，不崩、不反复重连 |
| 英文 UI | 切到英文界面看设置页和提词器 | 不截断、不溢出 |

### 质量评测（人工 + 半自动）

- 用 `tools/copilot-questions.json` 中的 36 道 ActAI Android 题，用 `say -o` 生成面试官音频，跑一遍新链路，把每题完整台词存到 `docs/evaluations/qwen-realtime-<date>.md`。
- 每题按 4 项打分（0–2 分）：是否先给计划、是否连贯分步、技术是否正确、是否编造经历。与 `docs/evaluations/` 下旧 Gemma 结果对比，结论写进本文「实测记录」。

## 9. 风险与对策

| 风险 | 对策 |
|---|---|
| flash 实时模型推理较浅，深题答得浅 | 先测（第 8 节评测）；不行再试 `qwen3.5-omni-plus-realtime` 等更大的实时模型（只改 `realtimeModel` 设置即可，不改架构） |
| 实时模型偏短答，讲不完长题 | `[[more]]` 续写循环；instructions 明确「one step per turn」 |
| 只能出音频，费用高 | 阶段 0 确认；必要时丢弃音频只用 transcript，并记下每小时成本给用户决定 |
| `semantic_vad` 把面试官的思考停顿当成说完 | 阶段 0 测；必要时换 `server_vad` 加大 `silence_duration_ms`，或续写前多等一会儿 |
| 长会话断线、上下文超限 | 4.8 的主动换连接 + 摘要重建 |
| 隐私：面试内容上传云端 | 设置页灰字明示；Key 只存 0600；日志不记录音频、图片和完整台词（只记长度和时延） |
| 系统声音里混入非面试官声音（视频、通知音） | 本版接受；模型自己判断要不要回答 |

## 10. 完成定义

- 第 8 节单元测试和端到端表格全部通过，有日志 / 截图证据，结论写进下方「实测记录」。
- 旧 Copilot 链路已删除，`scripts/test.sh` 全绿，`RELEASE=1 scripts/build.sh` 能出包。
- `AGENTS.md`、README（四种语言）、`site/changelog.json`、`tools/README.md`、本地化字符串已更新。
- 交接说明：剩余问题、未达标项、v2 想法（例如支持会议室单麦克风模式、模型自己发声）列在本文末尾。

---

## 实测记录

（实现方在此追加：日期、测试条件、数据、结论。）

### 2026-11-07：阶段 0 探针准备，真实服务验证受阻

- 当前分支 `feat/screen-notes`。保留全部既有未提交改动；本轮未修改 App、未删除旧 Copilot、未提交其他会话的文件。
- 已重新读取官方中英文 Realtime 文档（英文页面更新于 2026-11-06）。Qwen3.8 的最小示例使用 `audio.input.format` 明确声明 16 kHz / s16le / mono；旧模型示例仍有顶层 `input_audio_format`。探针按 Qwen3.8 示例发送音频配置，请求 `modalities: ["text"]` 和 `semantic_vad`，最终兼容性必须以真实 `session.updated` 和回答为准。
- 新增 `tools/qwen-realtime-probe.swift`：AVAssetReader 流式解码、每包最多 3200 字节、联网按真实时间推送、显式取消、接收文字/转写长度与数字用量、丢弃输出音频、超时退出和 JSON 报告。Key 仅从约定的 0600 文件读取，不进入参数或日志。独立离线模式不读取 Key、不联网。
- 已通过：`swiftc -swift-version 6 -typecheck tools/qwen-realtime-probe.swift`；`python3 -m unittest discover -s Tests -p test_qwen_realtime_probe.py -v`（3 项测试：48 kHz 立体声重采样和部分包、无效音频、无效地区/时长）。
- 离线证据：`docs/evaluations/qwen-realtime-probe-2026-11-07-offline.json`。对 `Resources/sample/sample.m4a` 取 1 秒，解码成 32000 字节、10 包。此证据**仅验证本地解码/分包，不是实时模型或 App 端到端通过**。
- 阻碍：开发版约定路径没有 `ai-key-dashscope`，尚未收到 WorkspaceId/地区。阶段 0 七项实测均未完成，不推断模型支持纯文字、首字达标、自动取消、连接上限或价格。收到同区 Key 和业务空间后继续联网验证，依据结果再进入阶段 1–4。
- 指标边界：探针暂以服务端 `speech_stopped` 到首 delta 为观察值，不能替代标注音频真实结束时刻的端到端 p50/p90；自动取消因显式 cancel 无法独立证明；长连接/上下文只可记录已观察下界；小时费用需结合地区价格和代表性用量。系统设计答案质量、暂停误判需额外标注或现场审阅，不能由长度代替。


### 2026-11-07：真实服务与新链路实现进展（持续验收中）

前面的“缺 Key”是阶段 0 初始快照，现已解除。Workspace/北京地区来自用户；Key 由 App/探针从约定的 0600 文件读取，不进入参数、日志或本文。

- 新增原生 WebSocket `RealtimeClient`、16 kHz PCM 旁路、`CandidateEngine`/纯续写循环、提词器、连接测试和背景导入；Assistant 不经过本地 Gemma，也不播放模型音频。旧 Copilot 仍保留编译，仅断开运行时接线；**尚未满足删除阶段的全部验收条件**。
- `modalities:["text"]` 实测成功：文字 delta、转写、用量正常，输出音频事件为 0。已验证 610 秒真实面试音频按实时时钟推流，无协议错误，46 次响应；该探针不等于完整 Mac 端到端。
- `semantic_vad` 对完整合成问题漏答：初轮 36 题有 4 题无响应。因此默认改为 `server_vad` + 900 ms 静音。服务器 VAD 的同一打断样本产生两轮回答，中间响应为 cancelled；客户端仍显式 cancel，旧响应 ID 无法继续改变 UI。纯事件测试验证收到 speech_started 后同步封住旧 delta。
- 服务端 speech_stopped 到首 delta 的 610 秒探针 p50=413 ms、p90=563 ms；另 10 题以末尾 20 ms RMS>-50 dBFS 估算声学结束点，p50≈1.33 s、p90≈1.39 s。后者是合成音频/独立协议测量，**尚不能替代 10 题 Mac 系统声音端到端结果**。
- 按北京官方价格，610 秒探针累计输入 audio=52346、text=63371，输出 text=2726，合计约 ¥0.4214；这里包含反复计入的上下文。按同样交互密度线性折算约 ¥2.49/小时，仅是无屏幕情境估算，不是实测一小时账单。图片及交互密度会改变费用，不能只按唯一音频时长计算。
- 官方文档连接上限为 120 分钟；客户端在 118 分钟轮换。上下文上限按官方模型说明处理，未做 120 分钟或满上下文压测。真实连续服务当前仅能确认已观察下界。
- 设置页英文界面通过原生窗口检查，Save and test connection 实际显示 Connected；背景、Key 文件权限均按 0600。单元测试当前 298 项、50 suites 全绿；Mac 本地化 1203 keys，各语言 0 missing/unused/TODO/bad specifiers。
- 屏幕协议早期失败样本必须保留：在首包音频后、VAD 开始前立即发送唯一图片时，回答臆测为背景中的 Agent 架构。改为将最新变化图片保留到 speech_started 后发送，单图实测正确识别 Compose UI、Chat ViewModel、Room Database、Sync Worker、Chat API；response.done 包含 608 video_tokens。这里只证明协议与图像理解，**仍需真实屏幕取帧验收**。不得用 OCR 文本替代视觉理解来宣称通过。
- 发现 response.create 的 instructions 覆盖可能丢掉背景/约束；续写现携带完整 CandidatePrompt。重新跑 36 题评测，原始失败和中间结果保留，最终逐题质量评审待补。
- 完整 53 分钟面试已于 05:12:37 UTC 以 afplay → Mac 系统声音 tap 启动；中途主动断开测试约 2 秒恢复，另一次服务异常约 1 秒恢复，均重建 Interview so far。**该次回放随后因 SwiftUI 布局卡住而终止，长会话验收失败，详见下方后续记录。**

待完成：完整回放、真实屏幕/10 题端到端时延、记录导出、最新版本英文 UI 与焦点/共享保护复核、36 题逐项评分和旧 Gemma 对比、release 打包。麦克风真人念稿需要真实人声证据；仅接线检查不能等同该项人工验收。

### 2026-11-07：回放失败、质量评审与服务权限阻断

- 完整回放于约 05:26:34 UTC 停止推进；进程采样显示主线程在 SwiftUI 布局中循环，尚不能证明唯一根因。已停止测试音频并终止卡住的开发版。将有上限的提词历史容器由 LazyVStack 改为 VStack 后，独立原生提词器完成 150 段、3150 次流式更新、保留最近 30 段，过程仍可响应；最后观察 RSS 约 217 MiB。**这不代替完整 53 分钟重新回放，也不宣称长会话卡顿已彻底修复。**截图见 `evaluations/qwen-realtime-2026-11-07-layout-stress.png`。
- 服务连接随后返回顶层 `{code,message,request_id}`，没有 Realtime 的 `type`；安全探测确认 code 为 `AccessDenied.Unpurchased`。新增兼容解码，保留安全代码、忽略 provider message；该错误直接显示“请在百炼开通实时模型权限”，不反复自动重试。其余网络断线仍采用有限退避恢复。已请用户核对北京业务空间的服务及模型权限；未确定是余额、配额或哪项控制台开通状态，不能代用户推断。
- 逐题完整台词及人工四项评分见 [36 题评测](evaluations/qwen-realtime-2026-11-07.md)。最新重跑 30/36 题有回答，6 题失败；30 题中 4 题缺控制标记。失败题明确展示较早结果，不能拼接为当前版本全通过。除 context-recall 外，混合版本主观技术评分新链路 1.37/2、旧 Gemma 1.60/2，未观察到整体技术质量优势。已补充快照累积、持久发送、禁止丢弃排队消息及隐私承诺边界的提示约束，效果等待服务恢复后重测。
- 发现新评测早期遗漏每题 context；旧 Gemma 实际收到 context-recall 的 850 ms 约定，新模型没有。已修复 fixture/eval 的 context 传递，但公平重跑受服务拒绝阻断；不得据旧样本得出新模型记忆退化的结论。
- 实际会议记录 `20261107-131237` 有 23 条 AI 行，其中 11 条被打断；原生记录窗口能显示。Markdown 全部保留，DOCX 包含 AI 和 Interrupted，SRT 按设计只输出实际说出的台词，不含建议 AI 台词。Key 对开发日志、评测产物和本次导出做精确字节扫描为 0 命中，开发版 UserDefaults 无 Key；Key、背景文件权限为 0600。
- 最新离线测试 301 项 / 50 suites 全绿，探针 Python 测试 3 项全绿；Mac 本地化 1204 keys，en/ja/ko 均 0 missing/unused/TODO/bad specifiers；dev 与 release 构建成功。测试日志使用独立 `CICADA_DEBUG_CHANNEL=unit`，避免与真实 App 时延混淆。
- 无 Key 的引擎离线测试通过。重启开发版做原生无 Key 检查时，主线程阻塞在现有 SystemAudioTap 的 AudioUnitSetProperty / CoreAudio IPC，界面检查未完成；自动恢复了原始 Key 及其 0600 权限。此问题与此前 SwiftUI 布局循环的采样不同，不归为同一故障，也不把单测当原生验收通过。

当前交接：**实现已接入，阶段 3 未通过，阶段 4 删除旧链路尚未执行**。服务恢复后优先重新跑完整回放、Mac 系统声音 10 题首字、真实屏幕取帧和公平 36 题；还需原生无 Key、焦点/共享保护复核及真人麦克风念稿验证。汇总证据见 `evaluations/qwen-realtime-2026-11-07-validation.json`。不发布、不删除旧 Copilot，直到验收条件满足。

最终复核：最新协议客户端实测仍返回 `server: AccessDenied.Unpurchased`（`evaluations/qwen-realtime-2026-11-07-access-check.json`）；最终 dev/release 均构建成功，工作目录保留 dev bundle。测试音频和卡住的开发版已停止，原 Key 已恢复且仍为 0600；未重启全局音频服务。

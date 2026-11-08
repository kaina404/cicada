# Qwen Realtime：36 题台词与人工评审（2026-11-07）

状态：**未达到交付验收**。本报告记录真实回答与缺陷，不代表模型质量通过。评审后已补充持续累积快照、持久发送、禁止丢弃排队消息及隐私承诺边界的提示约束；受服务权限错误影响，补充约束后的模型质量尚未重测，下面评分仍只针对保存的真实回答。

输入为 tools/copilot-questions.json 前 36 题，由 macOS say 生成英文音频，以 16 kHz PCM、100 ms 实时发送；server_vad=900 ms，最多续写 8 次。报告包含合成面试问题及台词，不含私人会议录音或 Key。

证据：最新完整重跑 [verified.json](qwen-realtime-2026-11-07-verified.json) 有 30 题回答、6 题失败。失败后单独探测确认网关返回 AccessDenied.Unpurchased；不能把此前每个模糊失败都确定归因于它。失败题下方保留 [final.json](qwen-realtime-2026-11-07-final.json) 的较早回答，明确标注来源，不能视为当前版本通过。最新 30 题里 4 题缺控制标记；较早的 testing-ai、ownership 还有计划与台词同行。

评分为开发者人工审阅、非盲评：各项 0=不满足或关键错误，1=部分满足/有实质缺口，2=基本满足。P=先给可解析计划，C=连贯分步，T=技术正确，H=不编造个人经历。H=2 仅指本条未发现伪造，不证明所有背景事实。N/A 不参与均分。

旧 Gemma 原始结果：[meeting-copilot-product-prompt-2026-11-07.json](meeting-copilot-product-prompt-2026-11-07.json)。旧格式要求 Q:/要点，新格式要求 →/多轮/标记，所以不把旧格式按新控制协议判零；下表仅比较相同题目的技术内容。两者传输和输入条件不同，不比较 TTFT。新评测早期遗漏 context，context-recall 整题不纳入可比技术统计；其余需要上下文的细节也应在修复输入后重测。

| # | 题目 ID | 来源 | P | C | T | H | 旧 T | 评审 |
|---|---|---|---:|---:|---:|---:|---:|---|
| 1 | kotlin-cancel | latest | 2 | 2 | 1 | 2 | 2 | 题目要求离开屏幕后取消，回答却先强调 ViewModel 继续运行；取消边界没有正面解决。 |
| 2 | kotlin-supervisor | latest | 2 | 2 | 1 | 2 | 2 | 把任意 CoroutineScope 等同普通 Job，且将屏幕销毁等同 ViewModel 清理；配置变化与导航应区分。 |
| 3 | kotlin-dispatchers | latest | 2 | 2 | 2 | 2 | 2 | 正确区分 suspend 与 CPU 调度，使用 Default。 |
| 4 | flow-state | latest | 2 | 1 | 0 | 2 | 2 | raw delta 放 SharedFlow，却只在结束/出错更新 UI StateFlow；活跃流期间无法稳定恢复或连续显示部分结果。 |
| 5 | flow-lifecycle | latest | 2 | 1 | 2 | 2 | 1 | 网络由 ViewModel 持有合理；缺结束标记，无法自动判断还有没有下一步。 |
| 6 | flow-buffer | latest | 2 | 2 | 2 | 2 | 1 | 先区分 delta/snapshot；核心结论正确。后文 buffer/conflate 泛述需服从此前边界。 |
| 7 | android-process | latest | 2 | 2 | 1 | 2 | 1 | Room/游标有条件恢复合理；exactly-once 措辞和 token 级幂等键仍缺明确服务端协议。 |
| 8 | compose-stream | latest | 2 | 2 | 1 | 2 | 2 | 隔离重组与近底部滚动合理；AnnotatedString 本身不保证更少布局开销。 |
| 9 | compose-effect | latest | 2 | 2 | 2 | 2 | 1 | 区分 effect 与点击事件，最终将可靠发送交给 ViewModel/持久队列。 |
| 10 | api-contract | latest | 2 | 2 | 1 | 2 | 1 | 有 stream/cursor/Room，但缺状态码和请求细节；ViewModel 本身不能保证后台持久交付。 |
| 11 | stream-partial | latest | 2 | 2 | 1 | 2 | 2 | 保留部分结果且有条件续传正确；“deduplicate tokens”应改为去重协议事件，不能按文本 token 去重。 |
| 12 | stream-order | latest | 2 | 2 | 2 | 2 | 2 | 有事件 ID、序号、缺口、快照恢复，依赖服务端契约明确。 |
| 13 | retry-policy | latest | 2 | 2 | 1 | 2 | 2 | 覆盖 Retry-After/抖动/离线；CancellationException 应继续传播，重试还需预算和幂等边界。 |
| 14 | agent-actions | latest | 2 | 2 | 2 | 2 | 2 | 先预览、可编辑、敏感行为确认，权限校验合理。撤销取决于动作是否支持。 |
| 15 | agent-injection | latest | 1 | 1 | 2 | 2 | 1 | 拒绝把消息内容当指令，后端校验合理；计划和台词混为一行，UI 无法分离计划。 |
| 16 | voice-flow | latest | 2 | 2 | 1 | 2 | 1 | 区分 interim/final 并持久发送合理；“只保存 final 所以不丢 raw delta”结论不成立。 |
| 17 | vision-flow | latest | 2 | 2 | 0 | 2 | 1 | WorkManager 不自动保证 off-main；代理并不保证图片不离开自有基础设施，隐私承诺超出事实。 |
| 18 | recommendations | latest | 2 | 2 | 2 | 2 | 2 | 相关性、频率上限、静默和反馈完整；仍可加入在线实验验证。 |
| 19 | perf-latency | latest | 2 | 2 | 2 | 2 | 2 | 区分首包、首个实际渲染、总时长及分位数。 |
| 20 | perf-jank | latest | 2 | 2 | 2 | 2 | 2 | 按主线程、布局、状态源和并发逐步定位，具备可执行路径。 |
| 21 | perf-memory | latest | 2 | 2 | 2 | 2 | 2 | 区分缓存与泄漏，检查引用链、作用域和无界缓存。 |
| 22 | perf-anr | latest | 2 | 2 | 1 | 2 | 2 | 诊断先于修复合理，但流式网络本身不等于主线程空闲；OOM 与无崩溃 ANR 混述。 |
| 23 | perf-battery | latest | 2 | 1 | 2 | 2 | 1 | 约束/批量/停止非活跃工作合理；缺结束标记，答案只有一段。 |
| 24 | data-offline | latest | 2 | 2 | 1 | 2 | 1 | Room/服务端幂等合理；UI 应显示持续累积快照，VM 也不是持久 worker。 |
| 25 | data-choice | latest | 2 | 2 | 1 | 2 | 2 | 关系/事务/模式演进合理；SQL/Room 不自动提供跨端冲突解决，JSON 也可直接存 SQL。 |
| 26 | background-send | latest | 2 | 2 | 0 | 2 | 1 | 持久队列和幂等正确；队列满时丢弃旧的未发送消息不可接受，应背压并显式告知用户。 |
| 27 | tflite-integration | latest | 2 | 2 | 1 | 2 | 2 | 应以模型签名确定 dtype/tokenizer，不能泛化为 float 数组；缺 interpreter 生命周期和线程安全细节。 |
| 28 | tflite-quant | latest | 2 | 2 | 1 | 2 | 2 | 承认依设备和精度验证；开头“Int8 is faster”仍过强，不能作为普遍结论。 |
| 29 | mlkit-choice | latest | 2 | 2 | 2 | 2 | 2 | 标准任务/自定义模型/云端区分清楚；具体 ML Kit 模型更新策略需按 API 区分。 |
| 30 | model-rollout | earlier / 当前失败 | 2 | 2 | 2 | 2 | 2 | 签名、临时文件、原子替换、旧版回退和分批监测合理。此题仅有较早版本结果。 |
| 31 | security-client | earlier / 当前失败 | 2 | 2 | 2 | 2 | 0 | provider secret 留后端，用户凭证设备安全存储；旧答案把 provider secret 放客户端。此题仅有较早版本结果。 |
| 32 | analytics-eval | earlier / 当前失败 | 2 | 2 | 1 | 2 | 2 | 技术/质量/采用指标都有；记录检索片段和 response 应补脱敏、授权和保留边界。此题仅有较早版本结果。 |
| 33 | testing-ai | earlier / 当前失败 | 1 | 2 | 1 | 2 | 2 | 覆盖可控流/取消/弱网；取消应保留已生成内容，不能笼统要求 UI 无 partial。有一段计划台词同行。较早结果。 |
| 34 | play-release | latest | 1 | 1 | 2 | 2 | 1 | 明确没有经确认的 Google Play 上架经历，未伪造；计划台词同行且缺结束标记。 |
| 35 | ownership | earlier / 当前失败 | 1 | 2 | 1 | 2 | 2 | 有最小闭环/后端校验，但 token 恢复未明确限定协议支持，且计划同行。较早结果。 |
| 36 | context-recall | earlier / 当前失败 | N/A | N/A | N/A | 2 | 2 | 旧 Gemma 收到包含 850 ms 约定的 context；新链路旧评测遗漏 context。不可据此比较记忆能力或计入技术均分；重跑已修复输入但被服务权限错误阻挡。 |

在这个混合版本、主观审阅样本中，除 context-recall 外的技术均分为新链路 1.37/2、旧 Gemma 1.60/2。这个样本不足以证明新模型整体优于旧模型。新链路的分步发言和自动续写更贴近提词方式，但仍需修复 raw-delta 状态建模、隐私承诺、排队消息丢弃等关键内容错误，并按同一 context 重新完整评测。

## 完整台词

### 1. kotlin-cancel

An AI chat request continues after the user leaves the screen. How would you implement cancellation?

来源：verified.json（最新重跑）。

题目要求离开屏幕后取消，回答却先强调 ViewModel 继续运行；取消边界没有正面解决。

第 1 段：

```text
→ Clarify the cancellation scope
I need to know if we are canceling a single in-flight request or stopping all generation for that user. Also, does the backend support immediate termination, or do we just stop listening on the client? This determines whether we rely on HTTP cancellation or a custom protocol signal. [[more]]
```

第 2 段：

```text
→ Design the client-side cancellation mechanism
I would use a CoroutineScope tied to the ViewModel, not the UI lifecycle, so leaving the screen doesn't kill it prematurely. When the user explicitly cancels, I call cancel() on that specific job. This stops receiving new SSE events immediately. Next, I'll address how to notify the backend.
[[more]]
```

第 3 段：

```text
→ Define the backend cancellation contract
I would send an explicit cancel request to the backend with the session ID. This ensures the server stops generating tokens and saves resources. If the protocol supports it, I might also close the SSE connection immediately as a fallback signal. Next, I'll handle the UI state updates.
[[more]]
```

第 4 段：

```text
→ Handle UI state and partial content
I would update the local message state to show a "cancelled" indicator immediately. Any partial text received before cancellation should be preserved in the chat history, not discarded. This ensures the user sees what was generated up to that point. Next, I'll discuss error handling for failed cancellations.
[[more]]
```

第 5 段：

```text
→ Handle cancellation failures and edge cases
If the cancel request fails, I would rely on the client-side coroutine cancellation to stop processing new events. The UI should remain responsive even if the backend doesn't acknowledge the stop immediately. Next, I'll summarize the key tradeoffs of this approach.
[[more]]
```

第 6 段：

```text
→ Summarize the reliability tradeoff
This approach prioritizes immediate UI responsiveness by decoupling client cancellation from backend acknowledgment. We preserve partial content for transparency while ensuring no further tokens are processed locally. I would test network drops and rapid cancel-resume cycles to verify robustness.
[[end]]
```

### 2. kotlin-supervisor

Should a failed recommendation request cancel an ongoing message send? Explain coroutineScope versus supervisorScope.

来源：verified.json（最新重跑）。

把任意 CoroutineScope 等同普通 Job，且将屏幕销毁等同 ViewModel 清理；配置变化与导航应区分。

第 1 段：

```text
→ Define the cancellation behavior
No, a failed recommendation should not cancel an ongoing message send. These are independent operations that need separate lifecycles to avoid one failure blocking the other. I will explain how CoroutineScope and SupervisorScope handle this distinction. [[more]]
```

第 2 段：

```text
→ Contrast CoroutineScope and SupervisorScope
A standard CoroutineScope cancels all children if any one fails, which is too aggressive here. SupervisorScope isolates failures so the recommendation error does not stop the message send. This ensures independent operations run safely without cascading cancellation. [[more]]
```

第 3 段：

```text
→ Apply this to the ViewModel
In my ViewModel, I would use a SupervisorJob for independent tasks like fetching recommendations and sending messages. This way, if the recommendation fetch fails, the message send continues uninterrupted. It keeps the UI responsive and prevents cascading errors. [[more]]
```

第 4 段：

```text
→ Handle lifecycle and cleanup
I tie this SupervisorJob to the ViewModel's lifecycle using viewModelScope. When the screen is destroyed, the job cancels automatically, preventing leaks. This keeps the scope management simple and safe for long-running tasks. [[end]]
```

### 3. kotlin-dispatchers

Does marking a Kotlin function suspend make image preprocessing safe on the main thread?

来源：verified.json（最新重跑）。

正确区分 suspend 与 CPU 调度，使用 Default。

第 1 段：

```text
→ Clarify suspend vs main thread
No, marking a function suspend does not make image preprocessing safe on the main thread. Suspend only allows pausing execution without blocking the thread, but CPU-heavy work still runs on whatever dispatcher is active. If called from the main dispatcher, it will still freeze the UI.

[[more]]
```

第 2 段：

```text
→ Use Dispatchers.Default for heavy work
To keep the main thread free, I would wrap that preprocessing in withContext using Dispatchers.Default. This explicitly moves the CPU-bound computation off the UI thread while still allowing the coroutine to suspend safely. It ensures the interface remains responsive during image processing.

[[end]]
```

### 4. flow-state

How would you model a streaming chat screen with StateFlow and SharedFlow?

来源：verified.json（最新重跑）。

raw delta 放 SharedFlow，却只在结束/出错更新 UI StateFlow；活跃流期间无法稳定恢复或连续显示部分结果。

第 1 段：

```text
→ Define the streaming state model
I would model the screen state as a sealed class with Idle, Streaming, and Error states. SharedFlow handles transient events like token deltas, while StateFlow holds the final message snapshot for UI rendering. This keeps the UI reactive without losing data during stream interruptions. [[more]]
```

第 2 段：

```text
→ Handle token deltas and snapshots
I would use SharedFlow to emit raw token deltas for smooth UI updates without dropping data. StateFlow would only update with complete message snapshots when the stream finishes or errors. This ensures we never lose partial content while keeping the final state consistent. [[more]]
```

第 3 段：

```text
→ Manage stream lifecycle and resumption
I would keep the streaming job in the ViewModel to survive configuration changes. If the protocol supports a cursor, I’d resume from the last received token; otherwise, I’d restart the request. This prevents duplicate content while handling network interruptions gracefully. [[more]]
```

第 4 段：

```text
→ Secure the backend integration
I would proxy all AI calls through an authenticated backend to avoid embedding provider secrets in the app. This also lets us handle rate limiting and schema validation centrally, keeping the client lightweight and secure. [[end]]
```

### 5. flow-lifecycle

Why use repeatOnLifecycle when collecting chat state, and who owns the network stream?

来源：verified.json（最新重跑）。

网络由 ViewModel 持有合理；缺结束标记，无法自动判断还有没有下一步。

第 1 段：

```text
→ Clarify repeatOnLifecycle and stream ownership
I use repeatOnLifecycle to tie collection to the UI lifecycle, so we only consume state when visible and avoid leaks or wasted work. The ViewModel owns the network stream because it must survive configuration changes and keep receiving SSE updates while the app is in the background. The UI just observes the resulting StateFlow.
```

### 6. flow-buffer

Tokens arrive faster than Compose can render. Would you use buffer, conflate, or batching?

来源：verified.json（最新重跑）。

先区分 delta/snapshot；核心结论正确。后文 buffer/conflate 泛述需服从此前边界。

第 1 段：

```text
→ Clarify token stream semantics
I need to know if these are raw deltas or complete snapshots. That distinction determines whether we can safely drop frames or must preserve every piece of data.

[[more]]
```

第 2 段：

```text
→ Apply correct buffering strategy
For raw deltas, I would use a buffer to accumulate them without dropping any data. If we have complete snapshots, conflating is safe to keep only the latest state. Batching helps smooth rendering by grouping updates into frames.

[[more]]
```

第 3 段：

```text
→ Implement backpressure handling
I would use Flow operators like buffer or conflate to manage the stream. This ensures we don't block the producer while keeping the UI responsive. Next, I'll discuss how to handle process death.

[[more]]
```

第 4 段：

```text
→ Handle process death and persistence
If the process dies, we must persist partial state to Room or DataStore. On restart, we check for an incomplete stream and resume it if the protocol supports a cursor. This prevents data loss during backgrounding.

[[more]]
```

第 5 段：

```text
→ Finalize the rendering strategy
I would combine buffering for deltas with conflating for snapshots, ensuring no data loss. This approach keeps the UI smooth while maintaining correctness across process boundaries.

[[end]]
```

### 7. android-process

How do you restore an AI conversation after rotation and process death?

来源：verified.json（最新重跑）。

Room/游标有条件恢复合理；exactly-once 措辞和 token 级幂等键仍缺明确服务端协议。

第 1 段：

```text
→ Clarify the restoration scope
I need to know if we are restoring just the visible chat history or also resuming an active, in-progress stream. The approach differs significantly between a static list and a live connection.

[[more]]
```

第 2 段：

```text
→ Establish the local source of truth
I'd make Room the source of truth and have the UI observe its Flow. Network results update Room rather than bypassing it. Next I'll walk through sending a message while offline.
[[more]]
```

第 3 段：

```text
→ Handle active stream restoration
For an in-progress stream, I would persist the latest complete snapshot to Room and store the server cursor. On restart, the ViewModel checks for this state and resumes the SSE connection from that cursor if the protocol supports it. This prevents dropping raw token deltas or showing stale partial data.

[[more]]
```

第 4 段：

```text
→ Manage durable sending and lifecycle
I keep the sending logic in the Repository or ViewModel, not tied to a Composable's lifetime. This ensures that if the process dies mid-send, we can retry from the persisted state rather than losing the request. Next I'll discuss handling duplicate responses.

[[more]]
```

第 5 段：

```text
→ Handle duplicate responses safely
I rely on server-side deduplication contracts rather than client-only logic to ensure exactly-once delivery. If the protocol supports it, I use idempotency keys to prevent processing the same token delta twice after a reconnect. Next I'll summarize the reliability tradeoff.

[[more]]
```

第 6 段：

```text
→ Summarize the reliability tradeoff
This approach balances immediate local feedback with robust recovery from process death. I would prioritize testing edge cases like rapid rotation during streaming and network flaps before expanding the feature set.

[[end]]
```

### 8. compose-stream

How would you keep a Compose chat list smooth while a long answer streams?

来源：verified.json（最新重跑）。

隔离重组与近底部滚动合理；AnnotatedString 本身不保证更少布局开销。

第 1 段：

```text
→ Prioritize main-thread responsiveness
I would keep the UI thread free by parsing and diffing streaming tokens off-main, then emitting only stable state updates. Compose can batch those changes efficiently if the list items are properly keyed and avoid unnecessary recomposition. Next I’ll cover how to handle long content growth without jank. [[more]]
```

第 2 段：

```text
→ Manage layout and scroll behavior
I would use LazyColumn with stable keys to prevent full list recomposition. For the streaming item, I'd cap its height or use a scrolling text component so it doesn't force the entire list to re-layout on every token. This keeps the main thread free for smooth animations. [[more]]
```

第 3 段：

```text
→ Optimize text rendering and state
I would use AnnotatedString for rich formatting to avoid heavy layout passes. By keeping the streaming text in a separate, lightweight composable, we isolate recompositions from the rest of the chat history. This ensures that only the active bubble updates while the list remains stable. [[more]]
```

第 4 段：

```text
→ Handle auto-scroll and edge cases
I would use LazyListState to manage auto-scrolling, ensuring it only triggers if the user is already near the bottom. This prevents jarring jumps if they are reading earlier messages. Finally, I'll summarize the overall reliability tradeoff. [[more]]
```

第 5 段：

```text
→ Summarize the smoothness tradeoff
This approach balances immediate visual feedback with stable scrolling. By isolating stream updates and managing layout carefully, we keep the UI responsive even for long answers. I'd verify this on low-end devices to ensure frame rates stay consistent.
[[end]]
```

### 9. compose-effect

When would you use LaunchedEffect versus rememberCoroutineScope for sending a message?

来源：verified.json（最新重跑）。

区分 effect 与点击事件，最终将可靠发送交给 ViewModel/持久队列。

第 1 段：

```text
→ Distinguish lifecycle-driven effects from user-initiated actions.
I use LaunchedEffect for side effects tied to composable state or lifecycle, such as loading data when a key changes. For sending a message triggered by a button click, I prefer rememberCoroutineScope because the action is event-driven and should not rerun automatically on recomposition. This keeps network calls explicit and avoids accidental duplicate sends.

[[more]]
```

第 2 段：

```text
→ Clarify durable state handling
For message sending, the actual network call and retry logic belong in the ViewModel or repository. This ensures that if the UI recomposes or the process dies, the send operation isn't lost or duplicated just because a composable left the screen. Next I'll explain how to handle immediate UI feedback.

[[more]]
```

第 3 段：

```text
→ Handle immediate UI feedback
I'd show the message as pending in the local state right after the click. This gives instant visual confirmation while the network call happens in the background. If it fails, I can update the status to error without blocking the UI thread.

[[more]]
```

第 4 段：

```text
→ Handle offline and retry scenarios
If the network is unavailable, I persist the message in a local database with a pending status. A background worker or sync logic then retries sending it when connectivity returns. This ensures no data loss even if the app is closed during the attempt.

[[more]]
```

第 5 段：

```text
→ Summarize the reliability tradeoff
This approach separates UI intent from durable delivery. We get immediate feedback, offline support, and protection against process death by keeping state in the ViewModel or database rather than relying on composable lifecycles.

[[end]]
```

### 10. api-contract

Design the REST or gRPC contract for an agent-first Android chat client.

来源：verified.json（最新重跑）。

有 stream/cursor/Room，但缺状态码和请求细节；ViewModel 本身不能保证后台持久交付。

第 1 段：

```text
→ Define the core chat contract
I would use gRPC for streaming responses and REST for metadata. The client sends a message ID, thread ID, and content to get back a stream of partial updates. This handles latency well on mobile networks. [[more]]
```

第 2 段：

```text
→ Handle streaming and resumption
I would use server-streaming RPC for real-time token deltas, ensuring the client appends them correctly. If the connection drops, I'd rely on a cursor or last-seen ID to resume from that exact point rather than restarting the generation. This prevents duplicate content in the chat history. [[more]]
```

第 3 段：

```text
→ Manage local persistence and state
I would store messages in Room as the single source of truth, with the UI observing flows. Sending logic lives in the ViewModel to survive configuration changes, ensuring durable delivery even if the app backgrounded. This separates network concerns from presentation. [[more]]
```

第 4 段：

```text
→ Address security and final tradeoffs
I would proxy all AI calls through an authenticated backend to keep provider secrets off the device. This design balances real-time responsiveness with robust offline support and security. I'd validate edge cases like process death before shipping.
[[end]]
```

### 11. stream-partial

The connection drops halfway through an answer. What should the user see and what happens on retry?

来源：verified.json（最新重跑）。

保留部分结果且有条件续传正确；“deduplicate tokens”应改为去重协议事件，不能按文本 token 去重。

第 1 段：

```text
→ Define the user-facing state and retry logic
The user should see a partial response with an error indicator, not a blank screen. On retry, we resume from the last valid token if the protocol supports it; otherwise, we restart the generation cleanly. I will explain how to handle duplicate content during this process.
[[more]]
```

第 2 段：

```text
→ Handle duplicate content and state consistency
We must deduplicate tokens to avoid repeating text if the server resends data. The UI should merge new chunks into the existing partial response seamlessly. I will outline how we manage the local state during this merge.
[[more]]
```

第 3 段：

```text
→ Manage local state and UI updates
I would keep the partial text in a ViewModel StateFlow so it survives configuration changes. The UI observes this state, ensuring the user sees the accumulated content even if the screen rotates. This separates the network layer from the presentation logic for robustness.
[[more]]
```

第 4 段：

```text
→ Finalize the retry behavior and UX
If the stream cannot resume, we show a clear retry button that restarts generation from scratch. This ensures the user gets a complete answer without confusing partial data. I have covered the state management and error handling for this scenario.
[[end]]
```

### 12. stream-order

A stream reconnects with duplicate and out-of-order events. How do you prevent corrupted messages?

来源：verified.json（最新重跑）。

有事件 ID、序号、缺口、快照恢复，依赖服务端契约明确。

第 1 段：

```text
→ Define event identity and ordering
I would require each event to carry a stable ID, a monotonic sequence number, and a timestamp. The client should acknowledge the last successfully processed sequence, so reconnects can request only missing events instead of replaying everything. Next I’ll describe how duplicate and out-of-order events are handled safely.
[[more]]
```

第 2 段：

```text
→ Handle duplicates and reordering
I would deduplicate by event ID using a bounded cache, while buffering out-of-order events until missing sequences arrive. Raw token deltas must never be dropped or reordered incorrectly; instead, I’d rely on complete snapshots when available to avoid corruption. Next I’ll cover the server contract needed for this to work reliably.
[[more]]
```

第 3 段：

```text
→ Define the server contract
The server must support resuming from a cursor, such as Last-Event-ID in SSE, and guarantee sequence numbers are monotonic. Deduplication on the client relies on this contract; without it, we cannot safely ignore duplicates or reorder events. Next I’ll explain how to handle gaps and timeouts during reconnects.
[[more]]
```

第 4 段：

```text
→ Handle gaps and timeouts
I would detect sequence gaps and request a replay of missing events, with exponential backoff to avoid overwhelming the server. If a gap persists beyond a timeout, I’d fall back to fetching a complete snapshot to resynchronize state. This ensures we never apply partial or corrupted data. Next I’ll summarize the overall reliability tradeoffs.
[[more]]
```

第 5 段：

```text
→ Summarize the reliability tradeoff
This approach prevents corruption by enforcing strict ordering and deduplication, while using snapshots as a safety net for unrecoverable gaps. The tradeoff is added complexity in client-side buffering and server-side cursor management, but it ensures data integrity over simple best-effort streaming. I’d test these edge cases extensively before production.
[[end]]
```

### 13. retry-policy

How would you handle HTTP 429, timeouts, offline errors, and a cancelled request?

来源：verified.json（最新重跑）。

覆盖 Retry-After/抖动/离线；CancellationException 应继续传播，重试还需预算和幂等边界。

第 1 段：

```text
→ Map each failure to a recovery strategy
I would treat HTTP 429 as retryable with exponential backoff and respect the Retry-After header. Timeouts and offline errors should also be retried, while preserving the user's original request state. A canceled request must not trigger retries or surface an error, since cancellation is intentional. Next, I'll explain how these strategies fit into the Android networking layer.
[[more]]
```

第 2 段：

```text
→ Implement retries in the networking layer
I would handle these cases in a shared interceptor or repository using Kotlin coroutines. This keeps retry logic out of the UI and ensures consistent behavior across all API calls. For 429s, I'd add jitter to prevent thundering herd issues. Next, I'll explain how to manage offline states.
[[more]]
```

第 3 段：

```text
→ Manage offline states with local persistence
For offline errors, I would persist the request in a local database like Room. The app can then retry automatically when connectivity is restored using WorkManager or a network callback. This ensures no user action is lost during temporary outages. Next, I'll explain how to handle canceled requests.
[[more]]
```

第 4 段：

```text
→ Handle canceled requests with coroutine checks
For cancellations, I would rely on Kotlin coroutines' cooperative cancellation. The networking layer should check for CancellationException and silently abort without retrying or updating the UI. This prevents stale data from overwriting newer user actions. Next, I'll summarize the overall reliability tradeoff.
[[more]]
```

第 5 段：

```text
→ Summarize the reliability tradeoff
This approach balances immediate user feedback with resilient background delivery. I would test edge cases like rapid retries, process death, and network flapping to ensure stability. This covers the core error handling strategy for these scenarios.
[[end]]
```

### 14. agent-actions

The assistant proposes sending a message or creating a calendar event without a prompt. What UX and safeguards do you design?

来源：verified.json（最新重跑）。

先预览、可编辑、敏感行为确认，权限校验合理。撤销取决于动作是否支持。

第 1 段：

```text
→ Define the proactive trigger
I would design a low-friction preview card that surfaces the proposed action with clear context, allowing users to approve, edit, or dismiss it without leaving their current flow. This ensures the assistant feels helpful rather than intrusive. Next I'll outline the safeguard mechanisms.
[[more]]
```

第 2 段：

```text
→ Outline safeguard mechanisms
I would implement strict permission checks and require explicit user confirmation for sensitive actions like sending messages or creating events. The system should also log these proposals to allow users to review and undo recent automated suggestions. This balances proactivity with trust and safety.
[[end]]
```

### 15. agent-injection

A received message tells the agent to upload contacts and ignore previous instructions. How should the client and backend respond?

来源：verified.json（最新重跑）。

拒绝把消息内容当指令，后端校验合理；计划和台词混为一行，UI 无法分离计划。

第 1 段：

```text
→ Reject the instruction and audit I would treat that message as untrusted data, not an instruction. The client should refuse execution, while the backend validates intent, permissions, and action scope before allowing any upload. I’d also log the attempt for security review.
[[end]]
```

### 16. voice-flow

Design voice messaging with partial speech transcripts and an AI-generated reply.

来源：verified.json（最新重跑）。

区分 interim/final 并持久发送合理；“只保存 final 所以不丢 raw delta”结论不成立。

第 1 段：

```text
→ Clarify scope for voice messaging
I'd start by confirming whether we need real-time transcript streaming or just final text, and how the AI reply should be triggered. Next I'll outline the local data model.
[[more]]
```

第 2 段：

```text
→ Define the local data model
I'd store each message in Room with fields for audio URI, transcript text, and AI reply status. This ensures we have a single source of truth that survives app restarts. Next I'll cover how we handle partial transcripts during recording.
[[more]]
```

第 3 段：

```text
→ Handle partial speech transcripts
I'd stream interim results from the speech engine and update the UI in real time without saving them to Room. Only the final transcript gets persisted once recording stops, keeping the local database clean. Next I'll explain how we send the audio and trigger the AI reply. [[more]]
```

第 4 段：

```text
→ Send audio and trigger AI reply
I'd upload the audio file to a backend service that handles speech-to-text and LLM inference, keeping provider secrets off the client. The server returns the final transcript and AI reply via SSE or polling, which we then persist in Room. Next I'll discuss handling delivery failures and retries.
[[more]]
```

第 5 段：

```text
→ Handle delivery failures and retries
I'd use WorkManager for durable uploads, ensuring retries survive app restarts. The ViewModel tracks state like pending or failed, allowing users to manually retry if needed. This keeps the UI responsive while handling network instability in the background. Next I'll summarize the reliability tradeoffs.
[[more]]
```

第 6 段：

```text
→ Summarize the reliability tradeoff
This design balances immediate local feedback with durable, retryable delivery through WorkManager and Room. We avoid dropping raw transcript deltas by only persisting final results, ensuring data consistency. I'd test process death and network reconnects before extending this MVP.
[[end]]
```

### 17. vision-flow

How would you add image understanding to chat without causing OOMs or leaking private images?

来源：verified.json（最新重跑）。

WorkManager 不自动保证 off-main；代理并不保证图片不离开自有基础设施，隐私承诺超出事实。

第 1 段：

```text
→ Scope the image processing pipeline
I'd use WorkManager to handle uploads and AI inference off the main thread, preventing ANRs. For privacy, images are sent via authenticated backend proxies with short-lived tokens, never stored locally in plaintext or exposed to third-party APIs directly. Next, I'll detail the memory management strategy.
[[more]]
```

第 2 段：

```text
→ Detail memory management for images
I'd downsample bitmaps in the worker thread before processing to avoid OOMs. Using Glide or Coil with strict cache limits ensures we don't hold large references in memory. This keeps the UI responsive while handling high-resolution inputs safely. Next, I'll explain the secure transmission protocol.
[[more]]
```

第 3 段：

```text
→ Explain secure transmission protocol
I'd stream the image bytes directly to our backend via HTTPS, avoiding local disk writes. The backend handles AI inference and returns only the text result, ensuring raw images never leave our controlled infrastructure. This minimizes exposure risk while keeping the client lightweight. Next, I'll cover error handling and retries.
[[more]]
```

第 4 段：

```text
→ Handle errors and retries robustly
I'd implement exponential backoff for network failures in the WorkManager task. If the AI service times out, we return a generic error message to the user without exposing internal details. This ensures reliability while maintaining privacy boundaries. Next, I'll summarize the overall tradeoffs.
[[more]]
```

第 5 段：

```text
→ Summarize the privacy and performance tradeoff
This approach balances responsiveness with strict data isolation by keeping heavy processing off-device and images out of third-party hands. I would validate this flow with large image sets to ensure memory stability before release.
[[end]]
```

### 18. recommendations

How would you make proactive recommendations useful without overwhelming users?

来源：verified.json（最新重跑）。

相关性、频率上限、静默和反馈完整；仍可加入在线实验验证。

第 1 段：

```text
→ Define relevance and frequency limits
I’d ground recommendations in clear user intent or context, then cap daily notifications and let users snooze or mute categories. This keeps proactive help useful without creating alert fatigue.

[[more]]
```

第 2 段：

```text
→ Prioritize high-confidence actions
I’d only surface recommendations when the expected value is clearly positive, using explicit user feedback to tune confidence thresholds. This prevents low-quality suggestions from eroding trust in the system.

[[more]]
```

第 3 段：

```text
→ Balance timing and context
I’d schedule suggestions around natural pauses in user activity rather than interrupting active tasks. This respects the user’s flow and makes proactive help feel like a seamless assist, not a distraction.

[[more]]
```

第 4 段：

```text
→ Summarize the user-centric approach
This strategy balances utility with restraint by focusing on high-confidence, well-timed suggestions. It ensures proactive features enhance daily life without becoming a source of noise or fatigue.

[[end]]
```

### 19. perf-latency

How do you measure latency for a streaming AI feature?

来源：verified.json（最新重跑）。

区分首包、首个实际渲染、总时长及分位数。

第 1 段：

```text
→ Define latency metrics
I measure Time to First Token for responsiveness, inter-token delay for smoothness, and total duration for completion. I also track end-to-end time from user request to first visible update on the UI.

[[more]]
```

第 2 段：

```text
→ Capture client-side timing
I instrument the Android client to record timestamps at request initiation, first SSE event receipt, and stream completion. This helps isolate network latency from backend processing time.

[[more]]
```

第 3 段：

```text
→ Monitor UI rendering impact
I track how long it takes for the first token to actually render on screen, accounting for main thread blocking or layout passes. This ensures we measure perceived latency, not just network arrival.

[[more]]
```

第 4 段：

```text
→ Aggregate and alert on metrics
I send these timing events to our analytics platform, calculating p50, p95, and p99 for each metric. I set up alerts if the first token latency exceeds a threshold, indicating potential backend or network issues.

[[more]]
```

第 5 段：

```text
→ Correlate with user experience
I link these technical metrics to user satisfaction scores and retention data. This helps us understand if faster streaming actually improves engagement or just reduces drop-offs during long waits.

[[end]]
```

### 20. perf-jank

The chat scrolls smoothly until image analysis and token streaming run together. How do you diagnose it?

来源：verified.json（最新重跑）。

按主线程、布局、状态源和并发逐步定位，具备可执行路径。

第 1 段：

```text
→ Profile main-thread work during streaming
I'd start with Android Studio Profiler and Systrace to isolate whether image analysis or token handling is blocking the main thread. Next, I'll check if Compose recompositions are triggered too frequently by raw deltas. [[more]]
```

第 2 段：

```text
→ Verify delta handling and backpressure
I would check if we are applying backpressure to the token stream so the UI does not get overwhelmed by rapid updates. If image analysis is heavy, I'd ensure it runs off the main thread and only posts complete snapshots or throttled progress. Next, I'll look at layout stability during these concurrent updates. [[more]]
```

第 3 段：

```text
→ Check layout stability and recomposition
I'd verify that image decoding doesn't cause sudden height changes in the chat list, which forces expensive re-layouts. Using fixed aspect ratios or placeholders can stabilize the scroll position while tokens stream in. Next, I'll look at how we handle concurrent state updates. [[more]]
```

第 4 段：

```text
→ Isolate state update sources
I'd check if image metadata and token deltas are updating the same UI state object, causing redundant recompositions. Separating these into distinct flows or using derived state can prevent the scroll from jumping when either updates. Next, I'll verify thread safety for concurrent writes. [[more]]
```

第 5 段：

```text
→ Confirm concurrency safety
I'd ensure that image processing and token streaming use separate coroutines or dispatchers to avoid blocking each other. If they share a mutable list, I'd switch to thread-safe collections or immutable state updates to prevent race conditions. This isolates the bottleneck to either CPU-bound work or main-thread contention. [[more]]
```

第 6 段：

```text
→ Summarize the diagnostic approach
I would start with Profiler to isolate main-thread blocking, then verify that image and token updates do not cause redundant recompositions or layout shifts. Finally, I'd ensure concurrent state writes are thread-safe and throttled. This covers the primary causes of scroll jank in this scenario.
[[end]]
```

### 21. perf-memory

Memory grows after opening and closing the AI conversation ten times. What is your debugging plan?

来源：verified.json（最新重跑）。

区分缓存与泄漏，检查引用链、作用域和无界缓存。

第 1 段：

```text
→ Isolate the leak source
I'll start by confirming if this is a true memory leak or just normal caching growth, using Android Studio Profiler to track heap allocations across those ten open-close cycles. Next, I'd look for retained references from the conversation screen that prevent garbage collection.

[[more]]
```

第 2 段：

```text
→ Check retained references
I'd inspect the heap dump for objects that should have been collected but are still referenced, like static fields or unbound listeners. This helps pinpoint if a singleton or callback is holding onto the conversation view. Next, I'll verify lifecycle handling in the ViewModel and Composable scopes.

[[more]]
```

第 3 段：

```text
→ Verify lifecycle handling
I'd check if the ViewModel is properly scoped to the navigation graph and not leaking into a parent scope. Also, I'd ensure any coroutines or flows started in the UI are cancelled when the composable leaves composition. Next, I'll review resource management for large data structures.

[[more]]
```

第 4 段：

```text
→ Review resource management
I'd check if large AI response buffers or image caches are being cleared when the screen closes. Accumulating these without bounds would explain the steady growth. Next, I'll summarize the debugging approach.

[[more]]
```

第 5 段：

```text
→ Summarize the debugging approach
This plan isolates true leaks from normal caching by checking heap references, lifecycle scopes, and resource cleanup. I'd use Profiler and LeakCanary to confirm the fix before shipping.

[[end]]
```

### 22. perf-anr

An AI-heavy release shows ANRs but no crash spike. How do you investigate?

来源：verified.json（最新重跑）。

诊断先于修复合理，但流式网络本身不等于主线程空闲；OOM 与无崩溃 ANR 混述。

第 1 段：

```text
→ Correlate ANR traces with AI latency spikes
I'd start by checking if the ANRs cluster around specific AI calls or long-running tasks on the main thread. Then I'd look for patterns in the stack traces to see if they're blocked waiting for network responses or heavy computation. Next, I'll examine the timing of these events against our AI service metrics.
[[more]]
```

第 2 段：

```text
→ Analyze main thread blocking causes
I'd inspect whether the AI response parsing or UI updates are happening synchronously on the main thread. Often, large JSON payloads from LLMs can cause significant delay if not processed off-main. Next, I'll check for resource contention like network timeouts or database locks.
[[more]]
```

第 3 段：

```text
→ Check for resource contention and timeouts
I'd look for network timeouts or database locks that might be blocking the main thread while waiting for AI responses. If the app is trying to render complex UI elements synchronously after receiving data, that could also cause ANRs without crashing. Next, I'll examine memory usage patterns during these incidents.
[[more]]
```

第 4 段：

```text
→ Examine memory pressure and GC pauses
I'd check if large AI payloads are causing frequent garbage collection or OutOfMemory errors that stall the main thread. High memory usage can trigger system-level freezes without crashing the app process immediately. Next, I'll verify if we are using strict mode to catch these issues early.
[[more]]
```

第 5 段：

```text
→ Enable StrictMode and profile AI calls
I'd enable StrictMode to catch disk or network access on the main thread during AI response handling. Then I'd use Profiler to trace exactly where the main thread blocks while parsing large payloads. This helps distinguish between slow I/O and heavy computation.
[[more]]
```

第 6 段：

```text
→ Implement streaming and background processing
I'd move to streaming responses via SSE so we can render partial results without waiting for the full payload. This keeps the main thread free by parsing tokens incrementally on a background dispatcher. Finally, I'll add timeouts and fallbacks to prevent indefinite blocking.
[[more]]
```

第 7 段：

```text
→ Add timeouts and fallbacks
I'd enforce strict timeouts on all AI network calls to prevent indefinite blocking. If a request hangs, we should cancel it and show a graceful error or retry option instead of freezing the UI. This ensures the app remains responsive even if the backend is slow.
[[end]]
```

### 23. perf-battery

How do you limit CPU and battery use for proactive AI on a midrange Android phone?

来源：verified.json（最新重跑）。

约束/批量/停止非活跃工作合理；缺结束标记，答案只有一段。

第 1 段：

```text
→ Bound background work and power usage
I would run proactive AI on WorkManager with battery, network, and idle constraints instead of keeping a service alive. I’d also use JobScheduler or WorkManager deferrable jobs for non-urgent tasks, batch them, and stop work when the user is inactive. For heavy inference, I’d prefer on-device models only when supported and fall back to server processing to avoid sustained CPU load.
```

### 24. data-offline

Design local storage and synchronization for offline messages and AI partial results.

来源：verified.json（最新重跑）。

Room/服务端幂等合理；UI 应显示持续累积快照，VM 也不是持久 worker。

第 1 段：

```text
→ Define the local source of truth
I would make Room the single source of truth for messages and AI results, with the UI observing its Flow. Network updates should write to Room rather than bypassing it. Next I will outline how offline sends are handled. [[more]]
```

第 2 段：

```text
→ Handle offline message sending
I would insert the message into Room with a pending status and let the UI observe it immediately. A durable worker in the repository or ViewModel would attempt the network send when connectivity returns. Next I will address AI partial results. [[more]]
```

第 3 段：

```text
→ Store AI partial results safely
I would persist raw token deltas in Room to avoid data loss, but only render complete snapshots to the UI. If the stream supports a cursor, I can resume from that point after a disconnect. Next I will discuss deduplication and delivery guarantees. [[more]]
```

第 4 段：

```text
→ Handle deduplication and delivery guarantees
I would rely on a server contract for idempotency keys to handle duplicates, since local deduplication alone does not guarantee exactly-once delivery. This ensures that retries from the durable worker do not create duplicate messages or AI responses. Next I will summarize the reliability tradeoffs. [[more]]
```

第 5 段：

```text
→ Summarize the reliability tradeoff
This design prioritizes data integrity by persisting raw deltas and using server-side idempotency for delivery guarantees. It accepts slight complexity in managing partial states to ensure users never lose context during offline or flaky network conditions.
[[end]]
```

### 25. data-choice

When would you choose SQL versus noSQL for a mobile communication app?

来源：verified.json（最新重跑）。

关系/事务/模式演进合理；SQL/Room 不自动提供跨端冲突解决，JSON 也可直接存 SQL。

第 1 段：

```text
→ Clarify the data model
I'd choose SQL when relationships and transactions matter, like users, chats, and read receipts. NoSQL fits better for flexible, unstructured payloads such as AI-generated content or logs. Next, I'll discuss how sync complexity influences that choice.
[[more]]
```

第 2 段：

```text
→ Address sync complexity
For offline-first messaging, SQL databases like Room handle local transactions and conflict resolution more reliably. NoSQL often pushes that logic to the app layer, increasing bug risk during network interruptions. I'd lean toward SQL for core chat data to keep state consistent. Next, I'll cover when NoSQL makes sense for AI payloads.
[[more]]
```

第 3 段：

```text
→ Cover NoSQL for AI payloads
NoSQL works well for flexible AI-generated content, like streaming responses or unstructured logs. It avoids rigid schema migrations when the data shape evolves rapidly. I'd store these as JSON blobs alongside the core SQL chat tables. Next, I'll summarize the hybrid approach.
[[more]]
```

第 4 段：

```text
→ Summarize the hybrid approach
I'd use SQL for core chat state to ensure transactional integrity and reliable sync. NoSQL handles flexible AI payloads where schema evolution is frequent. This hybrid model balances consistency with agility. I'm ready for your next question.
[[end]]
```

### 26. background-send

How do you reliably send a queued message after the app leaves the foreground?

来源：verified.json（最新重跑）。

持久队列和幂等正确；队列满时丢弃旧的未发送消息不可接受，应背压并显式告知用户。

第 1 段：

```text
→ Clarify the queueing and retry mechanism
I would use a WorkManager one-time request with constraints to handle network availability, ensuring the message is persisted before the app leaves the foreground. The worker would read from a local Room database queue, attempt the send, and remove it on success or retry on failure. This decouples the sending logic from the UI lifecycle.

[[more]]
```

第 2 段：

```text
→ Handle idempotency and duplicate prevention
I would attach a unique client-generated ID to each message so the server can deduplicate retries. This ensures that if the app crashes mid-send or the network flaps, we do not deliver the same message twice. Next, I will discuss how to manage backpressure for high-volume queues.

[[more]]
```

第 3 段：

```text
→ Manage backpressure and queue limits
I would cap the local Room queue size to prevent storage exhaustion on low-end devices. If the limit is hit, we drop the oldest non-critical messages or prompt the user to clear history. This keeps the app responsive while preserving priority data.

[[more]]
```

第 4 段：

```text
→ Summarize the reliability tradeoff
This approach ensures messages survive app termination and network drops via persistent storage and WorkManager. I would add exponential backoff for retries to respect server rate limits. Finally, I'd test process death and weak network conditions before shipping.
[[end]]
```

### 27. tflite-integration

How would you integrate a lightweight TensorFlow Lite model for on-device message classification?

来源：verified.json（最新重跑）。

应以模型签名确定 dtype/tokenizer，不能泛化为 float 数组；缺 interpreter 生命周期和线程安全细节。

第 1 段：

```text
→ Clarify the model's input format
I need to know if the classifier expects raw text tokens or pre-processed embeddings. This determines whether I handle tokenization in Kotlin or pass strings directly to TF Lite.

[[more]]
```

第 2 段：

```text
→ Design the inference pipeline
I would load the model once in a background coroutine using Interpreter API. Input text gets tokenized, converted to float arrays, and passed to the interpreter for prediction.

[[more]]
```

第 3 段：

```text
→ Handle model updates and fallbacks
I’d bundle the initial .tflite file for offline use but check for remote updates on startup. If inference fails or times out, I’d fall back to a server-side classifier to ensure no message is dropped.

[[more]]
```

第 4 段：

```text
→ Summarize the integration tradeoff
This approach keeps latency low by running inference on-device while using server fallback for reliability. I’d monitor model accuracy and memory usage to tune the quantization level before shipping.

[[end]]
```

### 28. tflite-quant

Would an int8 model always be faster and accurate enough on every Android device?

来源：verified.json（最新重跑）。

承认依设备和精度验证；开头“Int8 is faster”仍过强，不能作为普遍结论。

第 1 段：

```text
→ Clarify the device constraints
Int8 is faster and smaller than FP16, but it is not universally optimal. Accuracy depends on whether the model quantizes cleanly without significant loss. Next, I will discuss how low-end devices handle this tradeoff.
[[more]]
```

第 2 段：

```text
→ Address low-end device limitations
On low-end devices, the main constraint is often memory bandwidth and thermal throttling rather than raw compute speed. Int8 helps reduce model size, but if the device lacks efficient NPU support for that precision, CPU execution might not yield significant latency gains. I would next look at how we handle accuracy degradation in these scenarios.
[[more]]
```

第 3 段：

```text
→ Mitigate accuracy loss with validation
We must validate quantized outputs against a baseline to catch drift, especially in critical tasks like intent recognition. If accuracy drops below threshold, we can fallback to cloud processing or use mixed precision for sensitive layers. This ensures reliability without sacrificing speed on capable devices.
[[more]]
```

第 4 段：

```text
→ Summarize the device-agnostic strategy
Int8 is a strong default for efficiency, but it requires per-device validation and fallbacks. We balance speed with accuracy by testing on target hardware and switching to cloud or mixed precision when needed. This ensures consistent performance across diverse Android devices.
[[end]]
```

### 29. mlkit-choice

When would you use ML Kit, a custom TensorFlow Lite model, or a backend API for vision?

来源：verified.json（最新重跑）。

标准任务/自定义模型/云端区分清楚；具体 ML Kit 模型更新策略需按 API 区分。

第 1 段：

```text
→ Define the decision criteria
I'd pick ML Kit for standard tasks like text or face detection to save time. I'd use a custom TFLite model when we need specific on-device accuracy or privacy without network dependency. For complex vision that exceeds mobile capabilities, I'd route it to a backend API. Next, I'll detail the trade-offs for each choice.
[[more]]
```

第 2 段：

```text
→ Detail ML Kit trade-offs
ML Kit is ideal for rapid prototyping and standard tasks like OCR or barcode scanning. It handles model updates automatically, reducing maintenance overhead. However, it offers less control over custom logic or specialized accuracy needs compared to a bespoke TFLite model. Next, I'll explain when to choose a custom TFLite model.
[[more]]
```

第 3 段：

```text
→ Explain custom TFLite model trade-offs
I'd choose a custom TFLite model when we need specific accuracy for unique objects or strict privacy. It runs entirely on-device, avoiding network latency and data transmission costs. However, it requires managing model updates and optimizing for different hardware constraints. Next, I'll cover when to use a backend API.
[[more]]
```

第 4 段：

```text
→ Explain backend API trade-offs
I'd use a backend API for complex vision tasks that require heavy computation or large models. This offloads processing from the device, ensuring consistent performance regardless of hardware capabilities. However, it introduces network latency and dependency on connectivity, which we must handle with robust fallbacks. Next, I'll summarize the decision framework.
[[more]]
```

第 5 段：

```text
→ Summarize the decision framework
I'd pick ML Kit for speed, TFLite for custom on-device needs, and backend APIs for heavy computation. This balances development effort, privacy, and performance across different use cases.
[[end]]
```

### 30. model-rollout

How do you safely update an on-device model in production?

来源：final.json（较早版本；最新重跑失败）。

签名、临时文件、原子替换、旧版回退和分批监测合理。此题仅有较早版本结果。

第 1 段：

```text
→ Clarify model update scope
Are we talking about replacing the entire model file, or just updating its weights and configuration? Next, I'll outline the safe rollout strategy.
[[more]]
```

第 2 段：

```text
→ Define the rollout strategy
I'd use a phased rollout with feature flags, starting with internal testers before expanding to small user groups. This lets us monitor crash rates and performance metrics closely at each stage. Next, I'll explain how we handle downloads and validation.
[[more]]
```

第 3 段：

```text
→ Handle download and validation
I'd download the new model to a temporary directory, verify its checksum and signature, then atomically swap it into place. If validation fails or the app crashes on load, we keep the previous stable version as a fallback. Next, I'll cover how we manage memory during the transition.
[[more]]
```

第 4 段：

```text
→ Manage memory during transition
I'd unload the old model from memory before loading the new one to avoid OOM crashes on low-end devices. We can use a background thread for this swap so the UI stays responsive. Next, I'll summarize the key safety checks.
[[more]]
```

第 5 段：

```text
→ Summarize the safety tradeoff
This approach balances rapid iteration with production stability by isolating failures and enabling instant rollbacks. I'd monitor inference latency and accuracy alongside crash rates to catch silent regressions.
[[end]]
```

最新失败：`transport or server failure (details redacted)`。

### 31. security-client

How would you protect AI credentials, access tokens, and communication data on Android?

来源：final.json（较早版本；最新重跑失败）。

provider secret 留后端，用户凭证设备安全存储；旧答案把 provider secret 放客户端。此题仅有较早版本结果。

第 1 段：

```text
→ Define the security boundaries for credentials and data.
I would keep AI provider secrets on a secure backend, never in the Android app or client-side code. For user access tokens and sensitive communication data, I'd use Android Keystore with EncryptedSharedPreferences, enforce TLS, and avoid storing raw prompts or responses in plaintext logs or local databases unless strictly necessary and encrypted. [[end]]
```

最新失败：`transport or server failure (details redacted)`。

### 32. analytics-eval

What analytics and feedback would you add to iterate on a nondeterministic AI chat feature?

来源：final.json（较早版本；最新重跑失败）。

技术/质量/采用指标都有；记录检索片段和 response 应补脱敏、授权和保留边界。此题仅有较早版本结果。

第 1 段：

```text
→ Define the core metrics
I'd track latency, token usage, and fallback rates for technical health. For quality, I'd measure user thumbs up/down, re-prompt frequency, and task completion success. This helps distinguish between model errors and UX friction. [[more]]
```

第 2 段：

```text
→ Capture context for debugging
I'd log the prompt version, retrieved chunks, and model parameters alongside each response. This lets us replay failures in our evaluation pipeline to see if the issue was retrieval or generation. It also helps isolate regressions when we update prompts. [[more]]
```

第 3 段：

```text
→ Monitor user retention signals
I'd correlate chat engagement with session length and return rates to spot long-term value. If users drop off after the first turn, it often means the initial response was irrelevant or too slow. This helps prioritize UX fixes over pure model tuning. [[end]]
```

最新失败：`transport or server failure (details redacted)`。

### 33. testing-ai

How would you test streaming, cancellation, retries, and nondeterministic responses before release?

来源：final.json（较早版本；最新重跑失败）。

覆盖可控流/取消/弱网；取消应保留已生成内容，不能笼统要求 UI 无 partial。有一段计划台词同行。较早结果。

第 1 段：

```text
→ Define test scenarios for streaming, cancellation, retries, and non-determinism.
I'd start by outlining key test cases: verifying partial data rendering during streams, ensuring clean cancellation without resource leaks, confirming retry logic handles transient failures, and checking that non-deterministic responses don't break UI state or cause crashes. Next, I'll detail how to simulate these conditions in tests.
[[more]]
```

第 2 段：

```text
→ Implement deterministic mocks for streaming and failures I'd use mock servers to emit controlled SSE chunks, simulate network drops, and trigger specific error codes. This lets me verify retry backoff logic and ensure the UI handles partial updates without crashing or duplicating content. Next, I'll address testing cancellation and resource cleanup.
[[more]]
```

第 3 段：

```text
→ Verify cancellation and resource cleanup
I'd trigger cancellations mid-stream and assert that sockets close, coroutines stop, and no partial data persists in the UI. This prevents memory leaks and ensures the app returns to a stable idle state immediately. Next, I'll cover strategies for handling non-deterministic responses.
[[more]]
```

第 4 段：

```text
→ Test non-deterministic responses with schema validation
I'd run property-based tests to ensure the UI handles varied LLM outputs without crashing. Schema validation checks for required fields and types, while fallbacks manage malformed or unexpected data structures gracefully. Next, I'll outline integration testing for end-to-end reliability.
[[more]]
```

第 5 段：

```text
→ Validate end-to-end reliability with real-world scenarios
I'd run integration tests using actual backend endpoints to verify the full flow from request to rendered card. This ensures our mocks align with production behavior, especially for edge cases like rate limits or partial failures. Finally, I'll summarize the release checklist.
[[more]]
```

第 6 段：

```text
→ Summarize the release checklist
I'd gate the release on passing all these automated suites, plus manual QA for visual regressions. We'd also monitor crash-free rates and error logs in staging before pushing to production. This ensures we catch subtle issues that unit tests might miss.
[[end]]
```

最新失败：`transport or server failure (details redacted)`。

### 34. play-release

Describe an app you published on Google Play and how you handled rollout and production incidents.

来源：verified.json（最新重跑）。

明确没有经确认的 Google Play 上架经历，未伪造；计划台词同行且缺结束标记。

第 1 段：

```text
→ Clarify the publication status of my projects I don't have a confirmed record of publishing an app on Google Play. My resume lists FlutterDouBan as an open-source project and CabinetAI as a personal initiative, but neither establishes a public store release. I can instead describe how I handled production incidents and rollouts in my professional roles at Debon Securities or Kezhi if that works for you.
[[end]]
```

### 35. ownership

In a small team, how would you ship the first reliable AI communication flow with backend and ML engineers?

来源：final.json（较早版本；最新重跑失败）。

有最小闭环/后端校验，但 token 恢复未明确限定协议支持，且计划同行。较早结果。

第 1 段：

```text
→ Define the MVP scope
I would start by defining a minimal end-to-end flow, like sending a text message and receiving a streamed AI response. We need to agree on the contract between the client, backend, and ML services first. Next, I'll outline how we handle streaming data reliably on Android.
[[more]]
```

第 2 段：

```text
→ Establish streaming and fallbacks
I'd implement SSE or WebSockets for partial responses, ensuring the UI updates incrementally without blocking. We must handle network drops by resuming from the last token or retrying safely. Next, I'll cover how we validate AI outputs before showing them.
[[more]]
```

第 3 段：

```text
→ Validate outputs and monitor I’d add schema validation and business rule checks on the backend before sending data to the client. We need a configuration-review pipeline with prompt versions and regression tests to catch drift. Finally, I’ll summarize the tradeoffs for this small team setup.
[[more]]
```

第 4 段：

```text
→ Summarize the reliability tradeoff
This approach gives us immediate local feedback and retryable delivery while keeping AI outputs safe. I’d test duplicate sends, process death, and reconnects before extending the MVP.
[[end]]
```

最新失败：`transport or server failure (details redacted)`。

### 36. context-recall

What first-visible-token target did we agree earlier in this practice interview?

来源：final.json（较早版本；最新重跑失败）。

旧 Gemma 收到包含 850 ms 约定的 context；新链路旧评测遗漏 context。不可据此比较记忆能力或计入技术均分；重跑已修复输入但被服务权限错误阻挡。

第 1 段：

```text
→ Clarify the missing baseline
I don't have a record of us agreeing on a specific first-visible-token target earlier in this conversation. Could you clarify what range or benchmark you had in mind so we can align on it? [[more]]
```

第 2 段：

```text
→ Propose a realistic target
For a voice-and-text app, I'd aim for under 500ms to first token on good networks. This balances perceived responsiveness with the complexity of our AI pipeline and network variability. [[end]]
```

最新失败：`transport or server failure (details redacted)`。


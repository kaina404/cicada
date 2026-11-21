# 本地实时同传 + 声音克隆：open-realtime-translate 源码分析与 M4 Pro 方案

2026-11-20。依据：`JacobLinCool/open-realtime-translate` 最新提交 `3bbf77c`（2026-05-20）全部 `ort/` 源码；本机 `~/.cicada-mlx` 中 mlx-audio 0.6.4 的 Qwen3-TTS / Qwen3-ASR 源码；本机 2026-11-17 实测（`~/Downloads/cicada-asr-lab-20261117`，M4 Pro 48GB）；Cicada 现有代码。

标注：✅ 读源码或本机实测确认；⚠️ 推算，未在本机实测。

---

## 0. 结论先行

1. **ORT 不是同传架构，是“按停顿切段的串行批处理”**。三个模型跑在同一条推理线程上，逐段 ASR→MT→TTS，全部做完才吐第一包音频；连续讲话时延迟会单调累积。✅
2. **ORT 没有 LICENSE 文件**（GitHub `license: null`，6 star，3 个提交，最后推送 2026-05-19）。默认保留所有权利，**代码不能直接搬进产品**，只能当参考实现和测速工具。✅
3. 你粘贴的方案里有几处和源码不符：增量模式静音提交阈值是 **700ms**（不是 300ms），最长提交是 **8000ms**（不是 3500ms）；“VAD”只是 RMS 能量阈值 0.012；TTS 不是流式输出。✅
4. **Cicada 已经有这套系统的 2/3**：流式 Qwen3-ASR 1.7B + Hy-MT2 1.8B 的 MLX worker（`Resources/coach/mlx_listen_worker.py`，本机实测跟得上实时）、Silero VAD、Kokoro 常驻 worker、`voice/reference.wav` 声音样本、右 ⌥ 说话 → BlackHole 虚拟麦克风。缺的只是“本机克隆音色的流式 TTS”。✅
5. **推荐方案**：不接 ORT 服务；在 Cicada 现有 worker 模式上加一个 **Qwen3-TTS 0.6B/1.7B Base 流式克隆 worker**，用**固定声音档案**（而不是 ORT 的滚动参考）以命中缓存；ASR/MT/TTS 分进程并行；加积压控制器。预计“说完一个分句 → 对方听到英文”约 **1.2–1.8s** ⚠️，需要实测确认。

---

## 1. 逐题回答

### Q1 架构是否适合实时同传？ — 不适合 ✅

源码事实（`ort/session.py`、`ort/inference.py`、`ort/pipeline/segmentation.py`）：

| 环节 | 实际实现 |
|---|---|
| 切段 | 30ms 帧 RMS ≥ 0.012 算有声；有声后连续静音 700ms 或累计 8s 才提交一段 |
| 推理线程 | 全进程 `ThreadPoolExecutor(max_workers=1)`，ASR/MT/TTS 和模型加载共用一条线程（MLX 线程亲和问题的绕法） |
| 段内顺序 | `_process()`：ASR 整段 → MT 整段 → TTS 整段合成完 → 才开始 `_emit_audio` |
| 段间 | `handle()` 里 `await _drain()`，WebSocket 接收循环被推理阻塞；WebRTC 的 `feed_audio` 同样被 await 住 |
| 回放 | 音频按 100ms 切块但**不按墙钟节流**一次性发出；靠 1.25 倍变速（WSOLA）追赶 |

作者自己在 `_drain` 注释里写明：延迟收益来自“把长句切小”，**不是任务级并行**。README 也承认长句跨分句语序调整会碎片化。

所以它是“短句级交替传译”，不是同声传译。

### Q2 M4 Pro 48GB 实际速度 ⚠️（部分有本机实测）

本机已有实测（2026-11-17，M4 Pro）✅：
- Qwen3-ASR 1.7B 8bit 流式，每 1s 解码、30s 窗口：块落后 P50 0.23s / P95 0.37s，无单次 >1s。
- Hy-MT2 1.8B 8bit（英→中）：单次翻译 P50 0.18–0.30s。

未实测，按带宽推算（M4 Pro 273GB/s vs M5 Pro 约 307GB/s，解码基本受带宽限制）⚠️：
- ORT 默认栈单段：ASR ≈0.2s、TranslateGemma-4B-4bit ≈0.6s、Qwen3-TTS-1.7B ≈2.3s（RTF 0.37–0.70），合计 ≈3.1s/段。
- 端到端首音 = 段时长 + 700ms 静音等待 + ≈3.1s。讲一句 3s 的话，开口后约 **6.8s** 对方才听到第一个英文音节；从停顿算起约 **3.8s**。

### Q3 是否真流式？ — 全部是分段批处理 ✅

- ASR：`generate_transcription` 先把段写成临时 WAV 再整段识别。mlx-audio 0.6.4 其实有 `stream_transcribe` / `stream_generate`，ORT 没用。
- MT：`mlx_lm.generate` 整段生成（`max_tokens=256`），不流式。
- TTS：`model.generate(...)` 未传 `stream=True`，把所有块 `concatenate` 后才返回。mlx-audio 0.6.4 的 Qwen3-TTS **支持** `stream=True` + `streaming_interval`（12.5Hz codec，0.48s ≈ 6 个 token 一包），ORT 没用。

### Q4 三模型流水线并行？ — ORT 不能；架构上能 ✅

ORT 的单线程执行器使并行不可能。正确做法是 Cicada 已验证过的：**每个模型一个独立进程**，各自 Metal 上下文、各自线程。`mlx_listen_worker.py` 把 Hy-MT2 放到独立进程后，“翻译不会拖住下一块解码，两者都跟得上实时”（2026-11-17 实测）。

GPU 仍是同一块，三者交错提交 command buffer，会互相抢带宽，但 ASR（每秒一次短 prefill）和 MT（一次 0.2s）占空比都低，主要负载是 TTS 解码。

### Q5 首段延迟压到 2s 以内 ⚠️

目标定义：**分句结束 → 对方听到第一个英文音节**。预算：

| 步骤 | 做法 | 预算 |
|---|---|---|
| 分句判定 | Silero VAD + 流式 ASR 草稿；遇到 `，。？` 或 350ms 停顿即提交稳定前缀；最长 4s 强切 | 0.35s |
| ASR 收尾 | 流式 ASR 只需解最后一块 | 0.26s（实测 final_tail） |
| MT | Hy-MT2 1.8B 带 3–4 句上下文，**流式出 token**，攒到第一个英文分句就交 TTS | 0.2–0.3s |
| TTS 首包 | Qwen3-TTS `stream=True`，`streaming_interval≈0.4`，参考音编码已缓存 | 0.4–0.7s |
| 输出 | 写 BlackHole，按墙钟节流 | <0.05s |
| 合计 | | **≈1.3–1.7s** |

关键不在模型更快，而在三件事：流式 TTS 首包、缓存参考编码、提交阈值从 700ms 降到 ~350ms。

### Q6 更快且质量相当的克隆模型？

| 模型 | 流式 | 克隆 | 授权 | 判断 |
|---|---|---|---|---|
| Qwen3-TTS 1.7B Base | 是（mlx-audio） | 零样本 ICL，跨语种好 | Apache-2.0 | **基线** |
| Qwen3-TTS 0.6B Base | 是 | 同上，略差 | Apache-2.0 | **首选测速对象**，同管线直接换 |
| CosyVoice 2/3 | 双向流式（文本也可流入） | 零样本，中英强 | Apache-2.0 | 架构最适合同传，但 MLX 移植不成熟 ⚠️ |
| VoxCPM / VoxCPM2 | 是 | 零样本 | Apache-2.0 | mlx-audio 0.6.4 已有 `voxcpm2` 目录，值得同台测 |
| OmniVoice / MOSS-TTS | 视实现 | 零样本 | 需逐个核对 | mlx-audio 已收录，候选 |
| Kokoro + OpenVoice v2 音色转换 | Kokoro 快（RTF≈0.1） | 转换器做音色 | Apache-2.0 / MIT | 最快路线，相似度明显低于 ICL ⚠️ |
| F5-TTS / Fish-Speech / Spark-TTS / Seamless | — | — | 权重**非商用** | 产品化排除 |

结论：先在同一管线比 **Qwen3-TTS 0.6B vs 1.7B vs VoxCPM2** 的首包、RTF、相似度，再决定；没有本机数据前不换。

### Q7 能否缓存 Speaker Embedding / 参考编码？ — 能，但 ORT 的做法让缓存永远失效 ✅

mlx-audio 0.6.4 `qwen3_tts.py`：
- `_prepare_icl_generation_inputs` 有 `_icl_cache`，键 = `(ref_text, (ref_audio.size, ref_audio.sum()))`，缓存参考音频的 codec 编码 `ref_codes` 和文本 token。
- `extract_speaker_embedding` **每次都重算**，没缓存。

ORT 的问题：滚动参考缓冲每段都追加新音频 → 键每次都变 → `_icl_cache` 100% 未命中；还每次写临时 WAV 再读回。

做法：
1. **固定声音档案**：复用 Cicada 已有的 `voice/reference.wav` + `reference.txt`（≤30s，裁到 8–12s 干净片段），会议开始时预热一次。
2. 给 speaker embedding 加一层 memo（按档案 id），在 worker 里包装，不改 mlx-audio。
3. 参考音直接以 `mx.array` 传入，不走临时文件。
4. 再往前一步：把 ICL 前缀（参考 codec + 参考文本）的 **KV cache 预填一次**、每句复用，可省掉每句的长前缀 prefill；需要改 mlx-audio 的生成循环 ⚠️。

滚动参考还有质量风险：会把回声、噪声、别人的声音卷进参考。动态参考只适合“没有录过样本”的兜底。

### Q8 优化 MLX GPU 调度、减少竞争

- 分进程（见 Q4）；进程启动即 `mx.eval(model.parameters())` 常驻，设 `mx.set_wired_limit` 防止被换出。
- 优先级：TTS 正在出声时，MT 只处理下一句；ASR 解码间隔从 1s 拉到 1.5s 可接受（只影响草稿，不影响最终分句）。
- 量化：ASR 8bit、MT 8bit（1.8B 才 1.8GB）、TTS 8bit；总驻留 ≈6–8GB，48GB 无压力，**内存不是瓶颈，带宽是**。
- 不要同时常驻 Gemma E4B 面试教练 + 同传全套又同时推理：两者都是带宽大户。同传期间暂停教练的大模型调用或错峰。

### Q9 连续讲话不累积延迟

ORT 必然累积：处理 ≈3s/段 > 段长时，队列只增不减；英文语音比中文长约 1.5 倍，1.25 倍变速后仍 >1，**光播放就跑不赢实时**。

需要一个**积压控制器**（输出侧排队秒数 = 已合成未播放 + 待合成预估）：

| 积压 | 动作 |
|---|---|
| < 1.5s | 正常 1.0–1.1 倍速 |
| 1.5–3s | 变速到 1.25；MT 提示改“简洁口译”风格，删口头禅和重复 |
| 3–5s | 合并待译分句一次翻译（压缩），丢掉已过时的草稿 |
| > 5s | 只出字幕不出声，直到追上；**绝不播放未翻译原文**（Cicada 硬规则） |

另外：说话端是 push-to-talk（右 ⌥），用户松键本身就是强分句信号，比 VAD 可靠。

### Q10 真正的双向全双工

两条独立链路，共享 GPU：
- **出向**（我→对方）：麦克风 → 中→英 → 克隆 TTS → BlackHole → 会议软件麦克风。
- **入向**（对方→我）：Core Audio process tap 抓会议音频 → 英→中 → **字幕**（Cicada 现有听功能）。入向默认不出声；要出声只能走耳机，否则会被麦克风收回去。

两条链路不会自激：出向写 BlackHole 不经过扬声器；入向 process tap 可排除 Cicada 自身输出。

### Q11 多人、重叠、回声、打断

- 出向只认自己：push-to-talk + 可选 SpeakerID（`SpeakerID.swift` 已有）过滤别人的声音进入麦克风。
- 外放场景回声：麦克风开启 `AVAudioEngine` voice processing（系统 AEC），或复用 Cicada 的 `EchoGate`/`EchoMatch`。
- 打断：入向检测到对方开口且出向正在播放 → 200ms 淡出、清空待播队列、字幕保留（对方打断你说明他不需要后半句）。
- 重叠：入向用 SpeakerID 分人出字幕；重叠段只保证主讲人，不做分离（成本高、收益低）。

### Q12 TranslateGemma 是否最佳本地实时翻译？ — 对同传不是 ⚠️

- 4B-4bit 单次约 0.5–0.6s，且 ORT 不流式。
- Hy-MT2 1.8B 8bit 本机实测 0.18–0.30s（英→中），Apache-2.0，已在 Cicada 里跑。中→英方向**尚未在本机测过质量**。
- 建议：同一组中文口语样本（面试回答）同台比 Hy-MT2 1.8B / TranslateGemma 4B / Gemma 4 E4B（已在本机缓存），看延迟与人工评分。没测之前不下结论。

### Q13 Hy-SimulMT 能否替换 ASR+MT？ ⚠️

Hy-SimulMT 是“同传式文本翻译”（读到一部分源文就开始输出），本身不吃音频，**替换不了 ASR**，只能替换 MT 并把“等分句”改成“边读边译”。价值在于减少分句等待；代价是输出会更碎、需要 TTS 能接受短片段。它的 MLX 可用性、授权需要先核实（我没在本次读到它的源码）。Cicada 现有 Hy-MT2 已足够快，**优先级低于流式 TTS**。

### Q14 有没有更好的端到端开源方案？ — 目前没有适合中英+克隆+Mac 的 ⚠️

- SeamlessStreaming / Expressive：权重非商用，中文和音色保持一般。
- Hibiki / Hibiki-Zero：不支持中文。
- Qwen3-LiveTranslate：商业 API，不是开放权重。
- StreamSpeech 等研究模型：无克隆、无 MLX。

级联（流式 ASR → 流式 MT → 流式克隆 TTS）仍是 Mac 本地的最优解，且每段可单独替换、单独测。

### Q15 如何稳定集成到 macOS 原生应用

**不要接 ORT 的 FastAPI/WebSocket 服务**，按 Cicada 已有的模式做：
- Python 子进程常驻在 `~/.cicada-mlx`，stdin/stdout JSON lines（和 `mlx_listen_worker.py`、`kokoro_worker.py` 一致），文本只走私有管道、不落日志。
- 会议开始时异步预热（加载 + 用声音档案合成一句短文本不播放）——与 Kokoro 必须提前预热的规则一致。
- Swift 侧：引擎状态 `@MainActor`，音频回调把 PCM 交给 `AudioRouter` 队列；TTS PCM 流按墙钟写入 BlackHole（`VirtualMic.swift`）。
- Worker 崩溃：`Watchdog` 重启 + 当前句降级为字幕-only，不卡说话键。
- 归属：`SpeakEngine` 新增一种“本机克隆”语音来源，和 Ming（云端克隆）、Kokoro、系统语音并列；`Voices.swift` 的 `.clone` 现在只走 Ling，需要加本机分支。

### Q16 商业授权

| 组件 | 授权 | 产品化 |
|---|---|---|
| open-realtime-translate 代码 | **无 LICENSE** | ❌ 不能复制代码；思路可参考 |
| Qwen3-ASR 1.7B/0.6B | Apache-2.0 | ✅ 保留声明 |
| Qwen3-TTS Base | Apache-2.0 | ✅ |
| Hy-MT2 1.8B | Apache-2.0（本机 model-info 确认） | ✅ |
| TranslateGemma | Gemma Terms of Use | ⚠️ 可商用但带使用政策与再分发条件 |
| mlx / mlx-lm / mlx-audio | MIT | ✅ |
| Silero VAD | MIT | ✅ |
| BlackHole | GPL | ✅ 前提：不打包，下载并校验 SHA-256（Cicada 现规则） |
| Seamless / F5 / Fish / Spark | 非商用 | ❌ |

另一个非授权的风险：**克隆本人声音冒充本人说英文**用于面试，部分平台/雇主可能视为不诚实或违反规则；自用前自行判断。

---

## 2. 推荐方案（M4 Pro 48GB）

```
右⌥按住 → 麦克风(voice processing) → Silero VAD
   → [进程A] Qwen3-ASR 1.7B 8bit 流式（1s 解码，草稿+稳定前缀）       已有
   → 分句器：标点 / 350ms 停顿 / 松键 / 4s 强切
   → [进程B] Hy-MT2 1.8B 8bit 中→英，3–4 句上下文，流式 token      已有（需加中→英）
   → [进程C] Qwen3-TTS 0.6B/1.7B Base 8bit，stream=True，固定声音档案   新增
   → 积压控制器（变速 / 压缩 / 降级字幕）
   → BlackHole 2ch → Zoom / Teams / Meet / 腾讯会议                  已有
入向：process tap → 现有听功能 英→中字幕
```

落地顺序（每步可单独验证）：
1. **测速脚本**（只在 scratch，不进产品）：同一组中文面试回答，测 Qwen3-TTS 0.6B/1.7B 流式首包、RTF、相似度，命中/不命中 ICL 缓存各一次。→ 拿到真实 M4 Pro 数字再定模型。
2. `local_clone_worker.py`：常驻、预热、固定档案、流式 PCM 回传。
3. `SpeakEngine` 接入本机克隆语音来源 + 积压控制器。
4. Hy-MT2 中→英质量对比（vs TranslateGemma / Gemma 4 E4B）。
5. 打断与回声。

## 3. 对照：Qwen3.8-LiveTranslate（云端）

来源：阿里云百炼模型页与 live-translator 客户端/服务端事件文档、Qwen 发布公告、MindStudio 实测（2026-09）。

- 端到端模型（thinker 流式出原文+译文，talker 出语音，文本与语音交错输出）。官方平均滞后 LAAL 2.3s（上一代 2.8s），厂商自测数字。60 种源语言，29 种有语音输出；中英是否都能出语音，文档没逐条列出（大概率能，需实测）。
- 音色复刻：`enable_voice_clone` + `voice_clone_options.frequency` = `once`（开场复刻一次，单人）/ `always`（每次输出前复刻，多人）/ `never`（用预先复刻的音色 ID）。复刻不额外收费。
- 协议：WebSocket / WebRTC，`wss://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime`；事件风格近似 OpenAI Realtime 但未声明兼容（`speaker_detection` 轮次、`session.finish` 等是私有的）。输入 PCM/Opus 16kHz，输出 PCM 24kHz；可附 JPG 画面（≤2 张/秒）；热词表 `translation.corpus.phrases`。
- 价格（北京）：音频输入 ¥40、音频输出 ¥160 /百万 Token；输入 7 Token/秒、输出 12.5 Token/秒 → 约 ¥1/小时输入 + 每小时译音输出 ¥7.2，开着整场 1 小时一般 ¥3–8。限流 RPM 10。
- 第三方实测问题：判断说完时机不稳，长段连续讲话会中途断掉或落后再追；打断处理不符合预期。中英未在该测评里测。
- 没有开源权重，没写数据保存政策；声音和内容要上阿里云。
- Cicada 已有百炼实时 WebSocket 客户端（`RealtimeClient.swift`，同样的 workspace/region 地址，默认 `qwen3.8-omni-flash-realtime`），接入它主要是换模型和 session 参数。

对比本地方案：云端 LAAL 2.3s 是“整体平均滞后”，本地方案的 1.3–1.7s 是“分句结束到首音”，两者口径不同，不能直接比；要比只能用同一段中文音频两边各测一遍。

## 4. 未验证项

- M4 Pro 上 Qwen3-TTS 任何数字（模型尚未下载）。
- Hy-MT2 中→英质量。
- 三进程同时推理时的 GPU 带宽竞争实际影响。
- Hy-SimulMT 的授权与 MLX 可用性。

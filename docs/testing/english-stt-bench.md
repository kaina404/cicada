# 英文 STT 引擎对比测试：准确度 + 流式翻译速度

这份文档给执行测试的 AI 用。测试要回答一个问题：**Cicada 的英文识别要不要从 Apple SpeechAnalyzer 换成别的引擎？** 只看两件事：英文识别准不准，以及从"对方说完"到"中文译文出现"有多快。

## 0. 硬约束（先读）

- **只在 Mac 上跑**（Apple M4 Pro / 48 GB，macOS 26）。**不改 Cicada 仓库里 app 的代码**（`Sources/`、`Package.swift`）。
- **测试代码放在仓库外。** 沿用用户现有的实验目录 `/Users/xiaohui/Downloads/cicada-asr-lab-20261117`（下文简称 `LAB`），用它的 `.venv`（Python 3.14，已经装了 mlx 0.32.4、mlx-qwen3-asr 0.4.4、jiwer 4.0）。新的工作放进 `LAB/bench/`。回仓库的只有报告：`docs/testing/runs/stt-bench-<YYYY-MM-DD>/`。
- **音频来源**只能是合成音频、公开数据集，以及用户本人同意提供的录音。不能用真实会议录音。
- **下载**任何新模型或数据集之前，先把文件名、来源、大小和许可证列给用户，等用户确认。下载完记下 SHA-256，写进 `LAB/bench/models.lock.json`。
- **切换系统输出到 BlackHole 时**沿用 `stt-30min/run_stt.py` 的做法：先用 `audio-control snapshot` 保存当前设置，测完在 `finally` 里 `restore`。中断后也要确认已经恢复，并把 `audio-after.json` 留作证据。
- **不 push。** 仓库里的 commit 只包含报告，用英文 `test:` / `docs:`。
- **结论必须有数据文件作证。** 没跑完的项写"未完成 + 原因"。失败的样本留在分母里，不能估一个数填上去。厂商公开的 WER 只能当背景参考。

## 1. 已有资产（先复用，别重写）

| 文件 | 作用 | 怎么复用 |
|---|---|---|
| `LAB/model/` | `moona3k/mlx-qwen3-asr-1.7b-8bit`，HF commit `22c8abe6a6772122dda5905967d7496d1d3e8dd2`，8bit，group 64，权重 2.07 GB，Apache-2.0 | 直接用。先算 `weights.safetensors` 的 SHA-256，记入 lock |
| `LAB/run_stream.py` | Qwen 原生流式：每 100 ms 喂一包，`init_streaming(language='English', chunk_size_sec=1, max_context_sec=30)`，读 `text` / `stable_text` / `chunk_id`，每秒最多翻译一次最新快照，定稿后再译整句 | 作为 `qwen3asr` 引擎的参考实现。翻译部分要改成 §4.3 的方式 |
| `LAB/manifest.json` + `LAB/audio/` | 已经下载的公开数据：AMI IHM 12 句、earnings22 6 段，带参考文本 | 这就是集合 F，**不用重新下载** |
| `LAB/apple.swift` | SpeechAnalyzer 整段转写（不出草稿） | 只能用来测整段的准确度上限。流式要按 §2 的配置重写 |
| `LAB/local-translate.swift` | Apple 本机 en→zh-Hans 翻译，标准输入输出逐行 JSON | 作为第二种翻译通道（§4.3） |
| `LAB/stt-30min/run_stt.py` | 30 分钟双路测试：afplay 把 `meeting.wav` 播到 BlackHole，开发版 app（`CICADA_DEBUG_CHANNEL=stt30m`）按系统音频收听；每 0.5 s 用 `lsctl state:listen` 读一次字幕，并读 `session.json` 里的定稿；同一时刻 Qwen 在进程内同步喂入 | **测 Apple 的主方法**：走的是真实 app 链路，比单独写的 SpeechAnalyzer 更可信。其他候选引擎也照这个方式并行跑 |
| `LAB/stt-30min/partial-analysis/analyze.py` | 没有参考文本时，用两路结果里都只出现一次的 5 词短语当锚点，比较哪一路先出字；还会核对 BlackHole 采集和原音频的对齐（相关系数约 0.99，固定偏移 2.71 s） | 用来做长音频的延迟对比；音频对齐检查每次都要跑 |

**上一轮的结果**（只作参照，不当结论）：
- 30 分钟那次在 573 s 时被 SIGTERM 打断（`run.log`），原因没查。
- Qwen 每个 chunk 的解码耗时 p50 0.22 s / p95 0.36 s，没有一次超过 1 s。
- MLX 内存峰值约 2.65 GB。
- 108 个锚点上，Qwen 出字比 Apple 字幕早约 0.91 s（p50）。
- `meeting.wav` **没有参考文本**，所以没法算 WER。

## 2. 被测引擎

| ID | 引擎 | 接入方式 | 配置 |
|---|---|---|---|
| `apple` | SpeechAnalyzer + SpeechTranscriber（基线） | 主方法：通过 `run_stt.py` 测开发版 app。辅助方法：单独写的 Swift CLI，用于没有 app 的离线集合 | 必须和 app 一致：`en-US`，`reportingOptions: [.volatileResults, .fastResults]`，`attributeOptions: [.transcriptionConfidence]`（见 `Sources/Cicada/Recognition.swift` 的 `Analyzer.transcriber`）。app 用 `start:user`、`-listenSource system`、`-subtitles original`、`-target en-US` 启动；关掉助手、麦克风和 Gemma 助手，避免干扰 |
| `qwen3asr` | Qwen3-ASR 1.7B 8bit（用户已有的实现） | `LAB/.venv` + mlx-qwen3-asr，同 `run_stream.py` | 主配置 chunk 1 s，`max_context_sec` 30。对照配置 chunk 0.5 s（看首字能快多少、解码能不能跟上）。warmup 不计时 |
| `parakeet` | NVIDIA Parakeet TDT 0.6B **v2**（只做英文） | **FluidAudio**（Swift，CoreML/ANE），写成 Swift CLI 子进程，用 JSONL 收发。将来进 app 也是这条路，而且跑在 ANE 上，不和 Gemma 抢 GPU。FluidAudio 接不通时才退回 Python `parakeet-mlx`，并在报告里注明 | 优先用 FluidAudio 自带的流式接口；没有的话用滑窗（窗口 ≤ 2 s，步长 ≤ 0.5 s）。参数写进报告 |
| `nemotron` | NVIDIA Nemotron Speech Streaming 0.6B（优先纯英文版） | CoreML 移植版（soniqo/speech-swift，或 HF 上的 CoreML INT8），Swift CLI 子进程 | chunk 160 ms（主）和 560 ms（对照）。找不到纯英文 CoreML 版就用多语言 3.5 版并注明。自己转换超过半天就放弃，写明原因 |

可选（时间够再做）：`whisperkit` large-v3-turbo，只作参照。

开工前先核对许可证：Parakeet 是 CC-BY-4.0，Nemotron 是 NVIDIA Open Model License，Qwen 是 Apache-2.0。不能随 app 分发的标红。

所有候选引擎统一包成同样的事件输出：`{engine, id, kind: partial|stable|final, text, source_time, at}`，方便同一个 `score.py` 一起处理。

## 3. 测试数据

每个集合都要有参考文本和逐句时间清单：`{id, set, audio, ref, start, end, voice, degrade}`。

| 集合 | 内容 | 来源 | 规模 |
|---|---|---|---|
| **A 面试题（干净）** | 仓库 `tools/copilot-questions.json` 里 72 道题的英文 `question` | `say -v <voice> -o x.aiff --data-format=LEI16@16000`，前后各留 1.0 s 静音；口音用 Samantha en-US、Daniel en-GB、Karen en-AU、Rishi en-IN（没装的换同地区其他声音并记录） | 288 句 |
| **B 长段对话** | 30 分钟连续英文。**`meeting.wav` 只有在用户提供它的参考文本时才能算 WER**；没有的话，用仓库的 `tools/copilot-audio-fixture.py`（默认版和 `--scenario hr` 版）生成带清单的长音频，拼到 ≥ 20 分钟 | 合成，或用户提供 | 1–2 段 |
| **C 劣化** | A 的 en-US 子集分别做 4 种处理：粉噪 SNR 10 dB；多人说话噪声 SNR 5 dB；8 kHz 电话带宽；1.2 倍语速（`say -r 220`） | `LAB/bench/degrade.py`，随机种子 42 | 288 句 |
| **D 术语** | 自己写 40 句，密集放 Android/AI 术语：Kotlin、Coroutines、StateFlow、SharedFlow、Jetpack Compose、ViewModel、WorkManager、Room、Binder、ANR、gRPC、protobuf、TensorFlow Lite、LiteRT、ML Kit、NNAPI、GPU delegate、OkHttp、Retrofit、SSE、WebSocket、p95、LazyColumn、Hilt 等 | `say` 生成，en-US 和 en-IN 各一遍 | 80 句 |
| **E 真人（需要用户本人）** | 用户本人和另一个人各读 D 里的 20 句，再各自由回答 3 道题（每道约 60 s，参考文本人工整理） | 由用户录音；AI 只准备朗读稿和录音说明 | 约 10 分钟 |
| **F 公开数据** | AMI IHM 12 句 + earnings22 6 段 | `LAB/manifest.json`，已在本地 | 18 条 |

E 等用户录完再补跑，其余集合先跑完出一版报告。

## 4. 测什么

### 4.1 准确度

所有引擎共用一份归一化脚本 `normalize.py`：转小写，去标点，数字统一成阿拉伯数字，常见缩写统一，连字符换成空格。不能给某个引擎开特例。

| 指标 | 定义 | 用在哪些集合 |
|---|---|---|
| **WER** | 定稿结果对参考文本，用 jiwer 计算 | A–F |
| **术语召回** | 术语在定稿里完整、拼写正确地出现的比例；多词术语每个词都要对 | D、E |
| **草稿 WER** | 定稿前最后一个草稿的 WER | A、C |
| **草稿改写率** | 已经显示的词后来被改掉的次数 ÷ 最终词数。Qwen 的 `text` 和 `stable_text` 分开统计 | A、B |
| **断句 F1** | 定稿边界和参考句子边界对比，容差 ±0.5 s | B |

### 4.2 识别速度

音频按实时速度、每 100 ms 一包喂入（和现有脚本一致）。时间轴用音频时间。走 BlackHole 的那一路，要先减掉 `analyze.py` 测出的固定采集偏移，并在报告里写明偏移值。

| 指标 | 定义 |
|---|---|
| **首字延迟** | 第一个非空草稿出现的时间 − 这句开始说的时间 |
| **定稿延迟** | 定稿出现的时间 − 这句说完的时间。Qwen 以 `stable_text` 覆盖整句为准，或者以 `finish_streaming` 为准，两个都记 |
| **词滞后** | 参考词第一次在草稿里正确出现的时间 − 这个词说完的时间。词级时间统一用一次强制对齐的结果（WhisperX 或 MFA），所有引擎共用 |
| **解码耗时** | 每个 chunk 的处理时间（p50/p95/max），以及超过 chunk 时长的次数（说明跟不上实时） |
| **资源** | 峰值 RSS；MLX 的 `get_peak_memory`；稳态 CPU。ANE/GPU 功耗要用 `powermetrics`，需要 sudo，**请用户自己跑**，否则注明没测 |
| **冷启动** | 模型加载时间，以及从启动到出第一个字的时间 |

每个指标都报 p50、p90、p95、max 和样本数。

### 4.3 流式翻译速度（核心）

两种翻译通道分开测：

1. **Google**（主）：和 app 一致，草稿和定稿都送 Google。照仓库 `Sources/Cicada/Translator.swift` 的 `GoogleTranslator` 用同一个 endpoint 和参数，en→zh-CN。草稿送翻译的节奏复刻 `ListenEngine.swift` 的 `volatile*` 逻辑：同一时间只有一个翻译请求，回来时如果文本已经变了就丢掉。实现上和 app 有差异的地方要写进报告。
2. **Apple 本机**（对照）：用 `LAB/local-translate`，和上一轮可比。

规则：Ling 不翻译草稿，所以不测 Ling。Google 连不上时，这一列标"网络未通"，不能拿别的服务替代。所有引擎在同一时段轮流跑（每句换一个起始引擎），减少网络波动的影响。

| 指标 | 定义 |
|---|---|
| **首个译文延迟** | 第一个中文草稿译文拿到的时间 − 这句开始说的时间 |
| **定稿译文延迟**（最重要） | 定稿译文拿到的时间 − 这句说完的时间 |
| **纯翻译往返** | 每次翻译请求的耗时，单独列出来 |
| **译文闪烁** | 每句显示过几版中文草稿 |
| **译文质量损失** | 用 chrF 比较"翻译(引擎定稿)"和"翻译(参考英文)"；再抽 30 句人工看，有没有识别错误把意思翻反 |

### 4.4 和 Gemma 同时跑

在 B 集合上，`apple`、`qwen3asr` 和综合最好的那个候选引擎各跑两遍：一遍只跑 STT，一遍同时让本机 Gemma E4B（`mlx-community/gemma-4-E4B-it-qat-4bit`）持续生成。对比三样：定稿延迟 p95 变差了多少、内存峰值、Gemma 首字延迟有没有被拖慢。Qwen 和 Gemma 都跑在 MLX/GPU 上，这一项对它最关键。

### 4.5 30 分钟稳定性

先查清上次 30 分钟测试在 573 s 被 SIGTERM 打断的原因：是外部杀进程、超时，还是内存。然后用 `run_stt.py` 的方式完整跑 30 分钟，每个候选引擎至少一遍。看两点：解码耗时有没有越来越慢（按每 5 分钟分段的 p95），内存有没有持续增长。

### 4.6 校准

`apple` 的两条接入方式（通过 app 和单独写的 CLI）在 A 集合 en-US 的前 20 句上对比一次。定稿延迟差超过 300 ms，或者 WER 差超过 1 个百分点，就先查清原因再继续。app 日志信息不够时，只能读，不能改 app 代码，缺什么写进报告。

## 5. 产出

```
LAB/bench/
  run_bench.py          # 统一入口：--engines --sets --translate google,apple
  engines/              # apple(app 版和 CLI 版)、qwen3asr、parakeet、nemotron
  make_corpus.py  degrade.py  normalize.py  score.py  report.py
  models.lock.json  README.md   # 一条命令复现
  runs/<date>/          # manifest、raw/<engine>.jsonl、scores.json、report.md
Cicada 仓库 docs/testing/runs/stt-bench-<date>/
  scores.json  report.md        # 只放分数和报告；不放音频，不放 E 集合的原文
```

`report.md` 必须包含：

1. 环境：机型、macOS 版本、各引擎和模型的版本与 hash、网络情况、日期。
2. 总表：每个引擎一行，列出 WER（A–F 各一列）、术语召回、首字延迟 p50/p95、定稿延迟 p50/p95、**定稿译文延迟 p50/p95（Google 和 Apple 各一组）**、改写率、峰值内存。
3. 每个集合和每种劣化的明细；每个引擎错得最多的 20 个词。
4. 和 Gemma 同时跑的对照、30 分钟稳定性、校准结果。
5. 和上一轮（§1）的对比：哪些结论被证实了，哪些被推翻了。
6. 按 §6 的门槛给出结论：**换 / 不换 / 需要更多数据**。
7. 没完成的项、偏离本方案的地方，以及原因。

## 6. 判定门槛（提议值，用户可以改）

候选引擎要同时满足下面全部条件，才建议替换 `apple`：

- **准确度**
  - A+C+D 合并 WER 相对下降 ≥ 15%，并且 C 的每一种劣化都不比 `apple` 差；
  - D 集合的术语召回 ≥ `apple` + 5 个百分点。
- **速度**
  - 首字延迟 p50 ≤ `apple` + 150 ms；
  - 定稿延迟 p95 ≤ 1.2 s；
  - 定稿译文延迟（Google）p50 ≤ `apple`，p95 ≤ 1.8 s。
- **和 Gemma 同时跑**：定稿延迟 p95 最多变差 20%，额外内存 ≤ 3 GB（Qwen 本身约 2.65 GB）。
- **稳定性**：30 分钟跑完不崩溃，解码耗时不越跑越慢，内存不持续增长。
- **许可证**：允许随 app 分发，或者允许首次使用时下载。

如果准确度达标、速度不达标，结论写"可作为会后转写/记录轨候选"，不建议用在实时字幕上。

## 7. 执行顺序

1. **读 §1 的所有文件**，把 Qwen 和 BlackHole 双路测试复跑 60 s → 检查：`events.jsonl` 里两路都有事件，音频对齐相关系数 ≥ 0.98，系统输出已恢复。
2. **生成 A/C/D 集合和清单** → 检查：每条音频时长和清单的误差 ≤ 20 ms。
3. **`apple` 的两条接入方式都跑通，做 §4.6 校准** → 检查：差距在门槛内。
4. **`qwen3asr` 跑 chunk 1 s 和 0.5 s 两种配置** → 检查：F 集合的结果和上一轮 `stream-results.json` 对得上。
5. **接入 `parakeet`、`nemotron`** → 检查：各跑 10 句，WER < 20%；接不上就按 §2 的规则放弃并写明原因。
6. **加上两种翻译通道** → 检查：每句都有定稿译文事件，或者有明确的失败原因。
7. **全量跑 A–D、F**，然后 `score.py`、`report.py`。
8. **跑 §4.4（和 Gemma 同时跑）和 §4.5（30 分钟稳定性）。**
9. **准备 E 集合的朗读稿和录音说明交给用户**；用户录完后补跑，更新报告。
10. **把报告复制回仓库并 commit**（不 push）；最后把总表和结论贴给用户。

# 四引擎 5 分钟英文 STT 实测

日期：2026-11-18（Asia/Shanghai）。同一视频前 00:00–05:00，四个引擎顺序实时回放，各 300 秒。

**范围：识别引擎级测试，不包含 Cicada App、BlackHole、字幕 UI、翻译或 Gemma 并发。没有人工参考稿，不能给 WER 或准确率排名。**

环境：Apple M4 Pro，48 GiB；ProductName:		macOS; ProductVersion:		26.6; BuildVersion:		25G72; 

| 引擎 | 完成 300 秒 | 从片段起点首次非空输出（秒，单次） | 解码 p50 / p95（秒） | 主进程峰值 RSS（GiB） | MLX 峰值（GiB） | 最终文本词数* |
|---|---|---|---|---|---|---|
| apple | 是 | 1.121 | 未测 / 未测 | 0.05 | 未测 | 769 |
| qwen3asr | 是 | 1.112 | 0.226 / 0.336 | 2.29 | 2.56 | 757 |
| parakeet | 是 | 1.151 | 0.322 / 0.356 | 0.81 | 2.34 | 699 |
| nemotron | 是 | 1.346 | 0.039 / 0.046 | 1.18 | 未测 | 768 |

*词数仅描述输出规模，不表示准确率。RSS 不包含 Apple 独立识别服务，不能据此直接比较完整系统内存；MLX 峰值与 RSS 不可相加。Apple 使用异步引擎，无法从该接口取得每 chunk 解码耗时。

## 同文短语出现时间

四路最终文本共同出现且各自只出现一次的五词短语：277 个。下表为候选出现时间减 Apple 出现时间，负值表示候选更早。

| 引擎 | 差值 p50（秒） | 差值 p95（秒） | 样本数 |
|---|---|---|---|
| qwen3asr | 0.018 | 0.705 | 277 |
| parakeet | 0.195 | 0.908 | 277 |
| nemotron | -0.367 | 0.224 | 277 |

这些短语存在重叠，并排除了识别不一致的内容；共同出现也不证明识别正确。它只反映共同文本的呈现先后，不是人工对齐的词滞后，也不是句末定稿延迟。不能用这些相关样本计算独立样本显著性。

## 输入积压

| 引擎 | p50（秒） | p95（秒） | 最大值（秒） |
|---|---|---|---|
| qwen3asr | 0.229 | 0.339 | 0.512 |
| parakeet | 0.325 | 0.360 | 0.390 |
| nemotron | 0.043 | 0.050 | 0.066 |

积压 = 输出事件真实经过时间 − 已释放音频时长，包括本次解码；不是相对说话结束的延迟。

## 配置与偏离

- Apple：独立 Swift CLI，en-US，volatileResults / fastResults / transcriptionConfidence，与 App 的识别模块配置一致，但无 App 断句与记录修订逻辑。精确捕获回调，不使用 0.5 秒轮询。识别准备完成后计时，无合成推理预热。
- Qwen3-ASR：1.7B 8bit，chunk 1 秒，max_context 30 秒，复用已有模型。
- Parakeet：v2，MLX 原始精度 checkpoint，parakeet-mlx 默认 context=(256,256)、depth=1，每秒推理。较小上下文 (256,16) 的短段试跑出现丢词，未用于正式计分。
- Nemotron：3.5 ASR Streaming 0.6B CoreML INT8 多语言版，en-US、computeUnits=all；模型配置 chunk 320 ms、lookahead 240 ms。不是纯英文旧版，也不是预案中的 160/560 ms 配置。
- Qwen、Parakeet、Nemotron 均在正式计时前预热。所有引擎顺序运行；准备期的 Apple 预跑不计入表格。
- 输入统一为 mono PCM16 16 kHz；Apple 按 bestAvailableAudioFormat 在计时前重采样。按真实时钟释放数据；Parakeet 将 100 ms 数据聚合为 1 秒推理批次。
- EOF flush 单独标注，不能算在线断句。Parakeet EOF 使用最后 stable+draft 快照，未额外补静音，不冒充已稳定定稿。
- 此轮未测：WER、术语召回、句末延迟、翻译、功耗、Gemma 竞争、30 分钟稳定性。

## 可复现性与证据

- 本地完整实验目录：[quick5](/Users/xiaohui/Downloads/cicada-asr-lab-20261117/bench/quick5)
- 四路原始转写对照：[comparison.html](/Users/xiaohui/Downloads/cicada-asr-lab-20261117/bench/quick5/comparison.html)
- 原始事件：[apple.jsonl](/Users/xiaohui/Downloads/cicada-asr-lab-20261117/bench/quick5/apple.jsonl), [qwen3asr.jsonl](/Users/xiaohui/Downloads/cicada-asr-lab-20261117/bench/quick5/qwen3asr.jsonl), [parakeet.jsonl](/Users/xiaohui/Downloads/cicada-asr-lab-20261117/bench/quick5/parakeet.jsonl), [nemotron.jsonl](/Users/xiaohui/Downloads/cicada-asr-lab-20261117/bench/quick5/nemotron.jsonl)
- 配置/退出码：[run-meta.json](/Users/xiaohui/Downloads/cicada-asr-lab-20261117/bench/quick5/run-meta.json)
- 固定模型 revision 和 SHA-256：[models.lock.json](/Users/xiaohui/Downloads/cicada-asr-lab-20261117/bench/models.lock.json)
- 运行说明：[README.md](/Users/xiaohui/Downloads/cicada-asr-lab-20261117/bench/quick5/README.md)
- speech-swift commit：`b1287a6c963a38b0d4133c656725b2de7ea6bebf`
- Python 包：`{"mlx": "0.32.4", "mlx-qwen3-asr": "0.4.4", "parakeet-mlx": "0.7.0"}`

模型来源：[Parakeet v2](https://huggingface.co/mlx-community/parakeet-tdt-0.6b-v2)、[Nemotron CoreML INT8](https://huggingface.co/aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-CoreML-INT8)、[speech-swift](https://github.com/soniqo/speech-swift)。模型卡许可元数据分别为 cc-by-4.0、openmdw-1.1；本轮未进行产品分发许可审核。

## 本轮观察

- 四个配置均完成 300 秒实时输入，退出码均为 0。三个候选的单块解码耗时均未超过各自块长；这只证明本段 5 分钟运行情况，不等于长期稳定性。
- 277 个四路共同五词短语：Nemotron 比 Apple 提前约 0.367 秒（中位数）；Qwen 晚约 0.018 秒，基本持平；Parakeet 晚约 0.195 秒。仅限这批共同短语、这一遍运行。
- Parakeet 最终文本为 699 个归一化词，其他三路为 757–769 个。输出规模明显不同，且共同短语存在较晚修正；需人工检查漏词、合并和改写，不能将词数差直接当作错误率。
- Nemotron 这次输出为单调追加；Qwen 和 Parakeet 有较多非前缀更新。该计数包含标点/大小写等变化，不是文档定义的词级改写率，单调追加也不代表识别正确。

## 判定

**需要更多数据。** 此轮用于确认四个具体配置能否实时运行，以及比较同文输出时间；不能据此宣布准确度更高或替换 Apple。后续应人工核对代表性片段，再验证真实 App 链路与翻译延迟。

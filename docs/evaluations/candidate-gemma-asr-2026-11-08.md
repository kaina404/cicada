# 候选人 Gemma 主转写验证（2026-11-08）

面试教练开启时，候选人麦克风主转写改为本机 Gemma E4B。面试官仍使用原有 Apple 链路。候选人的草稿、最终原文、中间列、保存记录及教练上下文来自同一个主转写流；跟读复用转写进行文本对齐，不再额外转写同一份音频。未开启教练的普通会议沿用原有识别设置。

## 自动检查

- `scripts/test.sh`：371 项通过（默认不运行真实模型测试）。
- `CICADA_TEST_CANDIDATE_ASR=1 scripts/test.sh --filter CandidateRecognition`：7 项行为测试及 1 项真实本机模型测试通过。
- 行为覆盖：草稿与最终结果、独立于参考稿的音频输入、静音、短句收尾、延迟草稿、取消、连续发言分段、失败重试与显式报错、跟读复用文本而不重复识别音频。
- `python3 scripts/strings.py --mac-only`：英文、日文、韩文均无缺失、TODO 或格式占位符错误。

## 本机模型实测

使用现有 `tools/coach-reading-fixtures.py` 生成的合成语音与静音文件；Gemma 服务健康检查确认模型为 `mlx-community/gemma-4-E4B-it-qat-4bit`。通过正式 `CandidateRecognition` 流提交 16 kHz 音频，未外放或读取真人麦克风。

| 合成样本 | 参考词集合召回率 | 本轮处理耗时 |
| --- | --- | --- |
| 标准英语 | 1.00 | 1.57 秒 |
| Tingting 朗读英语 | 1.00 | 1.71 秒 |
| 停顿和误读 | 1.00 | 1.25 秒 |
| 重复朗读 | 0.90 | 1.52 秒 |
| 无关发言 | 0.70 | 1.10 秒 |
| 静音 | 无转写 | 0.01 秒 |

原始结果：`/tmp/cicada-candidate-asr-evaluation.json`。参考词集合召回率不衡量词序、重复次数、插入词或标点，不是准确率或 WER；其中误读和重复样本仍存在错误，不能据此声称所有口音识别准确。整段文件快速提交的处理耗时也不代表真实麦克风端到端延迟。

第一轮固定 8 秒切段把带口音样本的连读词切断，尾部产生误识别；将最长段调整到 12 秒、优先按 0.6 秒停顿断句后，该样本转写完整。连续讲话仍需在有界长度处切段，词边界附近仍可能识别错误。

真人麦克风、AirPods、回声消除与长时间实际面试准确率未在本轮验收。中英混说由原语言转写提示支持，尚未单独做真实语音验收。不得将这份技术验证当作真实使用或业务成效证据。

## 开发版运行检查

- `scripts/build.sh` 构建成功，启动英文开发版。
- 通过 `assistantRead:/tmp/cicada-reading-accented.wav` 将音频送入正式 Gemma 转写流；日志确认 `candidate file recognized by Gemma`、`candidate_asr=gemma`、`candidate_asr_failed=false`。
- 英文 Live Notes 的中间转写列、教练的 `Already spoken` 与会议记录均显示同一段结果：`I would keep room as the single source of truth. Each message gets a stable client ID so retries do not send it twice.`
- 界面显示 `Gemma speech recognition and reading`，检查后结束测试会议，保留开发版运行。
- 文件注入跳过麦克风、音频路由和回声消除，仅验证模型转写至显示、记录及跟读输入的链路。

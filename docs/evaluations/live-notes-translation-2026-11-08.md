# Live Notes 回复折叠与实时翻译验证（Mac）

2026-11-08，开发版 `com.wquguru.cicada.dev`，英文 UI。

- 原因：本机开发版字幕设置为 `original`，会暂停翻译；`LivePartialRow` 同时只绘制原文，未绘制已有的实时译文。
- 修改：对话记录的 AI 行默认折叠，展开后显示完整原文与可用中文对照；实时行遵循双语、只看译文、只看原文模式；重新启用翻译时恢复电脑与麦克风两侧。
- 当前开发版已通过 `subtitles:both` 恢复双语。保留“只看原文”的主动选择，不强制覆盖所有用户设置。
- `scripts/test.sh`：334 tests / 55 suites 通过。
- `scripts/build.sh`：通过，已重启开发版。
- `python3 scripts/strings.py --mac-only`：通过；各语言 0 missing / 0 TODO / 0 bad specifiers。默认不带参数的检查触发旧 iOS 编译错误 `SpeakerTagger.tag`，未修改其他平台。
- 原生窗口自查：既有记录的两条 AI 回复均默认显示 `AI, Expand`；点击变为 `AI, Hide` 并显示全文与中文对照；再次点击恢复折叠。
- 合成系统语音：Samantha 播放 ActAI Android 离线消息、重试和去重问题。发言过程中，原生窗口读取到原文及实时中文译文；断句后记录显示“当应用离线时如何保证消息的可靠性？请解释你们的重试策略，以及在连接恢复后如何防止消息重复。”。
- 日志：`/tmp/livesubs-dev-debug.log`，2026-11-08 01:13 UTC 附近有 `translate via=ling kind=sentence`。本次没有测试真人面试、真人麦克风或长时间翻译稳定性。

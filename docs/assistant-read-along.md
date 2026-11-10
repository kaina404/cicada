> 2026-11-09 播放修复：单击选中并播放下一句，双击选中并播放上一句，一句结束后暂停；表冠仍只选句并暂停。长按续播、松手暂停。下文“切句即暂停”仅保留作旧行为记录。失败后松手重新长按或再次点击可重试，无需关闭陪读。

> 当前接线已迁入 Cicada 的独立 Apple Watch 模块，见 [迁移说明](apple-watch-migration.md) 和 [模块文档](../watch/README.md)。下面的 WatchControl 分布式通知接线与“两端 Mac App”要求属于迁移前历史记录。

# 助手耳机陪读（Mac）

在面试教练或设置 › AI 服务 › 面试教练勾选“陪读”，把 macOS 系统输出切到 AirPods 或受支持的耳机。WatchControl 锁定 Cicada 的 Assistant 悬浮回答窗口，原地长按约 0.4 秒后开始播放；保持按住连续播放，松开立即请求暂停，再按继续同一 PCM 位置。单击选中下一句，双击选中上一句；单击等待系统双击间隔后执行，双击不会先跳下一句。Digital Crown 向下选下一句、向上选上一句，连续转动可快速切句。切句即暂停并回到所选句开头，首尾停在边界；不切句时松手保留 PCM 位置，再长按续播。普通滑动仍移动窗口；其他窗口保留双击复位，系统鼠标模式不控制陪读。新滚轮事件需要更新 Watch App 和两个 Mac App。

不再依赖候选人麦克风、VAD、Gemma 跟读位置或三词领先策略；文字跟读、会议记录仍独立工作，音频播放不会成为已发言证据。回答替换后旧音频取消，新回答等待松开后重新长按；流式回答只合成完整句子，完成后补尾段，略过 IPA。分句预取下一片段，暂停不丢弃当前 PCM。

## 本机 Kokoro

`ShadowSynthesizer` 使用 `KokoroWorker`，不使用 macOS 系统 TTS，也不静默回退。开启陪读时异步加载并合成 Ready（不播放），复用模型与 G2P。每个片段为完整一句（不按 40 词截断），速率 0.95，音色 af_heart。CPU 推理最多四个线程，避免抢占 Gemma 的 GPU；实际合成速度记录于验证结果。

`Resources/coach/kokoro_worker.py` 由已有 `~/.cicada-mlx/bin/python` 启动，首次启用在后台准备隔离的 `~/.cicada-kokoro` venv。固定 Kokoro 0.9.4、PyTorch 2.8.0 和 en_core_web_sm 3.8.0。模型 `hexgrad/Kokoro-82M` 固定 revision `f3ff3571791e39611d31c381e3a41a3af07b4987755`；模型和 af_heart 音色缓存在 Hugging Face 标准缓存。首次安装需网络，之后已有缓存可离线加载。模型与运行环境不随 App 打包；Kokoro 模型及代码为 Apache-2.0，PyTorch 为 BSD，英文模型为 MIT。

回答与 PCM 仅通过子进程私有管道传递，无 HTTP 服务，不写回答音频或正文文件。初始化失败显示 Kokoro 不可用，关闭陪读再打开可重试。准备安装与模型加载不会阻塞主线程。超时或迟到结果不会重启暂停的播放。

## 手表接线与输出

WatchControl 的已校验窗口控制状态每 100 ms 发送按住通知，包含接收进程 PID、窗口标题、发送进程 PID、单调序号与 uptime。Cicada 校验同用户运行的 WatchControl bundle、目标实例、当前可见且受支持窗口、事件时效与顺序。只向被锁定的 Cicada 实例发送；不激活窗口，不注入键盘。不收到按住续租超过 500 ms 就暂停，并要求抬手重新操作。切换窗口、取消手势、暂停控制、睡眠和退出同样发出暂停。通知在本机传递，长按仍经过原 Watch LAN/BLE 链路。

`ShadowAudio` 使用独立 AVAudioEngine 并显式绑定当前耳机设备，不接 SpeakEngine 或 BlackHole。耳机断开或输出更换即停止旧播放，不回落到扬声器；重新连接需要重新按下。系统声音 tap 排除本进程。会议软件共享系统音频的捕获行为、实体麦克风漏音仍需实际会议环境验证，不能以输出到耳机作为绝对隔离证明。

## 验证

- `scripts/test.sh --filter Shadow`：按住/松开、同一 PCM 续播、预取、续租超时、回答替换、断连、关闭、迟到合成、无麦克风、非法 PCM。
- `CICADA_TEST_SHADOW_TTS=1 scripts/test.sh --filter ShadowReaderTests/localTTS`：真实 Kokoro 预热和连续两次合成，不播放声音。
- WatchControl `Tests/Window/main.swift`：真实窗口状态机转发长按/松开，重复/迟到包不续租，切模式和暂停释放。
- 开发命令：`shadowReading:on|off`、`shadowState`、`shadowSentence:1|-1`、`shadowHold:on|off`（单次按住需在 500 ms 内续租）。独立 `CICADA_DEBUG_CHANNEL` 可隔离自查。
- 自动化与合成不替代真人手表/AirPods 验收；需验证耳机听感、会议混音、松手停声延迟、连接切换与连续使用。

2026-11-09 本机自查：全量 401 个测试通过，两个 Mac App 均构建成功；缓存模型在 `HF_HUB_OFFLINE=1` 下完成真实合成，预热后约 1.8 秒生成 3.5 秒音频。真实 AirPods Pro 播放测试通过：暂停期间位置保持，续播后继续前进。以 WatchControl 实际窗口控制代码注入已校验手势，跨进程通知通过可见助手窗口校验，Cicada 收到按住与松开。此项覆盖 Mac 控制链路，不包含实体手表无线传输或会议软件的音频捕获。

## 音频同步逐词填色

Kokoro 的 `Result.tokens` 提供合成词起止时间；多个音频块以实际 PCM 帧数累加偏移，不以文本长度分配时间。时间表和音频通过同一条私有管道返回，不使用示例音频时间表。原稿及 IPA 保持原样，合成 token 按规范化词序映射回原稿；映射不一致或时间戳非法时保留音频，关闭该片段填色，不猜时间。

`ShadowPlayback` 只读取 `ShadowAudio` 发布的源音频位置。UI 每 25 ms 取样，时间不按 tick 累加，也不乘播放速度。原生 TextKit 固定排版，灰色底字上覆盖裁剪的强调色；停顿期间前词保持填满，句子变更才垂直跟随。可关闭“跟随朗读”自由阅读，再打开回到当前句。尊重系统减少动态效果。

点击单词可跳播：当前 PCM 片段内重新调度原 PCM 的后半部分，暂停时跳播保持暂停；跨片段按新起点重新合成本机音频和对应时间表，不套用旧时间。手表长按/松手仍负责播放/暂停。可选 0.75×、1×、1.25×；只改变播放器速率。音频进度独立于候选人的实际发言、Gemma 跟读和已说出记录。

自动化验证：`scripts/test.sh --filter Shadow`；`CICADA_TEST_SHADOW_TTS=1 HF_HUB_OFFLINE=1 scripts/test.sh --filter ShadowReaderTests/localTTS` 检查真实合成与时间表；`CICADA_TEST_SHADOW_UI=/tmp/cicada-lyrics-sync HF_HUB_OFFLINE=1 scripts/test.sh --filter ShadowLyricsTests` 运行真实原生视图并输出截图。蓝牙听感对齐、实体手表与长时间会议仍需真人验收。

2026-11-09 音频填色验证：全量 411 个测试通过（含真实原生 CandidateFeed 截图）；本机离线 Kokoro 为普通英文、缩写、连字符、0.5 / 99.9 等样本生成了可映射的词时间表。真实 AirPods Pro 验证暂停、续播和回跳；从 0.25 秒处播放约 0.6 秒，0.75× 源音频位置约 0.706 秒，1.25× 约 0.997 秒。字形位置在填色前后保持一致。`scripts/strings.py --mac-only` 检查 1233 个 Mac 文案键，三语均无缺失、TODO 或格式问题。截图见 `outputs/assistant-audio-sync/assistant-audio-fill.png`。这些检查不等于实体手表、蓝牙主观听感与会议环境验收。

Mac 开发版 `scripts/build.sh` 构建成功；隔离启动英文开发实例并检查悬浮窗的英文深色界面，见 `outputs/assistant-audio-sync/assistant-controls-en.png`，检查后停止并退出该实例。原生滚动测试确认跳至后部句子时滚动位置增加，横向位置始终为 0。原有开发实例仍保留，重启后加载此次新构建。

## 2026-11-09 手表逐句选择

Mac 接收端只接受当前可见 `cicada.assistant` 窗口，实时纪要和系统鼠标不再触发耳返。分句合成和选择共用句首词索引，长句不再按 40 词拆开，小数点不单独分句。选择取消当前及预取合成、停止旧 PCM，并立即发布句首选中位置；迟到结果不得覆盖新的选择。长按仍可顺序连续播放，松开保留当前 PCM 位置。麦克风跟读证据独立。

WatchControl Mac 端对单击延迟一个系统双击间隔；双击取消待执行单击并选择上一句。切目标、暂停、长按识别取消待执行单击。滚轮通过新增 `sentence` 包走原有 LAN/BLE 队列，在共享会话/序号/手势校验后立即转发，其他窗口和鼠标忽略该包。滚轮事件不可合并丢弃，需要更新 Watch App 和两个 Mac App；旧 Watch App 的触摸点击与长按仍兼容。

本轮验证：413 个全量测试通过；新增句首、长句、小数、前后选择、连续快速选择和松手续播覆盖。WatchControl 包编解码、41 项光标手势检查及窗口状态机检查通过（含单击延时、双击无误前进、滚轮上下、重复包、切目标取消）。Cicada 和 WatchControl Mac 构建成功，Watch App 通用 watchOS 目标编译成功，未安装实体手表。真实 Kokoro 与原生 CandidateFeed 窗口自查通过，选末句后保持暂停并垂直滚动，截图见 `outputs/assistant-sentence-control/assistant-selected-sentence.png`。隔离英文开发实例的 AX 窗口标题为 `Floating answer`，浮窗 `key=false sharing=0`；自查后停止并退出该实例，原开发实例保留。1233 个 Mac 文案键三语检查通过。

本轮未播放实体耳机声音、未验证实体手表无线滚轮或会议软件系统音频捕获。播放器仍显式绑定耳机，不接虚拟麦克风；不能将此技术路由证明等同于任意会议共享系统音频下的绝对隔离。

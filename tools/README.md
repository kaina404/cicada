# 测试小工具

开发版（`scripts/build.sh`，bundle id `com.wquguru.cicada.dev`）默认就接受这些调试命令，日志在 `/tmp/livesubs-dev-debug.log`。
正式版需要先打开调试模式：`defaults write com.wquguru.cicada debug -bool true`，然后重启 App；日志在 `/tmp/livesubs-debug.log`。

编译：`swiftc -O lsctl.swift -o lsctl`（其他几个文件同理）。

- `lsctl <命令>`：通过分布式通知 `com.wquguru.cicada.debug` 遥控 App。
  - 开关字幕：`start` / `stop`（`start:user` 当作用户点了开始听，纪要窗口立即出现；`start` 当作自动开始，等到有人说话）
  - 麦克风：`mic:<on|off>` 等于点“打开麦克风”/“关闭麦克风”（没在听时打开会开始听；旧的 `listenSource:<system|room|both>` 也还能用），`hybridState` 把两边的状态写进日志，含 `echo=` 和测量值（扬声器传到麦克风没有）、`music=`、`micSilent=`；`roomEcho:on` / `roomGate:off` 下一场会议用系统回声消除 / 不在电脑放人声时关麦克风，单独试每道防线，日志 `hybrid: room line dropped as an echo` / `kept`、`room echo: speakers reach the mic` / `none`；`roomEchoSim:<on|off|real>` 假装测出（或没测出）回声；`roomMicSilent:<on|off>` 让麦克风从下次打开起只给 0（日志 `room mic: silent since it started`，再 `still silent`，纪要窗口出“麦克风没声音”）；`voiceMicRun:<on|off>` 只开回声消除单元看它对别的声音有没有影响；念译文时 `room mic muted` / `open`；`micDeniedSim:<on|off>` 让麦克风当作被拒（纪要窗口顶部提示、字幕条橙色标签、菜单栏橙点，纪要窗口收起 10 秒后发一次通知，日志 `problem:` 和 `menu bar: badge=`）。实测回声、桌边的话和同声传译：`.claude/skills/audio-test`
  - 打开界面：`open`（主窗口）、`panel`（菜单栏面板）、`settings[:speak]`（设置，可指定栏目）
  - 虚拟麦克风：`micTest` 试音（往虚拟麦克风播一句再听回来，结果写进日志），`micNext` 做清单里的下一步
  - 会议软件的麦克风：`micUsers` 把每个读麦克风的进程和列表写进日志，`micGuide:<bundle id 或名字>` 打开怎么改，`micGuideRender:<bundle id>=<png>`
  - 快捷键：`talkKey:right` 或 `talkKey:<keyCode>:<Carbon 修饰键>` 换说话键（被拒的原因写进日志），`toggleKey:…` 同理，`shortcuts` 把当前状态写进日志
  - 字幕条：`frame` 把位置写进日志，`place:x,y,宽,字号` 摆到指定位置
  - 系统麦克风：`sysMic` 把状态、默认输入、要换回的麦克风和知了实际在录的麦克风写进日志，`sysMicSet:<设备名片段>` 假装别人改了系统麦克风，`sysMicRestore` 还原，`sysMicSwitch` 换成虚拟麦克风，`sysMicAuto:<on|off>`，`speakMic:<设备名片段>` 固定知了用的麦克风（留空 = 自动）。会改本机的系统麦克风：测完 `sysMicRestore` 或退出 App
  - 说话同传：`speakOn` / `speakOff` 开关，`speakAsk[:off]` 面板里第一次打开时的确认卡，`speakConfirmed:<on|off>` 是否已确认过，`speakFile:<音频>` 把文件按实时速度当作麦克风输入，`speakOut:<路径>` 把译文语音另存一份，`speakOutput:<设备名片段>` 改输出设备（留空 = 虚拟麦克风），`speakVP:<on|off>` 按键说话时用不用带回声消除的麦克风（默认开；日志 `voice mic: ready`、`speak: mic with echo cancellation`），`talkDown` / `talkUp` 用真麦克风按住、松开说话键（日志 `speak: on-device heard … Ming …`、没人说话时 `nothing said in the press`）
  - 试一句：`speakTest:sample`（Mac 读一句示例）或 `speakTest:voice`（再发 `speakTestBegin` / `speakTestEnd` 当作按住、松开），结果以 `speak test:` 写进日志；`speakTestState`、`speakTestRender:<png>`、`speakTestClose`
  - 识别引擎：`recognizer:legacy` 在 macOS 26 上改用 14 / 15 的识别（`SFSpeechRecognizer`，第一次会要“语音识别”权限），`recognizer:cloud` 像 Intel Mac 那样全部交给 Ling 听（没有 key 就听不了），`recognizer:auto` 换回；下一次开始听起生效（或启动时 `open --env CICADA_RECOGNIZER=legacy`），日志里 `transcriber started recognizer=…`
  - 多开：两边都设 `CICADA_DEBUG_CHANNEL=x`（`open -n --env CICADA_DEBUG_CHANNEL=x build/Cicada.app`），命令只发给这一份，日志在 `/tmp/livesubs-dev-debug-x.log`
  - 导出：`export:<目录>`
  - 导入录音或视频：`import:<路径>[,<路径>…]`（等于拖进会议记录窗口），`importState` 把进度写进日志，`importCancel` 停止转写，`importRetry:<会议 id>[=<locale>]` 重新转写（带 locale 等于在“这场会议只留下了录音”里选了这种语言），`importNotify` 把通知权限写进日志
  - 新手引导与窗口：`onboarding:<步骤>[,skip|ask|setup]`（1–5，5 是收尾页；skip 是第 3 步点了“先不接”，ask / setup 是第 4 步的二选一 / 清单）、`samplePlay`、`speakers:<on|off>`（“说话人识别”）、`speakerGuess:<会议 id>`（马上让 Ling 认一遍名字）、`speakersRender:<会议 id>=<png>`、`voiceprintFile:<音频>=<json>`（用 app 里的声纹模型算整个文件的声纹，和参考模型对比）、`closeWindow:<main|settings|onboarding>`、`settings:<overlay|language|speak|records|ai|diagnostics>`、`about`
  - 外观自查：`appearance:<dark|light|system>` 只切换当前开发实例的外观，不改 macOS 系统设置；检查后用 `appearance:system` 恢复跟随系统。
  - 显示与字幕：`display:<notes|bar|none>`、`subtitles:<both|translation|original>`、`meetingSubtitles:<…>`、`overlayState`、`overlayToggle`、`pillClick`（等于点主窗口顶部的“正在听”）、`overlayAuto[:off]`、`hideAfter:<秒>`
  - 纪要：`notesLang:<mine|source>`、`meetingNotesLang:<…>`、`notesRegenerate:<id>=<mine|source>`、`notesWindow[:x,y,w,h]`、`notesClose`、`notesMinimize`、`notesFrame`、`notesNow`、`notesState`、`notesShow:<id>`、`notesReplay:<id>[,<每次几句>]`（按会议时的节奏重写一遍纪要，默认每次 4 句；回复被 max_tokens 截断时日志写 `cut at max_tokens`）、`notesCapturable[:off]`（只改窗口能否被截屏）、`notesShare:<on|off>`（改“共享屏幕时让对方看到”这个设置，等于点图标或开关）
  - 结束会议：`endSim:<应用名>[,…]` 假装这些会议应用在通话（`endSim:` 全部挂断，`endSim:off` 回到真实情况），`endTimes:<静默秒>,<倒计时秒>,<挂断宽限秒>` 缩短等待（`endTimes:` 回到设置），`endKeep` 等于点“继续记录”，`endState` 写进日志
  - 渲染（不需要录屏权限）：`panelRender:<png>`（菜单栏面板，离屏画）、`windowsRender:<目录>`、`settingsRender:<栏目>=<png>`、`notesRender:<png>`、`mainShow:<id>[,transcript]`、`mainWindow:x,y,宽,高`（摆好主窗口并暂时浮在最上层，方便模拟点击；不带参数恢复）、`mainRender:<png>`、`speakTestRender:<png>`
  - 会中问答：`ask` 等于按提问键；`screenNotes:on` 在当前会议打开系统画面选择器，`screenNotes:off` 清除本场选择并停止捕获；无会议时不生效。`screenState` 查看 meeting/selected/running、捕获次数与预览状态。`screenPreview:<窗口 ID 或应用 bundle id>` 仅在当前会议用已有录屏权限选择窗口并启动读取，不弹权限。新会议默认不读取画面，结束后所有选择及预览清除。`CICADA_TEST_ASK=1 scripts/test.sh --filter AskModelTests` 用本机模型测 Android 面试指标表及四分钟前的合成目标，各五次，输出 `/tmp/cicada-ask-benchmark.json`；测时保持开发版在听。
  - AI：`aiKeyFile:<路径>`（从 0600 文件读 key，不经过日志；测完就删掉文件）、`aiCheck`、`aiRemove`、`aiHide:<on|off>`（只在内存里当作没有 key，文件不动；用于截图）、`aiState`、`lingSimulate:<429|hijack|timeout|off>`、`translateFail:<n>`（接下来 n 句在所有翻译来源都失败，用来测重试）、`googleDown:<on|off>`（Google 翻译当作连不上，测提示和暂停）
  - 声音：`voice:<语言>[=<id>]`、`voicePreview:<语言>=<id>`、`voiceCloneFile:<wav>`、`voicePicker:<on|off>`
  - 诊断：`diagnostics:<on|off>`、`diagReport`
  - 语音模型与“听不出”：`models:<已装,…>/<系统语言,…>` 假装本机只装了这些语音模型、系统是这些语言（`models:none/zh-Hans-CN` 是一个都没装，末尾加 `@<秒>` 让后台下载至少花这么久；之后下载的会加进来），`models:off` 回到真实情况；`source:<auto|locale>` 改“听到”（自动识别或指定语言），`pickLanguage:<locale>` 等于在“听不出”里点这种语言，`releaseModel:<locale>` 退还一个本 App 保留的语音模型。`modelFail:<offline|disk|limit|other>` 让之后的语音模型下载都按这个原因失败（`modelFail:off` 结束），`network:<on|off|real>` 假装断网、联网或跟随真实网络，`modelRetry` 等于点“再试一次”。`cloud:on` 等于点“先用 ○○ 听”（下载慢时让 AI 服务代听，只有 Ling 能听），`cloud:off` 等于点“换回等待”，`cloud:decline` 等于点“继续等”，`cloud:state` 把服务、是否提供、是否在听、正在下载哪个模型写进日志；配 `models:…@<秒>` 测下载慢、装好后自动换回（日志 `cloud: … is on the Mac`）。用没装过的语言（比如法语）能测真实的后台下载；注意 macOS 每个 App 最多保留 5 种语音模型
  - 更新与登录项：`updateFeed:<url>`、`updateCheck`、`updateInstall`、`updateState`、`loginItem[:on|off]`
  - 完整、最新的清单以 `AppModel.debugCommand` 里的 `switch` 为准。

- `macos-vm/vm.sh setup|start|deploy|listen|ssh|stop`：macOS 14 测试虚拟机（tart，镜像实际是 14.5），在旧识别引擎上跑开发版。第一次 `setup`（约 18 GB），之后 `start`、`deploy`（装 `build/Cicada.app`）、`listen en.aiff`（片段放在 `~/VMs/share`）。截图用 `screencapture -l <tart 窗口 ID>`，点按用虚拟机里的 `~/bin/mouse`。虚拟机的声卡带麦克风，开始听时会先弹“麦克风”权限。

## 测试技巧

- 麦克风切换回归：系统输入选 BlackHole，Mac 内置麦克风改成与它不同的采样率（音频 MIDI 设置），运行 `CICADA_TEST_MIC=1 swift test --filter SpeakMicTests`。按住说话、会议室麦克风、录声音样本各开内置麦克风几次，只统计帧数或在取消时删掉样本，不识别、上传或播放，不改系统输入。运行测试的终端要有麦克风权限；普通单元测试和 CI 默认跳过。
- 英文界面：`defaults write com.wquguru.cicada.dev AppleLanguages -array en` 后重启，测完 `defaults delete com.wquguru.cicada.dev AppleLanguages`；或启动时加 `--args -AppleLanguages "(en)"`。
- 纪要窗口不出现在截屏里：先发 `notesCapturable` 再 `screencapture -l`，或直接 `notesRender:`。
- 合成的按键会发给所有 App：别的 App 的启动器可能抢走 ⌥ Space。模拟鼠标和按键需要终端有“辅助功能”权限。
- 试一句可以测整条同传链路和延迟：`speakTest:sample` 连发几次，读日志里的 `speak test:` 行。
- 端到端测更新：把根目录的 `VERSION` 调高再构建（构建完改回去），`ditto -c -k --keepParent build/Cicada.app Cicada-<v>-macOS-AppleSilicon.zip`，`shasum -a 256` 写进 `checksums.txt`，写一个资源地址用 `file://` 的 release JSON，从 scratchpad 运行旧版开发版（不要用 `build/` 里的），再 `updateFeed:file://…` 和 `updateInstall`。
- `mouse move|drag|dclick|click|scroll ...`：模拟鼠标移动、拖动、双击、单击、滚轮（`scroll x y 行数`，正数往上翻），坐标原点在主屏左下角。
- `key`：模拟按住说话键。`key right [秒]` 单按右 ⌥；`key <keyCode> <Carbon 修饰键> [秒]` 按组合键（如 `key 122 0` 是 F1）；不带参数是 ⌥ Space。
- `toggle-key`：模拟按一下 ⌃⌥S。
- `winall <pid>`：列出某个进程的窗口 ID，配合 `screencapture -l <ID>` 截图。
- `transcribe <音频> <locale>`：用本机模型转写一个文件，用来核对输出。



## 本机面试教练验证

- DeepSeek V4.1 Flash 开发版对照实验：以 `CICADA_COACH_PROVIDER=deepseek` 启动开发版（正式版忽略此开关），密钥文件为 `~/Library/Application Support/LiveSubs Dev/ai-key-deepseek`，权限 0600。只上传双方原文、历史、背景及已选窗口的截图，不上传声音；本机 Gemma 继续负责跟读。取消环境变量并重启即回到本机生成。界面标明云端处理与 TTFT。
- 实际 Swift 链路测首 token：`CICADA_COACH_PROVIDER=deepseek CICADA_TEST_DEEPSEEK=1 scripts/test.sh --filter CoachDeepSeekModelTests`。六次合成 ActAI Android 请求（短上下文、30 轮历史，各带三张 1600×900 图片），报告 `/tmp/cicada-deepseek-coach-results.json`。日志 `request_first_token_ms` 从 HTTP 发出计时；`pipeline_first_token_ms` 从生成流程开始计时，含准备和排队；均忽略元数据与思考 token。此探针不包含真实语音断句耗时。

- 设置 › AI 服务 › 面试教练使用已安装的本机 Gemma 4 E4B。电脑原声、双方原文与压缩屏幕关键帧发往本机 MLX；不使用旧百炼实时模型。
- `assistant:<on|off>` 开关教练；`ask` 手动分析；`askGloss:<on|off>` 开关建议的本机中文对照。教练只输出文字。
- `assistantSay:<问题>` 注入面试官原文并分析；`themSaid:<原文>` / `meSaid:<原文>` 写入双方原文。后两者不模拟声音。`assistantState` 写出状态、帧数、原声音频秒数、实际候选人麦克风、声学就绪、生成次数、首句耗时与 committed/pending 数量；`assistantReconnect` 重试失败请求；`assistantBackgroundReload` 重读背景。
- `screenfile:<图片路径>` 注入关键帧；`assistantRender:<png>` 生成当前建议的被动截图；`screenNotes:on` 在当前会议打开画面选择器，`screenNotes:off` 清除选择并停止捕获。关闭、换窗口或结束会议后不沿用旧窗口图片。
- 真实电脑声音链路：`start:user`，播放合成 ActAI 问题，检查 `coach: full answer` 的 `audio_s`。候选人使用 `mic:on`；设置里可跟随系统输入或指定 AirPods。连接、断开与切换默认输入时应检查实际麦克风 UID，且双方角色保持不变。
- 行为与多模态入参测试：`scripts/test.sh --filter InterviewCoachTests`。
- 本机模型探针：先用 `say -v Samantha -o /tmp/cicada-coach-question.aiff 'For this Android interview, look at the slide. How would you keep messages reliable when the app goes offline, and what is the first visible token target?'` 生成合成题，再运行 `CICADA_TEST_COACH=1 scripts/test.sh --filter InterviewCoachModelTests`。测试传原声音频、指标图片和候选人原文，报告在 `/tmp/cicada-interview-coach-benchmark.json`。
- 模型探针与文字注入不替代真人麦克风、AirPods 热切换、实际共享窗口和长时间面试验收。设计及验证记录见 `docs/interview-coach-local.md`。
- 旧 Candidate / Copilot / AnswerPlan / Qwen 工具保留作历史参考，未接入当前教练；旧云服务探针不会由教练调用。

## Qwen Realtime 阶段 0 探针

独立工具 `qwen-realtime-probe.swift`，不依赖或修改 App。联网需要北京或新加坡业务空间 ID，以及同区 DashScope Key 文件 `~/Library/Application Support/LiveSubs Dev/ai-key-dashscope`（0600）。当前面试教练设置页不再提供该云模型；历史探针可直接读取已有文件。不要通过命令行参数、聊天或 UserDefaults 传 Key。

```bash
# 离线检查解码/分包，不读 Key、不连接网络；不代表服务端验证通过。
swift tools/qwen-realtime-probe.swift Resources/sample/sample.m4a --dry-run --seconds 1
python3 -m unittest discover -s Tests -p test_qwen_realtime_probe.py -v
# 联网：仅在提供真实业务空间和同区 Key 后运行。音频会上传百炼，可能产生费用。
swift tools/qwen-realtime-probe.swift AndroidEngineerMockInterview.mp4 --workspace <WorkspaceId> --region cn-beijing --seconds 60
```

默认请求纯文字输出。`--audio-output` 显式请求文字与音频以做对照，会产生音频输出用量；收到的音频直接丢弃，绝不播放。`--seconds` 限制输入时长（默认 60 秒、最多 7200 秒），联网按真实时间推流，文件结束后补 5 秒静音并等待 15 秒回复。报告默认写入 `docs/evaluations/qwen-realtime-probe-<UTC时间>.json`，可用 `--report <path>` 指定；只包含事件时间、文字长度、数字用量，不保存 Key、音频、完整转写或台词。网络故障和缺 Key 也写失败报告。

报告的首字时延从收到 `speech_stopped` 开始计算，**不包含服务端 VAD 判停耗时**，不能当作从面试官实际说完开始的端到端成绩。每次 `speech_started` 都显式发 cancel，因此不能据此推断服务端是否自动取消。连接最大时长、上下文上限、暂停误判和小时费用仍需对应的长会话、标注输入及价格数据；报告的 `pending` 保留这七项验证提醒。`--server-vad` 使用 900 ms 静音判停；不带此参数可对比 semantic_vad。旧链路仅在全部验收后删除。


全文教练回归：`scripts/test.sh --filter InterviewCoachTests`、`scripts/test.sh --filter CoachScriptTests`；历史本机模型对照探针 `CICADA_TEST_COACH=1 scripts/test.sh --filter InterviewCoachModelTests`；声学模型测试 `~/.cicada-mlx/bin/python -m pytest -q Tests/test_coach_audio.py`（先在设置安装语音检测）。`meSaid` 验证实际发言入 committed；`themSaid:Okay` 会进行 AI 覆盖审查，keep 不增加正文生成次数；已被剩余稿件覆盖的追问同样保留原稿，未覆盖的要求才重新生成 pending。`assistantState` 的 reviews 为审查次数，generations 为正文生成次数。会议目录 `coach.jsonl` 保存过程事件及延迟，完整规格与限制见 `docs/interview-coach-local.md`。


## Gemma 原声跟读验证

- `python3 tools/coach-reading-fixtures.py` 生成十段合成 WAV（只写文件，不播放）。本机模型已就绪时运行 `CICADA_TEST_READING=1 scripts/test.sh --filter CoachReadingModelTests`；报告为 `/tmp/cicada-gemma-reading-evaluation.json`。这是合成语音基准，不代表真人口音准确率。
- `assistantRead:<音频绝对路径>` 将本地音频最多前十秒送入候选人原声链路；不注入 Apple 转写、不改稿、不播放音频。先生成回答，再用它的开头制作语音文件，观察 `assistantState` 的 `reading=gemma cursor=… sentence=… reading_failed=…`；生成次数和 response_id 应保持不变。`meSaid` 不再推进朗读位置。
- 跟读只用本机 Gemma，两阶段独立转写/稿件对齐；纯静音不请求，重复与无关发言不推进，新问题取消旧结果。发生识别错误时保留位置并可重试。

- 照片回归：`CICADA_TEST_READING=1 scripts/test.sh --filter CoachReadingModelTests/photoSentenceAfterSkippedWords`，用 Samantha / Tingting 合成声音跳过 feed screen 句尾，读到 scalability；报告 `/tmp/cicada-reading-photo-evaluation.json`。原声独立转写中唯一的连续词组可在前方 180 词内恢复位置；不会用 Apple 转写或稿件猜测未听见的词。

- AI 覆盖审查本机模型回归：`CICADA_TEST_COACH_REVIEW=1 scripts/test.sh --filter CoachReviewModelTests`，需本机 Gemma 就绪；报告 `/tmp/cicada-deepseek-answer-update.json`，含同一句追问在不同稿件覆盖情况下的 keep/replace 对照。

教练默认使用 DeepSeek Flash，AI 服务设置可保存专用 DeepSeek key。更新请求的首行是私有 JSON 决定，keep 后没有正文，replace 后在同一响应流式输出新稿；没有第二次正文请求。本机 Gemma 只负责麦克风跟读，开发对照可设 `CICADA_COACH_PROVIDER=local`。

## 候选人 Gemma 主转写

- 面试教练开启时，候选人麦克风的主转写使用本机 Gemma，面试官保留 Apple。中间列、会议记录和教练上下文使用同一份转写，跟读只做文本对齐，不再重复识别音频。
- `assistantRead:<wav>` 静音文件注入：Gemma 识别后写入候选人文字记录，并驱动跟读；无需外放，不验证实体麦克风或回声消除。
- `CICADA_TEST_CANDIDATE_ASR=1 scripts/test.sh --filter CandidateRecognition` 验证主转写流、取消、失败重试、连续发言与合成语音；音频先由 `tools/coach-reading-fixtures.py` 生成。报告 `/tmp/cicada-candidate-asr-evaluation.json`，不代表真人口音准确率。

- 追问澄清回归：`CICADA_TEST_COACH_REVIEW=1 scripts/test.sh --filter CoachReviewModelTests` 使用实际 DeepSeek，涵盖截图识别句、简化、再举例、指标追问及普通附和；新增结果写入 `/tmp/cicada-clarification-review.json`。`ask` 跳过覆盖审查，结合对话重新生成当前问题及追问，允许必要的复述；不是只补完旧稿。

- Dock：`dock:<on|off>` 设置是否常驻 Dock；`dockRender:<png>` 导出当前图标；`notesFrame` 可查看当前激活策略。

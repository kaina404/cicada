# Apple Watch 陪读播放修复（2026-11-09）

## 现场证据与边界

当前开发实例的 `watchState` 为 floating answer ready、浮窗可见，`shadowState` 为 failed，cursor=0、words=96。本机 Kokoro 实际合成和 AirPods Pro 底层播放、暂停、续播、变速测试通过。旧代码在播放或合成失败后持续拒绝长按，切句也不清除失败；点击只选择并暂停，没有用户要求的播放动作。

旧日志没有记录首次失败来自合成还是设备加载，无法追溯首次错误。不能据此声称已确定最初触发无声的硬件或合成原因。新增仅记录错误阶段、NSError domain/code 的诊断，不记录回答内容。

## 修改

- 新落指可重新准备失败的播放；正在按住时失败仍需先松手，避免每次心跳反复重试。
- 单击、双击独立触发所选句播放，一句结束后暂停；表冠保持选句待播。
- 下一次落指、隐藏浮窗、睡眠和停止接收器同时取消点击播放；耳机断开不回退到扬声器。
- 异步音频加载先核对 clip ID，再处理错误；加载失败保留所请求 clip ID，避免旧失败污染新片段。

## 验证

- `scripts/test.sh`：416 项通过，包括手表接收器、切句播放、失败恢复和异步旧状态隔离回归。
- `watch/scripts/test.sh`：协议、手势、平滑与 LAN/BLE 传输检查通过。
- `CICADA_TEST_SHADOW_TTS=1 scripts/test.sh --filter ShadowReaderTests/localTTSProducesAudioWithoutPlayingIt`：实际 Kokoro 预热、合成与词时间表通过。
- `CICADA_TEST_SHADOW_PLAYBACK=1 scripts/test.sh --filter ShadowReaderTests/actualHeadphonesPauseAndResume`：hui的AirPods Pro 实际播放器通过，暂停源音频位置约 0.832 秒，变速 0.75× / 1.25× 分别约 0.706 / 1.01 秒。
- 新增 `actualHeadphonesReaderHoldAndTapPlayback` 使用真实 ShadowReader、Kokoro 和 AirPods，长按播放、松开保持位置、下一句/上一句点击播放均通过（约 6.3 秒）。该项直接调用 Mac 控制方法，不包含无线手表链路。
- `python3 scripts/strings.py --mac-only`：1233 个键，英/日/韩无缺失、TODO 或占位错误。

实体 Apple Watch 的无线触摸与主观听感仍需人工验收。构建不会替换运行进程中的代码。

Mac 开发构建与签名通过。隔离英文实例可启动，助手浮窗保持 key=false、sharing=0；空稿界面检查后已停止并退出。该实例未验证真实回答的英文失败提示布局。

最终正常启动新版开发 App，已确认 Kokoro 预热成功、shadow=waiting；打开助手浮窗供手表重新控制。当前新实例尚无回答（words=0），需要产生回答后真人验证手表操作。

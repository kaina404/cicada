# Apple Watch 模块迁移

日期：2026-11-09（Asia/Shanghai）。迁移范围来自用户明确要求，将 WatchControl 迁入 Cicada 的独立 Apple Watch 模块。

## 交付结构

- `watch/App`：手表 SwiftUI 界面、触摸手势、表冠切句和 LAN/BLE 客户端。
- `watch/Shared`：两端唯一的 V2 `ControlPacket`。
- `watch/Mac`：独立 Swift Package target `CicadaWatchControl`，由 Mac Cicada 依赖。
- `watch/CicadaWatch.xcodeproj`：独立手表工程，包含 watchOS App 和安装容器；Mac 仍用原 Swift Package / Command Line Tools 构建。
- `watch/Tests` 和 `watch/scripts`：模块回归、手表构建、个人配对准备和集成 smoke。

Mac 接收器由 AppModel / AppDelegate 管理启动与停止，通过闭包访问 `AssistantWindowController` 的 NSPanel 和 `ShadowReader`。只接受当前可见、标识为 `cicada.assistant` 的本进程窗口；不再枚举其他进程窗口，不再需要辅助功能权限，也不再使用 WatchControl 分布式播放通知。浮窗的非激活和屏幕共享设置保持由 Cicada 管理。

所有 UI、收包、窗口和播放状态仍在 MainActor。保留原协议序号/会话/手势校验、重复包过滤、移动平滑、长按续租和切句判定。隐藏或切换目标会清除旧手势；重新打开必须重新落指。空闲轮询不会向本地播放反复发送暂停。

## 本机配置和兼容

原主机配对的服务 UUID 与令牌已在本机保留。新增可选的字符串字段 `port`，旧配置缺省仍为 8765。LAN 头和 BLE 服务/特征协议保持兼容。

本机已有独立 Python 服务占用 8765，因此将本机 Cicada 配对设为 8876，并重建 Mac / Watch 两端；未终止该 Python 服务。旧手表客户端只支持 8765，需安装本模块新包才能使用这里的自定义端口。

手表使用新 bundle ID `com.wquguru.cicada.watch.watchkitapp`，与旧 WatchControl 分开。Mac bundle ID 和原 ad-hoc designated requirement 未改。版本来自仓库 `VERSION`，本次手表构建版本为 1.3.0。

`LocalPairing.json` 为 0600 且被 git 忽略；生成的版本配置也被忽略。Mac 开发构建复制本机配对，公开 `RELEASE=1` 构建不包含它。没有本机配对时接收器不启动。当前不包含面向普通用户的可视化配对，不能作为面向外部分发已完成的证据。

## 验证

- `scripts/test.sh`：主应用 413 个测试（76 suites）及独立模块 3 个测试均通过，共 416 个。
- 模块测试覆盖本进程真实 NSPanel 移动、非激活、隐藏与重连、窗口标识隔离、长按释放、切句，以及配对/自定义端口校验。
- `watch/scripts/test.sh`：V2 编解码、41 项手势状态、显示平滑、精细移动与 LAN/BLE 传输回归；新增自定义端口探测和控制请求检查。
- `watch/scripts/build.sh`：generic watchOS 构建通过，非具体设备运行证明。
- `scripts/build.sh`：Mac App 构建与签名通过。
- `python3 scripts/strings.py --mac-only`：1233 个文案键，英/日/韩均无缺失、TODO 或格式占位错误。

- 英文开发实例真实运行检查：通过配对端口 8876 的 HTTP 收包，错误令牌返回 403，正确连接和 V2 控制返回 204。真实 floating answer 从 x=676 移到 x=721（45 point），完成后恢复原位置。
- 隐藏浮窗后控制不移动窗口，重新打开后旧手势尾包仍不移动；新落指可继续控制。检查各阶段 `key=false sharing=0`，未激活窗口且保持默认排除屏幕捕获。
- 接收器日志确认 LAN 监听成功、BLE 备用服务就绪；BLE 广播就绪不等于真实手表无线链路验收。
- 运行证据：`build/watch-full-tests.log`、`build/watch-standalone-tests.log`、`build/watch-migration-build.log`、`build/watch-mac-build.log`、`build/watch-strings.log` 与 `/tmp/livesubs-dev-debug-watch-migration.log`。
- 退出隔离英文验证实例后，正常启动新版 Cicada 开发 App，供用户继续使用。

## 待人工验收

未安装实体手表新包；未进行真实无线触摸 / 表冠、耳机声音或会议软件捕获验收。仍需检查手表文字布局和操作手感、AirPods 停声延迟、BLE 回退与真实异常断链。自动化与代码路由验证不代替这些证据。

# Cicada Apple Watch

独立 watchOS 模块，用 Apple Watch 控制 Cicada 的 **floating answer（悬浮回答）**。Mac 接收端已集成进 Cicada，不需要运行 WatchControl，也不需要辅助功能权限。

- 滑动：移动浮窗；重新落指从当前位置继续。
- 原地长按约 0.4 秒：播放 / 继续耳机陪读；松手暂停。
- 单击：选中并播放下一句；双击：选中并播放上一句；一句结束后暂停。表冠向下 / 向上：选中下一句 / 上一句并保持暂停。播放失败后松手重新长按可重试。
- 仅控制当前 Cicada 实例可见的悬浮回答。隐藏 / 关闭窗口、睡眠、退出或断链会停止当前手势与陪读；重新打开后重新落指。

## 目录

| 路径 | 用途 |
| --- | --- |
| `App/` | 手表 UI、触摸状态、LAN/BLE 客户端 |
| `Shared/ControlPacket.swift` | 两端共用的 V2 协议 |
| `Mac/` | Swift Package 模块 `CicadaWatchControl`，直接控制本进程 NSWindow |
| `CicadaWatch.xcodeproj/` | 独立手表工程和轻量 iPhone 安装容器 |
| `Config/` | 手表权限说明和生成的版本配置 |
| `Tests/` | 协议、手势、传输和 Mac 接收端测试 |

## 本机开发

```bash
# 仓库根目录：生成配对信息并编译手表（不安装）
watch/scripts/build.sh
# 同一份配对信息会随 Mac 开发构建复制到 App bundle
scripts/build.sh
open build/Cicada.app
```

打开 `watch/CicadaWatch.xcodeproj`，选 **Cicada Watch App** scheme，配置自己的 Apple 开发签名后安装。先运行 `watch/scripts/prepare.py` 生成配对和版本配置；仓库唯一版本来源仍为根目录 `VERSION`。手表 bundle ID 为 `com.wquguru.cicada.watch.watchkitapp`，与旧 WatchControl 不同，安装后打开 **Cicada** 手表 App。

初次迁移已在本机保留旧配对配置，保持 V2 协议兼容；旧客户端仅在配对主机和端口相同时可直接连接；干净检出会生成新配对。Mac 改名后重跑 prepare，并重建两端。Mac 只运行一个带本机配对的 Cicada 实例；默认端口 8765 被占用时会在诊断日志报告失败，可用 `CICADA_WATCH_PORT=8876 watch/scripts/prepare.py` 为本机选择空闲端口，再重建两端。请退出旧 WatchControl，避免端口和 BLE 广播冲突。

在 Cicada 打开 floating answer，并开启陪读、选择耳机。手表 App 保持前台。Mac 开发诊断 `tools/lsctl watchState` 可查看接收端状态，不输出凭据。未找到本机配对的构建默认不启动手表服务。

## 配对与发布边界

`App/LocalPairing.json`（0600）与 `Config/Version.xcconfig` 自动生成、被 git 忽略。配置包含当前 Mac 主机名、专用 BLE 服务 UUID 和 LAN 令牌，不能提交仓库或公开分发。`RELEASE=1 scripts/build.sh` 不会打包本机配对，因此公开发布版默认不开启接收服务。目前为本人设备的局域网 / BLE 开发流程，尚未提供面向普通用户的可视化配对。

LAN 使用令牌校验、明文 HTTP（默认 8765，可在本机配对中配置）；BLE 保留原专用服务和写入协议。只在本人设备与可信局域网使用。未加入系统光标事件或远程通用控制。

## 验证

```bash
scripts/test.sh --filter CicadaWatchControlTests
watch/scripts/test.sh
watch/scripts/build.sh
# 已启动隔离英文开发实例时（CICADA_DEBUG_CHANNEL 与实例一致）
CICADA_DEBUG_CHANNEL=watch-migration python3 watch/scripts/smoke.py
```

受控测试和 generic 编译不等于真机验收。迁移验证记录见 `../docs/apple-watch-migration.md`；真实手表、AirPods 停声延迟、断连恢复及英文布局仍需人工验收。

联系：support@missyoy.com

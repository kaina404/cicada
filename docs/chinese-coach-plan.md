# 中文面试教练计划

2026-11-17 定：现有 Cicada 内加「面试语言：中文/英文」开关，共用引擎；中文也输出完整可朗读台词并跟读；本期大陆范围只到 App 内网络依赖无代理可用。仅 Mac。

## 阶段

1. **中文切分与跟读**（已完成）：`CoachScript.words` 按汉字切 token、拉丁词保持整词；`droppingWords` 同口径；`。！？` 断句；文字判停识别中文结尾连词。英文行为不变，见 `CoachScriptChineseTests`。
2. **语言开关**（已完成）：`AppSettings.coachLanguage`，回答面板「面试语言」分段选择；中文时两路识别固定 `zh-CN`（`ListenEngine.coachLanguage`），关闭英式 IPA、HR 英文过滤、中文对照和英文陪读，快速跟读改用 `zh-CN` 本机识别。调试命令 `coachLanguage:<english|chinese>`。
3. **中文提示词**（已完成）：`CoachPrompt.systemChinese` / `plainChinese` 用中文写，HR、CEO 开放题约 150–250 字；审查、屏幕分析、澄清句和事实提醒按语言替换。开发版实测（`say -v Tingting`）：项目介绍、离职原因、"一句话说优势"追问均为口语化中文，追问经审查替换为一句；首字 0.5–1.6 s。
   - 待办：`CoachReadingPrompt.align` 仍写 "English script"，60 字窗口未在真人中文朗读下评估；快速跟读对同音字没有拼音级相似度。
4. **大陆网络**（已完成）：`HubMirror` 每次启动探测 huggingface.co，连不上时给 mlx-vlm、语音检测和 Kokoro 进程设 `HF_ENDPOINT=https://hf-mirror.com` 与阿里云 `PIP_INDEX_URL`，用户自设的变量优先。Silero 随 App 打包；Smart Turn 加 SHA-256 校验。DeepSeek 直连已可用。
   - 未覆盖：`~/.cicada-mlx` 本身（mlx-vlm 的 Python 环境）不是 App 安装的；英文陪读用的 spaCy 词典仍从 GitHub 下载（中文模式不用）；更新检查走 GitHub API（不在本期范围）。没有在真正的大陆网络下实测，本机可直连 huggingface.co，镜像路径靠 `hubMirror:on` 和 `HF_ENDPOINT` 强制验证。
5. **实测**：中文面试音频（`say -v Tingting` 生成）跑完整链路：识别、判停、生成、跟读光标；真人中文朗读需要人工。

## 风险

- Apple 中文识别的同音字会让逐字对齐的命中率低于英文；当前阈值（≥3 命中、≥45%）在真人朗读上待验证。
- Gemma E4B 中文音频转写质量未测。

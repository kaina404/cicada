# ActAI 钱包面试：资料瘦身后的整场验证

2026 年 11 月 19 日 21:44。Cicada macOS Dev 1.10.1（含 `ed8b458` 资料瘦身）。题目、Founder 动态追问、两处改题和严格评委与 [1516 轮](../wallet-live-20261119-1516/report.md) 相同；Founder、评委都走 `qa.llm`（`MOCK_LLM=deepseek`）。没有放真实声音（无 `AUDIO=1`）。

## 结果

| 轮次 | 严格评委（第一张卡 / 按实际念出） | 图 | 首字中位数 | 卡片稳定（中位 / 最慢） |
| --- | --- | --- | --- | --- |
| 1516 | 20 / 20（已评 20 题，Q-close 未评） | 4/4 | 823 ms | 7.2 / 12.2 s |
| 2144 | **19 / 21，20 / 21**（21 题全评） | 4/4 | 647 ms | 6.0 / 24.0 s |

- 第一题判断：通过。评分表：总分 75，决定 yes。
- W1–W7 和 Q-close 全部通过。资料瘦身后设计题没有变差。
- 请求大小（字符）：设计题平均 87,759（135 次，不带预制回答），项目题和 Q-close 平均 261,430（90 次）。
- 花费：DeepSeek 余额 19.98 → 18.80 元。这 1.18 元包括 App 的卡片、Founder 和评委。

## 失败的两题（已修复）

| 题 | 现象 | 原因 | 修法 |
| --- | --- | --- | --- |
| P1-intro（只有第一张卡失败） | 项目介绍后面多了三句聊天付款的话（金额、服务端绑定、工具重复调用） | 开场白（“agent-first app…then design a fictional mobile wallet”）和 P1 合成了同一个面试官回合，命中 W6 规则 | 带主题的必答点只用在设计题；问题目标是讲候选人自己经历时不补（`CoachRequiredPoints.applies`） |
| P3-risk | 故事讲到“给了两个选项”就停了，没有“谁决定”和“我完成了什么” | 多问句上限 8 句，故事的铺垫用完了 | “Tell me about a time…” 这类故事题每问 3 句，最多 12 句（`CoachCards.storyLimit`） |

两处修复都有单元测试（`aProjectQuestionAfterTheWalletOpenerGetsNoWalletPoints`、`multiPartQuestionsAndWalletNotesNameEveryPart`），还没在实测里跑过。失败少于 3 个，按约定不再重跑。

测试：`scripts/test.sh` 699 项全部通过。

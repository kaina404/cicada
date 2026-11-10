# HR 合作方式：选定排练案例与验证

更新：2026-11-10。只涉及 Mac Assistant 开发版知识库。

用户认可以下三个案例用于排练。事件情节由助手在本聊天获准构思，尚未确认真实发生；不能把认可文案当作事实确认。可之科技案例已排除。

回答结构：一句话指出不适应的行为 → 一个具体产品例子 → 自己采取的行动 → 结果。评价行为，不攻击个人；不虚构前期调研或方案缺陷。

## KKday｜遇到困难不及时反馈

编号：`KKday-risk`。状态：模拟排练，待核实。

我不太适应遇到困难后一直不反馈，直到临近交付才提出的合作方式。比如在 KKday 做 AI 行程规划时，我们支持用户通过追问修改行程。有一次，同事处理“修改一天后，如何保持后续行程衔接”的问题，花的时间超出了预期。他想自己解决，到了约定联调时才同步，影响了客户端的验证安排。我先和他一起梳理卡在哪里，再把能独立验证的部分拆出来，让客户端继续联调，同时和产品确认剩余部分的交付安排。最后我们分阶段完成了验证，避免所有工作都等在一个问题上。之后类似的阻碍也会更早同步，方便大家及时协调。

英文排练参考（情境假定）：

I find it difficult when someone is blocked but only raises it just before delivery. In this KKday rehearsal scenario, a colleague working on follow-up itinerary changes took longer than expected to keep the later days consistent, and only raised it at integration time. I worked through the blocker with him, separated the parts the client could already test, and agreed the remaining delivery plan with product. We completed validation in stages instead of keeping all work waiting on one issue. Later blockers were shared earlier.

## KKday｜反复讨论没有结论

编号：`KKday-decision`。状态：模拟排练，待核实。

我不太适应一个问题反复讨论，却始终没有明确结论和下一步的工作方式。比如在 KKday 做 AI 行程规划时，对于校验不通过的生成结果，团队有不同意见：继续重试，可能得到完整行程，但用户要等更久；直接提示失败，响应更快，但体验也不好。讨论了几轮，仍然没有定下来，客户端和测试都在等处理规则。我把实际失败样例和重试耗时整理出来，拉相关同事集中比较，推动大家确定重试上限，以及超过上限后的提示和重新生成方式。最后前后端按同一套规则完成实现，测试也能据此验收。

英文排练参考（情境假定）：

I find it difficult when a discussion keeps going without a decision or a next step. In this KKday rehearsal scenario, we disagreed on whether to retry an invalid itinerary or show a failure quickly, and client development and testing needed a clear rule. I collected failed examples and retry times, brought the people involved together, and helped agree a retry limit and what the user would see after it. The client and backend could then implement the same rule, and testing had a clear acceptance basis.

## 德邦证券｜职责交界处无人继续推进

编号：`Debon-watchlist`。状态：模拟排练，待核实。

我比较不适应的是，问题涉及多个模块时，只说明自己这部分没有问题，却没有人继续推动。比如做自选股时，测试发现调整股票顺序后，重新进入页面偶尔会恢复旧顺序。这个问题涉及本地缓存和服务端同步，双方单独检查都没有发现明显异常，排查一度停了下来。我主动把完整操作录下来，约后端同事一起对照请求时序和数据变化，最终定位到特定情况下旧数据覆盖新排序的问题，再一起完成修复和验证。最后问题解决了。对我来说，职责可以有分工，但面对一个完整的用户问题，需要有人主动往前多推一步。

英文排练参考（情境假定）：

I find it difficult when a problem crosses module boundaries and work stops after each side says its own part looks fine. In this Debon rehearsal scenario, a watchlist sometimes returned to its old order after the user changed it and reopened the page. I recorded the steps and worked with the backend engineer to compare request timing and data changes. We found old data could overwrite the new order in a particular sequence, and fixed and verified it together. The sorting problem was resolved.

## 知识库与验证入口

实际加载文件：`~/Library/Application Support/LiveSubs Dev/candidate-background.md`（0600）。用 `assistantBackgroundReload` 重读；程序通过 `CoachKnowledge.retrieve` 检索。未修改正式版知识库、提示词或简历。

验证结果、原始问题、App 会话事件与评分见 `outputs/hr-collaboration-2026-11-10/`。额外两道 HR 情境题不预写答案，不补造历史经历。

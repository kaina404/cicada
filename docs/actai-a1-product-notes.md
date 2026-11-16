# A1 Product Notes（面试用一页纸）

2026-11-12 起草，回应 HR 对上一位候选人的两条顾虑：Head（不了解产品）、Hustle（WLB 只谈休息）。用法：HR 面里主动提出“我写了一页产品笔记”，或面试后发给对方。

事实边界：

- 产品信息只来自用户提供的公司简介、ActAI Android JD，以及 BJAK 在 Ashby 上公开的招聘页（2026-11-12 检索）。2026-11-12 检索时没找到公开 App、demo 或产品官网，所以下文的“问题”和“建议”是对着 JD 提出的假设，不是用过之后的反馈。面试里要说 "from the job posts"，不能说 "when I tried the app"。
- 个人佐证只用 CabinetAI 和 KKday（按 [HR 摘要](actai-candidate-hr-summary.md) 的约定，面试中不提 Cicada）。
- 2026-11-12 检索结果：BJAK 的招聘页把首款产品描述为 agent-first 移动通讯 App，覆盖 iOS、Android、Web；反复出现的词是长流程可靠性、持久上下文、减少幻觉，以及让人审核和纠正 AI 动作（human-in-the-loop）。

---

## A1 product notes — Jianhui Xu

**What A1 is, in one line.** A1 is an AI-first voice and text app. It works like Cursor, but for daily talk, not code. You say what you want in a chat, and it helps get it done with very few prompts.

**Who it is for first.** People who coordinate with others every day: friends, families, small teams. The first job I'd bet on is scheduling: two people agree on a time in chat, and today someone still has to create the event, send the invite and check it.

**The words that keep coming up in ActAI's job posts:** proactive, reliable on long tasks, keeps context, fewer hallucinations, the user can review and fix what the AI does. In my own words: *A1 has to act before you ask, remember what you already said, finish what it started, and never pretend it did something it didn't. And the user stays in control.*

**Judgment 1: the hardest part is when to speak, not how smart the model is.** A proactive assistant lives or dies on timing. If it jumps in too often, it costs more time than it saves, and people turn it off. If it stays quiet, it's just another chat app. So the product needs clear rules: act alone on small, safe, undoable steps; ask first before anything that affects other people, like sending a message or changing a calendar; and stay quiet when it isn't sure.

**Judgment 2: the client decides whether it *feels* smart.** With voice and text mixed together, a lot happens on the phone: streaming the answer as it arrives, reconnecting on a weak network, and handling a task where three steps worked and one failed. If the app shows a spinner and then a vague error, users think the AI is dumb, even when the model was right. If it shows what's done, what failed and one button to retry just that part, it feels reliable. That's exactly the part an Android engineer owns.

**Why I believe this: I've hit these problems myself.**
- In **CabinetAI**, my own AI assistant, people use voice or text to record expenses, set reminders and manage tasks. One agent plans, and others do the work. I learned to ask when a date is unclear, never say something worked when it didn't, keep the parts that succeeded, and retry only the part that failed. Calendar changes only happen after the user approves.
- At **KKday**, I was the technical lead of the AI trip planning project. We showed the plan day by day while it was still being generated, checked each result against business rules, and retried or fell back when a step failed.

**Three questions I'd want to answer in my first month** (from the job posts, since I couldn't find a public app yet):
1. Which coordination task do your users repeat most, and where do they still do it by hand?
2. When the assistant acts for someone, how does the user see what it plans to do, whether it worked, and how to fix it?
3. How do Android, backend and ML agree on who owns each failure, for example a message that was sent twice, or a voice note that was half transcribed?

**One suggestion to test.** A small "plan card" in the chat: before acting, the assistant shows the steps it will take; each step shows its own status (done, waiting, failed); failed steps have a one-tap retry; and anything that affects other people waits for one tap to confirm. It makes the AI's work visible, keeps the user in control, and gives us clean data on where users correct it.

**How I'd know it works.** Less time from "let's meet" to a confirmed invite, fewer corrections, and people coming back the next week.

---

## 产品理解口述版（Head）

2026-11-13 用户确认中文修订稿；下方为英文表达。用于产品理解提问；“Why ActAI?” 使用知识库对应动机回答。约见面场景是方向举例，不是已体验的正式功能。

> Based on your introduction, ActAI brings AI into everyday voice and text communication. It aims to understand what people need and help them take the next steps.
>
> I believe in this direction. People chat every day, and many tasks start in a chat. For example, friends may agree to meet on Friday. They still need to confirm the time and add it to a calendar. I see a chance for AI to help with those steps.
>
> I worked on AI trip planning at KKday. I'm also building Cabinet. I'd like to bring this experience to ActAI and help make the Android app fast and reliable. The assistant should ask when needed and clearly show the result.

追问 —— Have you used our app?

> I looked, but I couldn't find a public version yet. So I wrote a one-page note from your job posts: what I think A1 is, two judgments, and three questions I'd want to answer in my first month. I'm happy to share it.

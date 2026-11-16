# ActAI Dev 知识库 HR 表达复检（2026-11-13）

本轮只整理讨论清单，未修改任何知识库。以下是文本表达风险判断，不代表 HR 必然反感，也不是本轮逐题运行模型的实测结果。

## 范围与方法

- 全文复检 Dev 实际加载的六份知识库（00_profile 至 05_target_company，共 1536 行）。加载清单见 Sources/Cicada/Knowledge.swift。发音练习.md 不在加载列表。
- 搜索项目 outputs 内可恢复的知识库备份、*.md.before、background-used.md、candidate-background.before.md，比较旧口径与当前口径；本机备份不等于完整版本历史，不声称恢复了所有历史版本。
- 同一表达出现在多道题中合并为一组，每组保留全部涉及问题与原文。风险问题、薪资底线、真实局限不自动算消极。
- 当前六份知识库整份进入上下文；旧答案还有固定版本/逐字使用规则，局部追加正面指导并不能证明所有题的生成结果都会一致。

## 当前需要讨论的 23 组表达

### 01. [优先] 为什么经历裁员后仍加入创业公司

更新：2026-11-13 用户已确认修订，现用 Dev 与对应文档已同步。下方保留审计当时的原回答，当前版本见 [逐项讨论记录](actai-hr-answer-discussion-2026-11-13.md)。

开头把资金、核心团队稳定放在首位，产品理由靠后，最后落在远程和陪家人；容易把 ActAI 的吸引力讲成资金与个人条件。应保留真实考虑，但先讲具体产品判断。

来源：[04_talk_tracks.md:392](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:392>)

```text
## After layoffs, why join an early-stage startup that may pivot or fail?

User-approved final (2026-11-11). Use verbatim. Do not repeat the Kezhi funding lesson in "Why not a big company".

That's a fair question. Kezhi taught me to look at two things before joining a startup: how the business is funded, and whether the core team is committed.

At Kezhi, revenue depended on public schools, and payments were slow. When the core team left, there was nothing left to build.

From what I understand, ActAI is different on both points. It's funded by a group that has been profitable since it started, and I'd work directly with the founder and CTO.

The product also fits what I've been doing. At KKday, I worked on how an AI plan shows up on the phone while it's still being generated. In my own project, CabinetAI, people can use voice or text to record expenses, set reminders and manage tasks, and it asks before it takes important actions. ActAI is the same idea in everyday communication.

If the product changes direction, that's normal for a startup. I'd watch whether the core people are still committed. If they are, I'd stay and help with the new direction.

And honestly, the remote and hybrid setup also helps me spend more time with my son.
```

### 02. [优先] 为什么不自己创业

更新：2026-11-13 用户已确认修订，Dev 与全题参考答案已同步。下方保留审计原文，当前版本见逐项讨论记录。

直接把 ActAI 的优势归结为团队、钱、找用户的时间；适用于许多有资金的公司，没有回答为什么选择 ActAI 的沟通产品。

来源：[04_talk_tracks.md:1124](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:1124>)

```text
## You've built a personal AI assistant yourself. Why not just start your own company?

Because a good product needs much more than me. It needs a team, money and time to find users. ActAI has all three. CabinetAI was for learning. I'd rather put what I learned into a product that can really reach people.
```

### 03. [优先] 如何相信你会长期留下

更新：2026-11-13 用户已确认修订，Dev 与全题参考答案已同步。下方保留审计原文，当前版本见逐项讨论记录。

以不能承诺永久留下开场，继而解释过去离开，再把留下的条件收缩为核心人员是否还在；缺少对产品方向、长期贡献的积极承诺。不需要承诺永不离职。

来源：[04_talk_tracks.md:738](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:738>)

```text
## Two layoffs and a team that disbanded. How do I know you won't leave us after a year?

Fair question. I can't promise forever, and nobody honestly can. What I can tell you is what makes me stay. I stayed at Ping An for almost six years. My last moves weren't my choice, except Kezhi, where the team was already gone. If ActAI changes direction, I'd look at one thing: are the core people still committed? If they are, I'd stay and help with the new direction.
```

### 04. [优先] 你了解我们的产品吗

更新：2026-11-13 用户已确认修订，Dev 与产品理解文档已同步。下方保留审计原文，当前版本见逐项讨论记录。

概念介绍之后主要讲用户离开、打扰、弱网、失败，具体的日常沟通价值展开不足；容易显得先评判风险再表态。技术判断可以保留，调整主次。

来源：[04_talk_tracks.md:654](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:654>)

```text
## What do you know about our product? (Tell me what A1 / ActAI does. What do you think of our product?)

Use when asked what I know about the product. Base it only on the company introduction and job posts; there is no public app, so never say I used it. Don't mention Cicada.

From what I've read, A1 is an AI-first voice and text app. It's like Cursor, but for daily talk, not code. You say what you want, and it helps get it done with very few prompts.

I think two things will decide if people stay. First, timing. The hard part isn't the model. It's knowing when to jump in and when to stay quiet. Too many interruptions, and people turn it off. Second, the phone side. When voice and text are mixed, and the network is weak, the app has to stream the answer, recover, and show clearly what worked and what failed. That's what makes it feel smart, and that's the part I'd own as an Android engineer.

I've run into both in my own work. In CabinetAI, my AI assistant, I had to decide when it can act alone and when it must ask, and how to retry only the part that failed. At KKday, we showed the AI trip plan day by day while it was still being generated. So it's not just that I'm interested in AI. I've hit these problems myself.
```

### 05. [优先] 加入前还想了解产品什么

更新：2026-11-13 用户已确认修订，Dev 与全题参考答案已同步。下方保留审计原文，当前版本见逐项讨论记录。

问题合理，但结尾把少提示是否真的省时作为主要怀疑；可先表达为何看好，再说明想了解哪个高频场景与落地进展。

来源：[04_talk_tracks.md:642](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:642>)

```text
## What would you want to learn about our product before deciding to join?

Three things. Which task you want users to trust ActAI with first. How you decide when the assistant acts on its own and when it asks. And how product, Android and ML decide together when something goes wrong. The assumption I'd most want to test is that fewer prompts really save time, and that the questions it asks don't cost more than they save.
```

### 06. [讨论] 如何解释 Cursor for everyone

更新：2026-11-13 用户已确认修订，Dev 与全题参考答案已同步。下方保留审计原文，当前版本见逐项讨论记录。

开头例子具体，但解释产品时额外转向用户迁移困难、已有 WhatsApp 等工具；容易把产品介绍变成质疑采用率。日历/邀请例子应表述为对方向的理解，不冒充已发布功能。

来源：[04_talk_tracks.md:626](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:626>)

```text
## How would you explain “Cursor for everyone” in practical user terms?

Cursor lets programmers say what they want, and it writes the code with them. ActAI does that for daily life. You say "let's meet Friday with Anna," and it handles the calendar, the invite and the reminder. The hard part is adoption. People already have WhatsApp and their calendar app. So it has to save time on something they do every day, from day one.
```

### 07. [优先] 你和只说喜欢 AI 的候选人有什么不同

更新：2026-11-13 用户已确认修订，Dev 与全题参考答案已同步。下方保留审计原文，当前版本见逐项讨论记录。

说已交付 AI 是优点，但对 ActAI 的具体判断仍只有通用的信任、何时行动、何时询问；没有充分回应此前 Head 反馈。

来源：[04_talk_tracks.md:1136](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:1136>)

```text
## The last candidate told us they love AI. Everyone says that. What's different about you?

I don't just love AI; I've shipped it and built it myself. I know what goes wrong when it's slow or wrong, and I've built the phone side that handles it. And I've thought about your product specifically: the hard part is trust, knowing when to act and when to ask.
```

### 08. [优先] 为什么录用你

更新：2026-11-13 用户已确认修订，Dev 与全题参考答案已同步。下方保留审计原文，当前版本见逐项讨论记录。

把 ActAI 目标泛化为 plan anyone’s life，并花大量篇幅讲 Cabinet；与当前日常沟通定位不够贴合。Cabinet 全部端作者身份也不应由此推断。

来源：[04_talk_tracks.md:104](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:104>)

```text
## Why should we hire you? What are your strengths?

There are two reasons. First, I already work on the same idea. In May, I started planning my own app, Cabinet, in my spare time. In October, I started building it for real. I built the app, the backend and the website alone. You tell it what to remember, spend or plan. One agent understands you. Other agents do the work. Your goal is to plan anyone's life with almost no prompts. Cabinet follows the same idea. Second, I've done both Android and AI at scale. At KKday, I led our AI trip planner. It made about 300,000 plans a day. A traveler typed "Tokyo, three days, 5,000 yuan." Then they got a plan they could book. I built the app screens and the backend together. So I won't start from zero. This is also personal for me. I will care about your app like my own.
```

### 09. [讨论] 为什么 ActAI 的一分钟版

更新：2026-11-13 用户授权仅优化一分钟版，已同步 Dev 和全题参考答案；原完整版本保留未变。下方保留审计原文。

短版保留 AI for everyone / 无复杂提示，却省略完整版本已有的日常沟通、协调场景；缩短时丢掉了最能区分公司的内容。此版本带固定逐字使用规则，需讨论后再改。

来源：[04_talk_tracks.md:44](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:44>)

```text
## Why do you want to join ActAI? (Why this company? Why us? Why are you interested in this role?)

### One-minute version (only when asked for one minute or a short version)

There are three reasons.

First, ActAI's product and my own product share a similar direction.
In May, I started designing an AI agent in my spare time. It's called Cabinet.
It checks my calendar, the weather and my budget. Then it gives me a good plan.
ActAI builds proactive AI products for everyone. People don't need to write complex prompts.
So I have real interest in this direction. I also have real experience.

Second, ActAI needs someone to make AI fast and stable on Android. That's my strength.
I have ten years of experience, mostly on Android.
At KKday, I cut the first-screen loading time on Android. It went from three seconds to under one second.

Third, I want to join a startup like ActAI.
You need to bring structure, make decisions, and move fast.
I've done this before. At Kezhi, I was the only Android engineer.
I built the whole Android app myself, from zero to launch, in four weeks.

So I want to build a great product with ActAI. I want people to trust it and use it every day.
```

### 10. [讨论] 还有其他 offer 吗

更新：2026-11-13 用户已确认并授权同类问题联动修改，当前 Dev 与参考文档已同步；下方保留审计原文。第 14 项中“已有金融 offer”的表达亦在本次联动修正。

first choice if the package works 把首选和薪资条件紧贴，缺少具体选择理由；待遇合适是合理条件，问题在此处如何组织表达。

来源：[04_talk_tracks.md:226](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:226>)

```text
## Do you have other offers right now?

Say only that some are still under discussion. Never say "I have other offers", and don't name companies or amounts.

Some are still under discussion. I expect to decide within a few weeks. ActAI is my first choice if the package works.
```

### 11. [讨论] ActAI 是否只是众多选择之一

更新：2026-11-13 用户已确认修订，Dev 与全题参考答案已同步；下方保留审计原文。

理由主要是 AI-first 和自己做过类似产品，仍可套用很多 AI 公司；对其他公司的 traditional apps 描述也过于概括。

来源：[04_talk_tracks.md:1164](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:1164>)

```text
## You're interviewing with finance and securities companies too. Isn't ActAI just one option among many?

It's one option, but it's the one I want most. The others are traditional apps. ActAI is AI-first, and it's the kind of product I've been building on my own time. If we're a fit, I'd decide quickly.
```

### 12. [讨论] 离职复盘反复落在资金与团队

进度：2026-11-13 第 12 项三题均已确认并同步 Dev 与全题参考答案。失败项目题采用可之 AI 作业批改第一版缺少历史错题归类、总结与分析的案例；后续改进为复盘建议，不声称已实现或已提分。下方保留审计原文。

三道不同问题都导向先检查资金与核心团队，05_target_company 的 Choices 也重复此结论。单独谈企业风险合理，但高频重复会挤掉产品、用户和贡献判断；失败项目复盘还缺少自己能改进的交付/验证动作，不能编造业务数据补充。

来源：[04_talk_tracks.md:726](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:726>)

```text
## How did you handle the transition after your role was affected?

I handed my work over first. Then I took a month off, which I hadn't done in years. I travelled and spent time with my grandmother. In October I started looking, with a clearer idea of what I want. The main lesson was about choosing a team: check the funding and whether the core team is committed.
```

来源：[04_talk_tracks.md:734](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:734>)

```text
## Looking back, is there any move you would make differently?

I'd ask more questions before joining Kezhi: how the business makes money, and how committed the core team is. I learned a lot there, but I didn't look at the business closely enough. Now I ask those questions first, and I'm asking them here too.
```

来源：[04_talk_tracks.md:772](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:772>)

```text
## Tell me about a project that did not achieve the result you expected.

Kezhi. Technically, it went well. I built the whole Android app from zero to launch in four weeks, and I also worked on the question-answering system. But the business didn't work out. It depended on public schools, and payments were slow. Then the core team left. What I missed was looking at the business model before I joined. I only looked at the technical challenge. Now I ask about funding and the core team first.
```

### 13. [优先] 7H 哪项最能代表你

进度：2026-11-13 用户确认 45–60 秒 Hands 英文最终版，已同步 Dev 与全题参考答案；不再主动补充 Hustle 弱项。下方保留审计原文。

回答最强项 Hands 后，主动增加 weakest…Hustle。问题未问弱点，而 HR 已明确关注 Hustle，属于不必要的自我减分。

来源：[04_talk_tracks.md:1008](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:1008>)

```text
## We look for 7H. Which one describes you best? Give me an example.

Hands. I build things myself. At KKday I wrote core Android features and built the planner's backend. In my spare time I built CabinetAI: the app, the backend and the website. The weakest one for me is probably Hustle in one sense: I like to plan before I move. But I've learned to ship first when the team needs it.
```

### 14. [优先] 你是否更想找轻松工作

进度：2026-11-13 已单独修订：采用用户审定英文：轻松不是主要目标，更看重产品与贡献，愿意承担压力和责任，以可知四周上线佐证，并落到 ActAI 与 Android/AI 经验。下方保留审计原文。

假设金融工作更轻松，且说 one of my offers 与当前只能说仍在讨论的口径冲突；wrong things 带对抗意味。

来源：[04_talk_tracks.md:962](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:962>)

```text
## Your answers sound balanced. But honestly, would you rather have a calm job?

If I wanted a calm job, I'd take one of my offers in finance. I'm here because I want to build something new, and that's never calm. What I want is a team that works hard on the right things, not hard on the wrong things.
```

### 15. [讨论] 能否全力投入创业公司

Yes, when it matters 与 won’t…wrong thing 容易显得先限定再拒绝；可以用实际优先级判断、冲刺和交付说明投入，而不取消家庭边界。

来源：[04_talk_tracks.md:1140](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:1140>)

```text
## You told me rest and family matter. Startups need people who can go all in. Is that you?

Yes, when it matters. I'll put in the hours for a launch. Family is why I want this to work, not a reason I'll hold back. What I won't do is work hard on the wrong thing. I'll push to know what matters most, and put my time there.
```

### 16. [讨论] 优先级变化、上线冲刺与周末工作

回答已有积极交付证据，但反复以 every week、planning wrong、calmer 收尾；作为单题有边界很合理，多题累积可能压过快速适应与投入。尤其 planning wrong 是未经了解的归因。

来源：[04_talk_tracks.md:370](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:370>)

```text
## Priorities change mid-sprint

First, I'd ask what must work for users on launch day. Say sending messages isn't stable. Then I'd move a nice extra screen out of the sprint. I'd spend my time on sending. I'd tell the team what changed and when they can test it. A short push is fine. But if every week feels like launch week, we should talk about it.
```

来源：[04_talk_tracks.md:932](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:932>)

```text
## How do you handle a short period of intense work before a critical launch?

I'm fine with it when there's a clear goal and an end date. At Kezhi, I built the whole Android app alone, from zero to launch, in four weeks. Back then, AI coding tools weren't good enough, so I wrote and worked out almost all of it myself. I'd focus on what must work on launch day and drop the rest. I'd also protect quality: no skipping tests on the core flow. Afterwards, we look at why it was intense, so the next launch is calmer.
```

来源：[04_talk_tracks.md:940](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:940>)

```text
## Are you willing to work evenings or weekends before a launch?

When the product needs it, I'm there. For an important launch with a clear goal, I'll do what it takes. What I'd watch is whether it becomes every week. If it does, we're planning wrong, and I'd raise it so we can fix the plan.
```

### 17. [讨论] 维护工作、拒绝 offer 与 deal-breaker

三题及 01_job_target 重复强调主要维护/缺少产品决定权就犹豫。不是必须放弃偏好，但应区别必要维护与长期职责不匹配，避免像排斥基础可靠性工作。

来源：[04_talk_tracks.md:602](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:602>)

```text
## What would be a deal-breaker for you?

If the job were mostly maintenance, with no say in what users experience. I'm looking for a role where I help shape the feature, and stay responsible for how it works after launch.
```

来源：[04_talk_tracks.md:1152](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:1152>)

```text
## What would you do if, after three months, you realized the role was mostly maintenance?

I'd talk to my manager first, not leave. I'd ask what's coming and where I can help most, and offer to take on something new. Usually maintenance shows you what needs to be rebuilt. If nothing changed after a real conversation, then I'd think again.
```

来源：[04_talk_tracks.md:1172](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:1172>)

```text
## What would make you reject an offer?

If the job turned out to be mainly maintenance, with little say in what users experience. I'm looking for a role where I help shape the feature and stay responsible for how it works after launch.
```

### 18. [讨论] 从前 30% 到前 10% 还差什么

主要归因于更长任期和更多曝光机会，主动改进、扩大贡献和跨团队结果不够明确；可能让成长意愿显得被动。不能编造绩效标准。

来源：[04_talk_tracks.md:432](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:432>)

```text
## You were top 30%. What would it have taken to be top 10%?

User-approved final (2026-11-11). Use verbatim. Do not criticize colleagues.

At KKday, our manager gave ratings based on our past work and feedback from colleagues. I'd been there about a year and a half. It takes time for a team to get used to a new person, and for that person to learn how the team works. My work got better steadily over that time.

To reach the top 10%, I think I needed a longer track record there, and more chances for my work to be seen beyond my own project.
```

### 19. [讨论] 为什么做 AI 助手而非传统 Android

兴趣几乎全部落在错误、等待、模糊与纠错；对主动完成任务给用户带来的价值讲得少。技术兴趣合理，需补上积极产品动机。

来源：[04_talk_tracks.md:992](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:992>)

```text
## Why an AI assistant rather than a traditional Android role?

I like problems users can feel. In a normal app, a tap has a predictable result. With an assistant, the answer comes in pieces, can be wrong, or the request can be unclear. Deciding what the user sees while they wait, and how they fix a mistake, is the part I enjoy. It uses the Android I know well, on a problem I want to work on.
```

### 20. [优先] 你有什么问题想问我

现有答案只有我可以问 hiring manager，没有任何提问，且预设 HR 不能答。05_target_company 已有五个可用问题，两处口径冲突。

来源：[04_talk_tracks.md:1194](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:1194>)

```text
## What questions do you have for me?

No problem, I can ask the hiring manager about that.
```

### 21. [讨论] 其他候选人的英语更强

English I can improve in months 没有依据，也可能显得低估全球协作的语言要求；可用真实协作方式和提升行动回应，保留已有技术优势。

来源：[04_talk_tracks.md:1160](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:1160>)

```text
## We have several candidates with stronger English. Convince me in thirty seconds.

My English is good enough to work and explain clearly, and I'm improving it. What's harder to find is someone who has built AI features used 300,000 times a day and ten years of Android. English I can improve in months. That experience takes years.
```

### 22. [讨论] Cabinet 用户少、继续维护与利益冲突

not a business、no business、Not a business and I don’t claim that 多次防御式降调；个人探索的定位必须如实保留，但可以先解释已验证的能力和仍未验证的商业结果。停止维护的承诺是既有明确口径，不在本轮擅自改动。

来源：[04_talk_tracks.md:356](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:356>)

```text
## Will you keep working on Cabinet? (Why join us instead of Cabinet? Side project?)

Only for an explicit question about continuing the side project or commitment. Never append this answer to a general Cabinet product introduction.

It's a personal project, not a business. It's in internal testing on TestFlight now, with a small group of users. If I join ActAI, I'll stop working on it. I want my full focus here.

Follow-up — Why iOS? Is there an Android version?
There's an Android version too. I wrote it in my spare time. I built the base framework myself and used AI coding tools for the simpler screens, which saved a lot of time. It isn't on Google Play yet, because I'm still finishing the integration testing and the Play setup. The iOS build just reached testing first.

Follow-up — How do you stay accountable for AI-written code?
I write the core architecture myself, and I review and test everything the tools generate before it goes in.

I personally developed CabinetAI (app, backend and website), with help from AI coding tools. Do not mention Cicada.
```

来源：[04_talk_tracks.md:1096](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:1096>)

```text
## Do you have any conflicts of interest or outside commitments relevant to this role?

No conflicts. My only side project is CabinetAI, a personal project with no business. If I join, I'll stop working on it.
```

来源：[04_talk_tracks.md:1128](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:1128>)

```text
## CabinetAI has very few users. What does it actually prove?

Not a business, and I don't claim that. It proves I can build an agent product end to end by myself, and that I've already faced the questions ActAI faces: when to act, when to ask, and how to recover when something fails.
```

### 23. [讨论] 为什么要求如此大幅涨薪

I’m not asking for a raise…market price 容易像纠正 HR，市场价也不等于已确认报价；应积极解释岗位责任和经验价值。并非现金优先本身有问题。

来源：[04_talk_tracks.md:232](</Users/xiaohui/Library/Application Support/LiveSubs Dev/knowledge/04_talk_tracks.md:232>)

```text
## That's a big jump from your last job. Why should we pay that much? (Why such a big raise?)

Don't use the SKU speed story here. Talk about what the role is worth, not about needing a raise.

I'm not asking for a raise. I'm asking for the market price of this role. It needs senior Android and real AI product work together, and I've done both. At KKday, I was the technical lead of the AI trip planner, which handled about 300,000 planning tasks a day. And in my own app, CabinetAI, I built voice and text with AI agents on the phone. My last role was mostly Android, with AI as one project. Here AI on the phone is the core product, so the role's range is a better guide than my last package.
```

## 需要单独核对的旧口径冲突

04_talk_tracks.md:238 的“略低于范围”仍按年现金约 500K 以上触发，并试探 600K；01_job_target.md 当前则按所述招聘区间、现金保证月份等条件讨论 50–55K × 15。它不是产品信心问题，但可能让薪资回答漂移，应单独讨论，不能在本轮擅自替用户改价格。

05_target_company.md 的 Choices 仍强调盈利集团与资金，而末尾新增信心指引要求资金只作背景；需与第 1、12 组一起讨论。

## 暂不建议当作消极回答删除

- 现金优先、了解股权条款、不拿现金换股权：是用户已有薪资偏好；只在相应问题使用。
- 未用过 ActAI 公共产品、未确认的功能：必须诚实，不编造亲身体验。
- Cabinet 用户少、Android 集成/上架仍在进行：必须保留事实，不能把探索写成商业成功。
- 模型训练、端侧 ML、设计经验的真实局限：可以温和说明，不编造成擅长。
- 被明确问隐私、失败或最难挑战时，谈风险、确认机制、错误恢复和人工接管是合题内容。第 630 行的“一次出错用户就弃用”较绝对，可润色，但不是不看好产品的证据。
- 家庭、远程偏好、合理工作边界与过去裁员事实：不因积极表达而隐瞒，讨论重点是顺序、场景与措辞。

## 仅存在于历史快照的相关口径

- outputs/cabinet-learning-2026-11-11/04_talk_tracks.md.before 仍保留旧 C14：I can’t be sure anyone will win / money and time / change their habits。当前 Dev 对应题已更新，不列为当前未修问题。
- 历史竞争对手回答曾把无需迁移应用放在竞争者优势中；当前对应题已改为积极解释 ActAI 的沟通到行动机会，不能把旧测试输出当作当前行为。
- 历史 03_projects.md.before 在 Cabinet 状态介绍中无条件附带加入后停止维护；当前已限制在明确追问继续维护或投入时回答。
- 历史报价、其他 offer 状态存在已被更新的版本；当前仍残留的 offer 用词见第 14 组，报价冲突见上节。

建议讨论顺序：1 → 2 → 3 → 4 → 7 → 13 → 20，再处理其余各项。先确认事实与立场，再写候选答案；用户确认后统一更新所有重复位置，并在 Dev 对同义提问实测。

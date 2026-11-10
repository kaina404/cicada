# ActAI HR 补充问题：定稿回答

2026-11-11 与用户逐题讨论后的定稿，对应 [HR 摘要](actai-candidate-hr-summary.md) 的 10 题之外、HR 可能追问的问题。事实来自用户本人确认（见摘要末尾各补充段），英文回答已落进 Assistant 知识库 `04_talk_tracks.md`。这些是预测问题，不是 ActAI 真题。

## 使用原则

- 最近三段是**两次裁员（KKday、德邦）+ 一次团队解散后主动离开（可之）**。HR 说“三次被裁”时先温和纠正。
- 同一场面试里 SKU（1s → 300ms）只在 D1 完整讲一次，其他题换例子。
- HR 层面只到职责、理由、用户价值和态度；测量口径、技术细节留给技术面。
- 不说：可之“快破产”、补偿金额（只说四个月工资）、在谈 offer 的公司名、Cicada、iOS 代码是本人写的。

## 一、简历引出的追问

### 1. 为什么最近三段都结束了（被裁的是你？）

> Just to be precise, two of them were layoffs, and one was my own decision.
>
> At KKday, the business line was shrinking. Most of the people they kept had been there longer than me. I'd joined about a year and a half earlier. My performance was in the top 30% of the Tour team, so I don't think it was about my work.
>
> Debon was similar. The business had struggled for two years, and our Android team went from three people to one. They kept the longest-serving engineer. Before I left, my work had shipped and I handed everything over cleanly.
>
> Kezhi was different. After the team was disbanded, there was no real product work left, and the company's future was unclear. Many people left, and I decided to leave too.

短版：

> Two were layoffs, and one was my choice. At KKday and Debon, the business was shrinking, and the company mostly kept people who'd been there longer. At KKday I was in the top 30% of my team. At Kezhi, the team was disbanded and there was no real work left, so I left.

追问 —— 两次都按资历留人，是不是你每家都待不久？

> Not always. I stayed at Ping An for almost six years. The last few years were just hard for a lot of companies.

追问 —— 为什么不留下来帮可之翻盘？

> By then, most of the team had already left: the backend engineers, the web engineers and the core algorithm people. The business depended on selling to public schools, and getting paid was slow and difficult. An Android engineer alone couldn't rebuild that. If the core team had stayed, I would have stayed too.

追问 —— 拿了补偿吗？

> Yes, I received the standard package. *(只有被追问金额时：four months' pay.)*

### 2. 被裁过，为什么还选创业公司？

> That's a fair question. Kezhi taught me to look at two things before joining a startup: how the business is funded, and whether the core team is committed.
>
> At Kezhi, revenue depended on public schools, and payments were slow. When the core team left, there was nothing left to build.
>
> From what I understand, ActAI is different on both points. It's funded by a group that has been profitable since it started, and I'd work directly with the founder and CTO.
>
> The product also fits what I've been doing. At KKday, I worked on how an AI plan shows up on the phone while it's still being generated. In my own project, CabinetAI, people can use voice or text to record expenses, set reminders and manage tasks, and it asks before it takes important actions. ActAI is the same idea in everyday communication.
>
> If the product changes direction, that's normal for a startup. I'd watch whether the core people are still committed. If they are, I'd stay and help with the new direction.
>
> And honestly, the remote and hybrid setup also helps me spend more time with my son.

### 3. 8 月以来在做什么？

> After KKday, I took September off. I travelled a bit and spent time with my grandmother back home. She raised me, so that time mattered to me.
>
> I started looking again after the October holiday. That was about a month ago. So far I've talked to four companies, in finance, securities and e-commerce, and a few are at the offer stage.
>
> But ActAI is the one I'm most interested in, because it's an AI-first product, not a traditional app with AI added on.

追问 —— 时间线 / 有截止日期吗？

> Nothing urgent yet, but I'd expect to decide in the next few weeks. I'd be happy to move quickly if things go well here.

### 4. 职级从 Senior Architect 变成 Full-Stack Engineer

> Titles mean different things at different companies. At Kezhi, the app team was five people, and I reported to the CTO, so "architect" covered a lot. KKday is a much bigger company with its own title system.
>
> The work itself didn't get smaller. I led the technical work on the AI itinerary project, and the system handled about 300,000 planning tasks a day.
>
> I chose KKday because it was a strong company, I was referred by someone there, and it was close to home. The title wasn't what I was looking at.

追问 —— 你是架构师还是动手写代码的？

> Both. At KKday I was leading the project, so about 30% of my time was coding. The rest was architecture, product analysis and data research. Before that, at Kezhi and Debon, I was much more hands-on.
>
> In a small team like yours, I'm happy to spend most of my day coding again. The product analysis part still helps, because I can see what users need before I build it.

### 5. 在可之从 Android 转去做 RAG，为什么又回来？

> It wasn't really a switch. At Kezhi, I did both at the same time. I kept building the Android app, and I also worked on the RAG question-answering system.
>
> Android has been the constant through my whole career. AI is something I learned by using it in real products, first at Kezhi, then at KKday.
>
> So for me, this role isn't coming back to Android. It's where both parts of my experience meet.

### 6. 前 30%，怎样才能进前 10%？（只有主动提了才可能被问）

> At KKday, our manager gave ratings based on our past work and feedback from colleagues. I'd been there about a year and a half. It takes time for a team to get used to a new person, and for that person to learn how the team works. My work got better steadily over that time.
>
> To reach the top 10%, I think I needed a longer track record there, and more chances for my work to be seen beyond my own project.

### 7. CabinetAI 是生意吗？加入后还继续做吗？

> It's a personal project, not a business. It's in internal testing on TestFlight now, with a small group of users. If I join ActAI, I'll stop working on it. I want my full focus here.

追问 —— 为什么是 iOS？有 Android 版吗？

> There's an Android version too. I wrote it in my spare time. I built the base framework myself and used AI coding tools for the simpler screens, which saved a lot of time. It isn't on Google Play yet, because I'm still finishing the integration testing and the Play setup. The iOS build just reached testing first.

追问 —— 怎么为 AI 写的代码负责？（需本人确认确有审查和测试）

> I write the core architecture myself, and I review and test everything the tools generate before it goes in.

## 二、技术栈初步核实

### 8. 最近什么时候写的生产 Kotlin？用过 Compose 吗？

> Until August this year, at KKday. Everything was in Kotlin. I introduced Jetpack Compose there, and all our Android screens were rebuilt with it. More recently, I've built the Android version of CabinetAI, also with Kotlin and Compose.

### 9. 哪个最近的 Android 项目最能说明你能贡献什么？（D1）

> One I'm proud of is the product page at KKday. When a traveller tapped a tour, it took about a second before the options and prices appeared. That's long enough to feel slow.
>
> I looked into it and found the app was reading the same data again and again, and doing heavy calculations at the moment the page opened. So I simplified the data, prepared the price and stock lookups in advance, moved the heavy work into the background, and cached the results.
>
> It went from about one second to about 300 milliseconds. For ActAI, it's the same idea: when an assistant answers, the user should see something right away.

### 10. Android 上的语音经验

> Some. At Ping An Haoxue, I packaged our live classroom, including its audio and video, into an SDK that both the student tablet app and the parents' phone app could use. More recently, in CabinetAI, people can speak instead of typing on both iOS and Android. I used ElevenLabs for the speech-to-text.
>
> I haven't built speech models myself. My side is the app: making voice input feel quick and natural, and handling it well when something goes wrong.

### 11. 做过面向全球用户 / Google Play 的应用吗？

> Yes. KKday is a global travel platform, and our Android app is on Google Play, used by travellers in many markets and languages. Before that, my work was mostly for users in China. CabinetAI's Android version will go on Google Play once I finish testing.

## 三、Head：AI 敏感度与产品判断

### 12. 每天用哪些 AI 产品？最烦什么？

> I use AI tools every day, mostly for coding. I use Codex and ChatGPT for architecture and product research, and Claude for deeper coding and building base frameworks. I also use Grok.
>
> What frustrates me most is context. On long tasks they forget things, and when I switch between projects, I have to explain everything again.
>
> I think a real assistant should work from one place. You give it a goal, and it uses what it already knows to decide the next steps. You shouldn't have to tell it every step.
>
> That's a big reason ActAI caught my attention. Your job post talks about keeping context and finishing multi-step tasks with minimal prompting. That's exactly the problem I feel every day.

追问 —— 那助手就该全自动吗？

> Mostly, yes, but not for everything. Routine steps should just happen. But before anything important, like changing someone's calendar or sending a message, it should check first. In CabinetAI, calendar changes only happen after the user approves them. The hard part is deciding where that line is.

### 13. 怎么看 Meta AI / Gemini？用户为什么要换？

> Their biggest advantage is that people don't have to switch apps. So for ActAI to win, it has to fix a problem people hit again and again, and the benefit has to be big enough to be worth installing another app.
>
> From what I've seen, those assistants mostly wait for you to ask. ActAI's idea is to help before you have to ask.
>
> In CabinetAI, I've been working on the same question: once someone says what they want, can we cut out the copying and manual steps? For example, if a voice message mentions a meeting time, some materials to prepare and a deadline, the assistant should turn that into a short list for me to confirm, and then carry on. I shouldn't have to listen again and type it all in.
>
> I don't expect people to leave WhatsApp on day one. More likely, they start using ActAI for one task, find it saves them steps every day, and gradually move more conversations over.
>
> So what matters to me isn't how many AI features there are. It's whether getting from saying it to getting it done feels natural, fast and reliable. That's where I want to bring my Android and AI experience together.

追问 —— 怎么判断它有效？

> I'd look at three things: how much time it saves before something is agreed, how often people have to correct it, and whether they come back the next week. If people keep correcting it, the extra steps might cost more time than it saves.

### 14. 读聊天的助手，怎么看隐私和信任？

> I think what people fear most is something they said privately showing up somewhere they didn't expect. Say I talk to a friend about changing jobs, and later the AI mentions it in a message it drafts to my colleague. Nothing leaked, but I'd stop trusting it.
>
> So consent can't be a single checkbox at sign-up. People should see which chats the AI can read and what it keeps, and be able to take that back at any time. A deleted memory should never come back. And anything that affects other people, like sending a message or sharing something, should show me the content and the recipient first.
>
> To me, a trustworthy assistant makes its limits clear and leaves the user in control.

### 15. 为什么不去大厂？

> I'm not against big companies. But looking back, the work I've enjoyed most was at a startup. At Kezhi, I built the Android app and, at the same time, worked on the RAG question-answering system. I found I really like picking up a new technology to solve a real problem and building it into a product.
>
> That's also why I built CabinetAI in my own time: to learn and test new technology on a real product. It's about AI understanding what people need and helping with everyday tasks. ActAI starts from communication, which is very close to that: people express a lot of needs in chat, and the question is how AI can help get those things done.
>
> So what draws me is the startup way of working and the product fit. I want to put my Android and AI experience into a product I'll want to stay with for a long time.

## 四、早期团队里的角色

### 16. 没有 QA 和发布工程师，你愿意自己负责测试和发布吗？

> Yes. Testing and releases have always been part of my job. At Kezhi, I was the only Android engineer, so besides building features, I also handled testing and releases, and the team shipped the first version in four weeks. I'm happy to own a feature all the way to launch and keep an eye on how it does afterwards.

### 17. 面试或招聘过工程师吗？

> Yes. I did technical interviews when we were hiring at Kezhi and at KKday. I usually pick one real problem from the candidate's project and follow it: what they were responsible for, how they made the call, why they chose that approach, and how they checked the result. That tells me what they actually did and how they think when things get hard.

### 18. 上一位主管会说你最大的弱点是什么？

> My manager at KKday once told me to keep the scope of my changes under control. There was a feature I could have built on the existing architecture. It needed quite a lot of code, so I wanted to improve that part of the architecture at the same time, to make future work easier. But that made the release take longer.
>
> That taught me that even a good long-term improvement needs the right timing. Now, when this comes up, I describe the feature and the architecture work separately, and agree with the team whether it's worth doing both in this release.

追问 —— 在创业公司你就不做架构了？

> No, but I'd make it a separate decision. Sometimes doing it now saves time next month. Sometimes shipping first is the right call. The team should choose, not me alone.

（问“你的弱点”时用模型训练那条；问“主管会说”时用这条。）

### 19. 可以联系你的推荐人吗？

> Yes. My team lead at KKday can speak to my work there. I'm happy to share his contact details when you need them.

面试前先联系主管，提醒 AI 行程项目、SKU 优化、Compose 迁移。主管性别不同时把 his 改成 her。

## 五、条件与流程

### 20. 地点 / 远程

> I'd prefer remote, but I'm happy to work from Beijing if the team needs it. My son is older now, so moving is much easier than it used to be. I'd just come back to Shanghai every month or two.

### 21. 出差

> Yes, occasional travel is fine. I'd just like to get home to see my son every month or two.

### 22. 竞业限制

> No, I don't have a non-compete.

### 23. 用简单英语讲一个技术点

骨架屏（KKday）：

> In our app, loading data and showing the page takes time. So I added a skeleton screen first, which is a simple placeholder for the content. We also reuse cached images when we have them, so users don't have to wait for them to download again.
>
> As the data comes back, we fill in the content with smooth transitions. That way users can see the page is loading, instead of staring at a blank screen.

RAG（可之）：

> At Kezhi, I worked on an AI tool that answers students' questions using their learning materials.
>
> Instead of asking the AI to answer from memory, we first find the right content in the textbooks. We narrow the search by subject, grade and chapter, so we don't mix up different courses.
>
> Then we give that content to the AI to help it answer. It's like an open-book exam: find the right material first, then explain the answer. That way, the answers stay accurate and match what the students are actually learning.

练习：念到脱稿；每句一口气说完；忘词时说 "In short…" 再用一句话收尾。

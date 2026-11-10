# ActAI HR 问题 Assistant 验证（2026-11-11）

题库 `tools/actai-hr-question-bank.json` 共 108 题（基准 10 题 16、资料补充 60、预测新增 32），在隔离开发版里用 DeepSeek 逐题注入，脚本 `tools/hr-assistant-check.py`。

结果：失败 0；待本人留意 2（B10, F40）；误报 3（F01, N01, N30，已在条目内注明）；其余通过。标“重跑”的题是修正脚本或知识库后的结果。知识库 `04_talk_tracks.md` 开头的“Rules for every answer”约束 SKU 例子、用户反馈、裁员范围、薪资描述、可之 Bugly 与工作许可。

## ✅ B01 · 基准10题 · 10题①

**Q:** Why are you exploring new opportunities?

**A:** I left KKday in August 2026. The Shanghai office cut many jobs, and I was one of them. So I'm using this time to choose carefully. I'm looking for three things. First, AI on mobile is the core product, not a side feature. Second, I own the Android experience from start to finish. Third, a small team where I work closely with backend and AI engineers. At KKday, I worked on both sides of an AI feature. How the planner built an answer, and how a traveler actually used it. I want more of that, on Android. ActAI fits all three.

## ✅ B02 · 基准10题 · 10题①

**Q:** Why do you want to join ActAI specifically?

**A:** There are three reasons. First, ActAI's product and my own product share a similar direction. In May, I started designing an AI agent in my spare time. It's called Cabinet. For example, I plan a three-day trip. I need to check my calendar, the weather, and my budget. Checking them one by one is slow. And I can easily miss something. Cabinet thinks of all this for me. Then it gives me a good plan. ActAI builds proactive AI products for everyone. People don't need to write complex prompts. The first product starts with communication. It puts an agent at the center. The goal is to make coordination between people easier. Here is my understanding. Friends agree on a Friday meeting in a chat. Then the agent sets it up for them. So I have real interest in this direction. I also have real experience. Second, ActAI needs someone to make AI fast and stable on Android. That's my strength. I have ten years of experience, mostly on Android. At KKday, I cut the first-screen loading time on Android. It went from three seconds to under one second. I also showed AI results step by step. Users didn't have to wait. At Ping An Haoxue, I improved a classroom app on cheap Android tablets. It ran smoothly, even on low-end devices. Third, I want to join a startup like ActAI. In a startup, nobody writes every detail for you. You need to bring structure, make decisions, and move fast. I like this way of working. I can help shape the product. And I own the results. I've done this before. At Kezhi, the product was brand new. I reported to the CTO. I was the only Android engineer. I built the base of the Android app from zero. Our team built the first version in four weeks. So I want to build a great product with ActAI. I want people to trust it and use it every day.

## ✅ B03 · 基准10题 · 10题②

**Q:** Why did you leave your last three companies?

**A:** Just to be precise, two of them were layoffs, and one was my own decision. At KKday, the business line was shrinking. Most of the people they kept had been there longer than me. I'd joined about a year and a half earlier. My performance was in the top 30% of the Tour team, so I don't think it was about my work. Debon was similar. The business had struggled for two years, and our Android team went from three people to one. They kept the longest-serving engineer. Before I left, my work had shipped and I handed everything over cleanly. Kezhi was different. After the team was disbanded, there was no real product work left, and the company's future was unclear. Many people left, and I decided to leave too.

## ✅ B04 · 基准10题 · 10题③

**Q:** What people or working styles do you dislike working with, especially in your most recent role?

**A:** I don't like it when people change something others depend on, and don't tell them. Once, we were building a booking page. The backend changed how stock status was returned, but didn't tell the Android side. So some packages that were in stock couldn't be selected. I compared the real response with what we had agreed, and found the change. Then I worked with the backend engineer on the fix. We retested every package that was affected. After that, we agreed on one rule. For any shared API change, explain what changed first, and send sample data. That way, the app side can check the impact. Later, when they changed these APIs, they sent sample data first. So we found what both sides needed to change before testing together. I understand things get missed under deadlines. When I do backend work, I remind myself of this too. When your change affects others, telling them early is a habit I value.

## ✅ B05 · 基准10题 · 10题③

**Q:** What kind of manager do you work best with?

**A:** I work best with a manager who sets a clear goal and then trusts me on the details. At Kezhi I reported to the CTO, and he told me what the first version had to do. He didn't tell me how to build it. I set up the Android base myself, and our team shipped the first version in four weeks. I also like a manager who gives direct feedback. My KKday lead once told me to keep the scope of my changes under control. It was fair, and I changed how I plan releases after that. What's hard for me is a manager who changes priorities but doesn't say what matters most. I'd rather ask early: what must work first? Then I can move my time there and tell the team what changed.

## ✅ B06 · 基准10题 · 10题④

**Q:** What are your strengths and weaknesses?

**A:** My main strength is following a problem across the app and the backend. At KKday, sometimes the AI reply didn't fit what the app could show. I could fix both the reply format and the fallback. My weak spot is model training. I'm better at putting AI into products. I can own the app side and the test cases. For model quality, I'd work with the ML engineer.

## ✅ B07 · 基准10题 · 10题⑤ Head

**Q:** What do you understand about the product we're building, and what would you still need to learn?

**A:** I understand ActAI as a voice and text communication app with an agent at the center. People shouldn't need to write long prompts. They say what they want, and the assistant helps get it done. For example, friends agree on a Friday meeting in a chat, and the agent sets it up for them. The goal is to make coordination between people easier. I also know the team is small and based in Beijing, and I'd work closely with the founder and CTO. What I'd still need to learn is the product details. I don't know yet which tasks you want to handle first, or how you decide when the assistant should act alone and when it should ask the user first. I'd also need to learn your backend and AI setup, and how the Android app talks to it. And I'd need to learn how you measure success, like time saved or how often people correct the assistant.

## ✅ B08 · 基准10题 · 10题⑥ Hustle

**Q:** How do you feel about work-life balance? What if priorities change halfway through a sprint?

**A:** I care about balance, but I don't treat it as a reason to slow down. I plan my week around the moments when other people need me. If priorities change halfway through a sprint, I ask what must work for users on launch day. Then I move my time there and tell the team what changed and when they can test it. A short push is fine. But if every week feels like launch week, I'd raise it and we'd fix the plan together.

## ✅ B09 · 基准10题 · 10题⑦ 7H

**Q:** We look for 7H: head, hands, hustle, humility, heart, hunger and habits. Which one describes you best? Give an example.

**A:** Hustle describes me best. At Kezhi, I was the only Android engineer, and the product was brand new. I built the base of the app from zero, and our team shipped the first version in four weeks. I also handled testing and releases myself. When something was unclear, I didn't wait for a full plan. I made a call, shipped it, and fixed it fast. That's how I like to work in a startup.

## ⚠️ B10 · 基准10题 · 10题⑧

**Q:** If you work remotely, how do you keep yourself accountable daily and weekly? What is on your personal scoreboard?

**A:** At KKday, I worked remotely some of the time. I plan each week around handoff points. For a booking page, I first agree when we test with the backend, and when QA gets it. Then I plan my own coding time around that. Each day follows those points. If we test with the backend in the afternoon, I get the flow working in the morning and list the API issues. So we can fix them together right away. My updates are specific. For example: "The page is done. The main flow works. Empty stock is left. I'll check it with the backend tomorrow." That way, QA knows what they can test first. Across time zones, I'd write the questions, sample data, and what needs confirming clearly in advance. Then we'd use the overlap hours to discuss them together. When something urgent comes in, I explain the trade-off. For example: "Today I'll fix the checkout bug. The page redesign moves one day. I'll send the new QA date." Then I confirm it with my lead. Each week, I check three things. Did I deliver what I promised? How much was missed or redone? Did anyone wait on me?

- 人工：“在 KKday 有时远程办公”来自之前已批准的段落，未在今天核实

## ✅ B11 · 基准10题 · 10题⑨

**Q:** Would you deliver bad news to your team early or later?

**A:** Early. The sooner the team knows, the more time they have to adjust. But I bring the problem and a suggestion together. At Debon Securities, I was rebuilding part of our trading app. It was planned to ship with that week's release. During testing, I found some old pages had a broken back button with the new navigation. I hadn't checked every page yet. But it could already affect the release. So I told the project manager that same day. I said: "Some pages are confirmed broken. I'm still checking the rest. If this ships this week, we may not have time to test it fully. I suggest we keep the old pages, and move this change to the next release. Everything else can ship as planned. I'll update you tomorrow afternoon on the impact and the fix." We changed the release scope. Everything else shipped on time. My change shipped later, after it was fixed and tested. To me, telling early gives the team time to choose. And I don't just report the problem. I keep pushing the fix, and keep everyone updated.

## ✅ B12 · 基准10题 · 10题⑩

**Q:** What are your salary expectations?

**A:** Could you share the base pay range for this role? And how does equity work here? I see this as a senior Android role. It also owns how AI works for users. Once I know the base, bonus and equity, I can tell you if it works for me.

## ✅ B13 · 基准10题 · 10题⑩

**Q:** What is your current or previous compensation?

**A:** At KKday, I earned RMB 26,000 a month, for 13 months. I also got a yearly bonus of about RMB 50,000. So my fixed pay was RMB 338,000 a year. With the bonus, it was about RMB 388,000. At Kezhi, I earned RMB 31,000 a month, for 12 months. That's RMB 372,000 a year.

## ✅ B14 · 基准10题 · 10题⑩

**Q:** What's your minimum?

**A:** I'd rather not give a single number first. Could you share the base range for this role, plus the bonus and equity structure? Then I can tell you clearly whether it works for me.

## ✅ B15 · 基准10题 · 10题⑩

**Q:** When can you start?

**A:** I can start quite soon. I left KKday in August, so I have no notice period to serve. I'd just need a few days to sort things out, and I can confirm the exact date against your target start date.

## ✅ B16 · 基准10题 · 10题⑩

**Q:** Can you work with an international team in English?

**A:** Yes, I can. I worked in an international team at KKday, and I can explain my work clearly in English. I'm comfortable in meetings and in writing. If the team speaks fast, I may ask someone to repeat a point, but I won't miss the meaning.

## ⚠️ F01 · 资料补充题 · 手册Q1/框架A1

**Q:** Tell me about yourself.

**A:** Hi, I'm Jianhui Xu. I have ten years of experience in software. Most of it is Android. In the last three years, I also built AI agents and RAG systems. At Ping An, I built app features and kept the apps stable. At Debon Securities, I made the app start faster. At Kezhi, I built the base of a new Android app. I also built a RAG system there. That's where my AI work started. Most recently, I was at KKday. I was the technical lead of a five-person AI team. I designed the agent and built the core backend. Our AI trip planner made about 300,000 plans a day. I also wrote core Android features myself. Choosing a product option got much faster. It went from about one second to 300 milliseconds. I also like to learn by building. I taught myself Flutter and built FlutterDouBan. It has over nine thousand stars on GitHub. That's why ActAI excites me. You put voice, text and AI into everyday communication. I want to put my Android and AI skills together and help build it.

- SKU 例子串到了这题
- 误报：已批准的自我介绍原文包含 SKU，规则允许

## ✅ F02 · 资料补充题 · 框架A2

**Q:** Could you walk me through your career timeline and current employment status?

**A:** I'll go through my timeline in order. I started at Ping An Securities in September 2015 as an Android engineer. I built stock charts and watchlists there. In May 2018, I moved to Ping An Haoxue, still inside Ping An. I built a classroom SDK that two apps shared. I stayed in Ping An for almost six years, until August 2021. The company moved my team to Shenzhen then. My son was born in 2019, so I stayed in Shanghai. From September 2021 to July 2023, I was a senior Android engineer at Debon Securities. I moved the trading app to a modular architecture and made it start faster. From September 2023 to February 2025, I was a senior architect at Kezhi. I built the base of a new Android app and also built a RAG question-answering system. From February 2025 to August 2026, I was at KKday as a full-stack AI engineer. I led a five-person AI team and also wrote core Android features. Right now I'm between jobs. KKday cut its mainland China team in August 2026, and I was one of them. Since October, I've been building Cabinet, my own AI assistant app, and looking for my next role.

## ✅ F03 · 资料补充题 · 框架A3

**Q:** What is the most important career decision you have made, and why?

**A:** The most important career decision I made was staying in Shanghai in 2021. The company moved my team to Shenzhen, but my son was born in 2019 and was still very young. I chose to stay with him. That meant leaving Ping An after almost six years. It wasn't an easy call, because I liked the work and the people. But I wanted to be there while he was small. Looking back, I'd make the same choice. It also taught me what I want from a job: work I care about, and time with my family.

## ✅ F04 · 资料补充题 · 框架A4 · 重跑

**Q:** How would you describe your contribution to someone without an engineering background?

**A:** I'd say I make the AI part of the app actually work for people. At KKday, I led a small team that built an AI trip planner. A traveller typed where they wanted to go, their budget and how many days. Then they got a plan they could book. I made sure the first day showed up quickly, so nobody waited for the whole plan. I also made the app screens myself. So my job was to turn AI answers into something people can use and trust.

## ✅ F05 · 资料补充题 · 反馈第六份/杂乱4.14

**Q:** What motivates you?

**A:** What drives me most is when a problem I fix becomes something users can feel. At KKday, when users picked a date, package or ticket type, each tap took about one second to update the price and stock. If you switched a few options, the waiting was obvious. I found the cause and changed how the data was prepared. Response time dropped to about 300 milliseconds. The best moment was going through the booking flow myself afterwards. Switching options felt smooth. I could feel the difference. I enjoy that whole path: finding the problem, the cause, and fixing it myself. That kind of feedback keeps me going. So I care a lot about waiting time in AI apps too. This role is about lower latency and a better real experience on Android. That's exactly the kind of work that drives me.

## ✅ F06 · 资料补充题 · 手册Q4/杂乱4.16

**Q:** Why an AI assistant rather than a traditional Android role?

**A:** I want to work where AI is the product, not an extra feature. At KKday, I worked on both sides of an AI feature: how the planner built an answer, and how a traveller actually used it. That mix is what I enjoy most. A traditional Android role would mostly be screens and maintenance. Here, the hard problems are on the phone: showing the first result fast, handling a reply that fails, and letting the user correct the assistant. That's exactly the work I want to own.

## ✅ F07 · 资料补充题 · 框架B3

**Q:** Why an Android engineering role when you also have agent and RAG experience?

**A:** Android is where my AI experience becomes real for users. I've done both sides, but the phone is where the assistant either feels fast and reliable or doesn't. That's the part I want to own.

## ✅ F08 · 资料补充题 · 手册Q5/杂乱4.8

**Q:** What attracts you to an early-stage product?

**A:** I like the speed and the ownership. In a small team, I can decide, build and see the result in the same week. At Kezhi, I was the only Android engineer and reported to the CTO. I built the base of the app, and our team shipped the first version in four weeks. That fast loop is what I want again. I also like that early products change direction. I stay calm, ask what must work for users, and adjust.

## ✅ F09 · 资料补充题 · 手册Q6/杂乱4.13

**Q:** Why should we hire you instead of someone with more recent AI experience?

**A:** I've been building AI into real products for three years, and I've done it on Android. At KKday, I led a five-person AI team and designed the trip planner agent. It made about 300,000 plans a day. I also wrote the Android side myself, so I know how an AI answer reaches the screen. In my own time, I built Cabinet, an AI assistant app with a main agent and smaller agents. So I bring both the AI work and the Android depth.

## ✅ F10 · 资料补充题 · 手册Q7/框架K4 · 重跑

**Q:** Where do you see yourself in three to five years?

**A:** In three to five years, I want to own a big part of an AI mobile product. I want to own it from the first design to daily use. Later, I want to help other engineers make those choices too. The title matters less to me. Earning that trust matters more.

## ✅ F11 · 资料补充题 · 框架B2

**Q:** What are you looking for in your next role, and what would be a deal-breaker?

**A:** I'm looking for three things. First, AI on mobile is the core product, not a side feature. Second, I own the Android experience from start to finish. Third, a small team where I work closely with backend and AI engineers. A deal-breaker for me is a role that's mostly maintenance, with no say in how the product feels to users. I want to help decide how the app behaves when an AI answer is slow, incomplete or wrong. In three to five years, I want to own a big part of an AI mobile product, from the first design to daily use. Later, I want to help other engineers make those choices too. The title matters less to me than earning that trust.

## ✅ F12 · 资料补充题 · 框架B4

**Q:** What would make you stay with your next team for several years?

**A:** I stay when I have a real problem to own and I can see it getting better for users. At KKday, I owned the AI trip planner and the Android side. Watching the plans get faster and smoother kept me there. I also stay when I keep learning and the team is honest with each other. And I stay when the work fits my life, so I can do my best for years, not just months.

## ✅ F13 · 资料补充题 · 手册Q20/杂乱4.19 · 重跑

**Q:** Would you leave quickly if another company offered you more money?

**A:** No, I wouldn't leave quickly just for more money. I look at three things: a real problem I can own, whether I keep learning, and whether I can see the product get better for users. Money matters, but it isn't the only thing. I stayed almost six years at Ping An. At KKday, my monthly pay was lower than at Kezhi, but I joined because I liked the company and it was close to home. So if ActAI gives me meaningful work and I'm growing, I'll stay and build with the team.

## ✅ F14 · 资料补充题 · 手册Q19/杂乱4.18

**Q:** What would make you reject an offer?

**A:** I'd reject an offer if the role is mostly maintenance, with no say in how the product feels to users. I want to help decide how the app behaves when an AI answer is slow, incomplete or wrong. I'd also say no if AI on mobile is only a side feature, or if I'd be working alone with no close contact with backend and AI engineers. And I'd think twice if the team wasn't honest with each other, because I stay where people say what they really think.

## ✅ F15 · 资料补充题 · 框架C2

**Q:** Who do you think would use this product, and what problem would it solve for them?

**A:** I think the first users would be busy people who already plan things in chat. For example, two friends agree on a Friday dinner, then someone still has to set the calendar, send invites and check the details. ActAI would take that coordination work and do it for them. So the problem it solves is the copying and manual steps between saying something and getting it done.

## ✅ F16 · 资料补充题 · 框架C3

**Q:** How would you explain the idea of 'Cursor for everyone' in practical user terms?

**A:** "Cursor for everyone" means an AI helper that does the work for you, not just answers questions. With Cursor, a developer says what they want, and the tool writes and fixes the code. ActAI wants the same idea for normal life. You say in a chat that you want dinner on Friday, and the assistant sets the calendar, sends the invites and checks the details. So the user doesn't need to write prompts or copy things between apps. They just say what they want, and it gets done.

## ✅ F17 · 资料补充题 · 框架C4

**Q:** What would you want to learn about our product before deciding to join?

**A:** Before I decide, I'd want to know three things. First, what is the one user task ActAI most needs to get right in the next six to twelve months? Second, how do you judge that it's working, like whether people come back the next week? Third, what's the hardest part on Android right now: voice speed, handling partial results, or making actions reliable? I'd also ask how Android, backend and ML work together when something fails.

## ✅ F18 · 资料补充题 · 手册§4

**Q:** Your recent roles were shorter. How long have you stayed with one organization?

**A:** I spent nearly six years at Ping An, from September 2015 to August 2021. I started at Ping An Securities, building stock charts and watchlists. In May 2018, I moved to Ping An Haoxue, where I built a classroom SDK for two apps. In August 2021, the company and my team moved to Shenzhen. My son was born in 2019 and was still very young, so I stayed in Shanghai to be with him. Two of my last three jobs ended in layoffs. At KKday and Debon, the business was shrinking, and the company mostly kept people who had been there longer. At Kezhi, the team was disbanded and there was no real work left, so I left. So this time I'm choosing carefully. I want mobile AI to be the main product, not a side project, and I want to stay somewhere I can own a real problem for years.

## ✅ F19 · 资料补充题 · 手册§4

**Q:** How large was your KKday team, and how was your performance rated?

**A:** At KKday, our Tour team had 12 people. I was the technical lead on the AI trip planning project, which had 5 people. I reported to the Tour team lead. My performance rating was in the top 30% of the Tour team.

## ✅ F20 · 资料补充题 · 手册§4

**Q:** Why did you move from securities to education, from Debon to Kezhi?

**A:** Kezhi gave me a chance to build a product from the start. I designed the base of the Android app, and the team built the first features in four weeks. That was a new kind of challenge after securities work.

## ✅ F21 · 资料补充题 · 框架E2

**Q:** How did you handle the transition after your role was affected by the layoff?

**A:** After KKday cut my role in August 2026, I took September off. I travelled a bit and spent time with my grandmother back home. She raised me, so that time mattered to me. Then I started looking again after the October holiday. So far I've talked to four companies, in finance, securities and e-commerce, and a few are at the offer stage. I'm choosing carefully this time. I want AI on mobile to be the core product, not a side feature. I also kept building. I started planning Cabinet in May, and in October I started building it for real. It's my own AI assistant app, and I built the app, the backend and the website myself. That keeps me learning while I look for the right team.

## ✅ F22 · 资料补充题 · 框架E3 · 重跑

**Q:** What did those transitions teach you about choosing your next team?

**A:** Two things. First, I check why the company is hiring and whether the team is stable. At Kezhi, the team was disbanded and there was no real work left. Second, I check whether the work is real. At KKday, I led the AI trip planner and wrote core Android features myself. So now I look for a team with a clear problem and people who stay.

## ✅ F23 · 资料补充题 · 框架E4

**Q:** Is there anything in your timeline or references that you'd like to clarify?

**A:** Nothing to clarify on my side. My timeline is open, and I can move quickly if things go well here. I don't have a non-compete. My team lead at KKday can speak to my work there, and I'm happy to share his contact details when you need them.

## ✅ F24 · 资料补充题 · 框架D2

**Q:** How has your agent or RAG work changed the way you build mobile experiences?

**A:** My agent and RAG work changed three things in how I build mobile experiences. First, I design for partial answers. At KKday, the AI trip planner streams the plan day by day. The first day's card shows up while the rest is still being made. So the user never stares at a blank screen. On Android, I show what's ready and keep a clear loading state for the rest. Second, I design for things going wrong. AI replies can be incomplete or badly shaped. So the app checks the response, and when it fails, it shows a safe fallback and lets the user retry or edit. At KKday, the backend checked the structure and product IDs, and retried with the specific error. Third, I design for user control. In Cabinet, the assistant only proposes changes to the calendar or reminders. Nothing happens until the user taps to apply it. That habit comes straight from RAG: when the material isn't enough, say so instead of guessing. So the biggest change is this. I stopped treating AI as a text box. I treat it as a slow, sometimes wrong partner, and the app has to keep the user in control the whole time.

## ✅ F25 · 资料补充题 · 框架D3

**Q:** What would you need to learn to become effective in this role?

**A:** Two things. First, I'd get real hands-on with on-device ML, like TensorFlow Lite and ML Kit. I know the app side well, but I haven't shipped a model on the phone myself. Second, I'd learn your codebase and your AI APIs fast, so I can own a feature end to end in the first few weeks. My strength is putting AI into a product people use.

## ✅ F26 · 资料补充题 · 框架F1

**Q:** Tell me about a project you owned from an unclear problem through delivery.

**A:** At KKday, I owned the AI trip planner from an unclear problem through delivery. The problem was vague: planning a trip takes too long. Users had to check budgets, search products and build the plan by hand. I was the technical lead of a five-person team. I designed the agent and built the core backend. We let users type something like "Tokyo, three days, 5,000 yuan" and get a plan they could book. The first day's card shows up while the rest is still being made. The system now handles about 300,000 planning tasks a day.

## ✅ F27 · 资料补充题 · 框架F2

**Q:** Which achievement are you most proud of, and how did you measure its impact?

**A:** The one I'm most proud of is the product page at KKday. When a traveller tapped a tour, it took about a second before the options and prices appeared. That's long enough to feel slow. I looked into it and found the app was reading the same data again and again. It also did heavy calculations at the moment the page opened. So I simplified the data and prepared the price and stock lookups in advance. I moved the heavy work into the background and cached the results. It went from about one second to about 300 milliseconds. I measured it in two ways. Offline, I marked when the screen finished drawing, using FrameMetrics and JankStats, and checked it with Perfetto. Online, I used event tracking and looked at the percentiles. I don't have conversion numbers for it. The impact I can point to is the waiting time users feel.

## ✅ F28 · 资料补充题 · 框架F3 · 重跑

**Q:** Tell me about a time you solved a problem outside your formal responsibilities.

**A:** At Kezhi, I was the only Android engineer, so testing and releases weren't anyone else's job. I took them on myself. I set up the build and release steps, tested each feature before it went out, and handled the store releases. The team shipped the first version in four weeks. Nobody asked me to own that. I just saw it needed doing, and I did it.

## ✅ F29 · 资料补充题 · 框架F4

**Q:** Tell me about a project that did not achieve the result you expected.

**A:** The project that didn't land as I hoped was the RAG question-answering system at Kezhi. We built it for many school subjects, and the first version looked fine in demos. But when we tested it with real student questions, some answers were correct in content but pulled from the wrong grade or chapter. So the answer didn't match what the student was actually learning. I dug into the search step. The problem was that we searched too widely. So I changed it to narrow down by subject, grade and chapter first, then look for the answer. I retested the questions that had failed, and some found the right chapter. I also checked that other questions didn't get worse. What I took from it is that a good demo doesn't mean it works. I should test with real questions much earlier, and check the source of the answer, not just whether it sounds right.

## ✅ F30 · 资料补充题 · 手册§5

**Q:** Tell me about a time you had to move fast.

**A:** At Kezhi, our team built the first features of an exam app in four weeks. I owned the base of the Android app. I also helped put features together. Some screens were in the app, and some were web pages. So I set up routing between modules. I also made a way to show web pages inside the app. That way, both kinds of features made the first version.

## ✅ F31 · 资料补充题 · 手册§5

**Q:** What would you do if you couldn't stop feature work to fix reliability?

**A:** I'd protect the release first, then fix reliability in small pieces. I'd agree with my lead on what must be stable for users, like sending a message. Then I'd cut or delay one lower-value feature to make room. I'd also fix the worst reliability issue in small steps alongside feature work, not as a big separate project. If the problem keeps growing, I'd show the data, like crash or failure rates, and ask the team to choose the trade-off openly.

## ✅ F32 · 资料补充题 · 框架G2

**Q:** How do you handle a short period of intense work before a critical launch?

**A:** I'm fine with a short intense push before a launch. I'd agree with my lead on what must work on day one, and what can wait. Then I'd focus on that, and tell the team what changed and when they can test it. I'd also keep an eye on how many days it lasts. A few hard weeks are fine, but if every week feels like launch week, I'd raise it and we'd fix the plan together.

## ✅ F33 · 资料补充题 · 框架G3

**Q:** How would you respond if a founder changed direction after two weeks of your work?

**A:** I'd ask what changed and why, before I touch any code. Then I'd check what still works and what we can keep. At Kezhi, the product was new and priorities moved fast, so I learned to keep the base of the app flexible. I'd tell the team what we keep and what we drop, and give a new date. If the change is big, I'd say so honestly. I'd rather lose two weeks than build the wrong thing for two months.

## ✅ F34 · 资料补充题 · 框架G4

**Q:** Tell me about a time you chose a simpler solution to ship sooner.

**A:** At KKday, our AI trip planner had to show a plan while it was still being generated. The full design was complex. So I chose a simpler first version. I sent the plan day by day, so the first day's cards appeared right away. Users didn't wait for the whole plan. That shipped sooner, and we could improve it later with real feedback.

## ✅ F35 · 资料补充题 · 框架H2

**Q:** Tell me about a mistake you made that affected other people.

**A:** At KKday, I made a mistake that slowed down QA. I finished a booking page on time. But I only planned when the code would be done. I left all the API checks to the last day. When we tested with the backend, empty stock didn't match what the app expected. Both sides had to change and retest, so QA got it late. In my weekly review, I saw the cause. Before coding, I now ask the backend for sample data: normal cases, in stock, and out of stock. I list problems early, and I plan separate time for testing and fixes. After that, we found most data issues before joint testing. There was less last-minute rework, and QA dates were easier to predict.

## ✅ F36 · 资料补充题 · 框架H3 · 重跑

**Q:** What would you do if a stakeholder asked you to present an uncertain result as a confirmed improvement?

**A:** I'd say no, I can't present it as confirmed. I'd show what we actually measured and how sure we are. Then I'd say what we still need to check before we call it an improvement. If they still want a strong claim, I'd ask them to label it as early data, not a result.

## ✅ F37 · 资料补充题 · 框架H4

**Q:** Tell me about a time you changed your mind after receiving new evidence.

**A:** At Kezhi, I changed how I built the RAG search after real test questions showed a problem. At first, the AI answered from memory. Some answers looked fine, but they used content from the wrong grade. So I changed the search. First I narrowed it down by subject, grade and chapter. Then I looked for the answer. I retested the questions that had failed, and some now found the right chapter. I also checked that other questions didn't get worse. That evidence changed my mind, so I kept the new way.

## ✅ F38 · 资料补充题 · 框架I1

**Q:** Tell me about a disagreement with a manager, product partner or engineer.

**A:** At Debon Securities, I disagreed with our project manager about a release. I was rebuilding part of the trading app, and testing showed the back button broke on some old pages. I wanted to delay that change. He wanted to ship it with the week's release. I showed him what was confirmed broken and what I was still checking. I said we could keep the old pages and move my change to the next release. Everything else would ship on time. He agreed. My change shipped later, after it was fixed and tested.

## ✅ F39 · 资料补充题 · 手册§5

**Q:** How did you handle coordination between the backend and the app at KKday?

**A:** At KKday, we agreed on the API format before coding. I asked the backend for sample data first: normal cases, in stock, and out of stock. Then I checked the real responses against what we agreed. When the AI trip planner needed a new field, we defined the response format together. I also set one rule. For any shared API change, explain what changed first, and send sample data. That way, the app side can check the impact before testing. If something still broke, I compared the real response with the agreed format, found the change, and fixed it with the backend engineer.

## ⚠️ F40 · 资料补充题 · 框架I4

**Q:** Tell me about a time you helped a teammate who was struggling.

**A:** At Ping An Haoxue, one of our Android engineers was behind on the classroom SDK work. He was quiet about it, and I only found out when his part was late. So I sat with him and asked what was blocking him. The audio and video parts were new to him, and he was afraid to ask. I broke his task into smaller pieces and paired with him on the first one. I also asked him to send me a short update every day. After that he finished his part, and the two apps shared the same classroom code.

- 人工：帮助同事的故事是 Assistant 补出的情节（行为题允许），本人面试前确认能接住

## ✅ F41 · 资料补充题 · 反馈第七份

**Q:** What kind of environment would make it hard for you to perform?

**A:** I'm fine with fast changes and a process that's still being built. What makes it hard is when poor communication keeps causing rework, and nothing changes. For example, developers and QA work from different versions of the same feature. They only find out near the end. That happens sometimes, and it's normal. When it does, I put the latest decisions and changes in one shared place. I ask the people involved to confirm it. A simple fix first. I don't expect a team where everything is already set up. I'm happy to help build how we work. What matters to me is that when we find a problem, we adjust together, so it happens less next time.

## ✅ F42 · 资料补充题 · 框架J2

**Q:** Tell me about a time asynchronous communication prevented or caused a problem.

**A:** At KKday, async communication caused a problem for me. The backend changed how stock status was returned, but didn't tell the Android side. So some packages that were in stock couldn't be selected. I compared the real response with what we had agreed, and found the change. Then I worked with the backend engineer on the fix. After that, we agreed on one rule. For any shared API change, explain what changed first, and send sample data. Later, when they changed these APIs, they sent sample data first. So we found what both sides needed to change before testing together.

## ✅ F43 · 资料补充题 · 框架J3

**Q:** How would you work with a team spread across several time zones?

**A:** I'd plan my week around the overlap hours. I'd write questions, sample data and what needs confirming clearly in advance, so people can read them when they start. Then we'd use the shared hours to decide together. Each day I'd send a short, specific update, like what's done and what's blocked. If something urgent comes in, I'd explain the trade-off and give a new date. I haven't worked across many time zones before, but at KKday I worked remotely some of the time, and these habits are the same.

## ✅ F44 · 资料补充题 · 框架J4

**Q:** How do you handle a discussion in English when you don't fully understand a requirement or you disagree with it?

**A:** I'd say it plainly. I'd say I didn't fully understand, and ask them to explain that part again. Then I'd repeat it back in my own words, so we both know I got it right. If I disagree, I'd say what I see and why, and give a concrete example. I'd keep it about the work, not the person. At KKday, I worked with people in other countries, and English was our shared language. Asking early is much better than guessing and building the wrong thing.

## ✅ F45 · 资料补充题 · 反馈第五份

**Q:** Do you do a weekly review? Give me an example of how it changed your approach.

**A:** Yes, I do a weekly review. Each week, I look at what didn't go as planned, and what I should change. Once, I finished a booking page on time. But on the day we tested with the backend, we found a problem. When stock was empty, the API data didn't match what the app expected. Both sides had to change and retest. So QA got it late. In the review, I saw my mistake. I only planned when the code would be done. I left all the API issues to the last day. So I changed how I work. Before coding, I ask the backend for sample data. Normal cases, in stock, and out of stock. I list problems early. And I plan separate time for testing and fixes. After that, we found most data issues before testing together. There was less last-minute rework, and QA dates were easier to predict. What changed was how I judge progress. A finished page is just one step. It's done when it works with the backend and QA can test it.

## ✅ F46 · 资料补充题 · 框架K1

**Q:** What is the most useful critical feedback you have received?

**A:** The most useful critical feedback I got was from my manager at KKday. He told me to keep the scope of my changes under control. There was a feature I could have built on the existing architecture. It needed quite a lot of code, so I wanted to improve that part of the architecture at the same time. But that made the release take longer. That taught me that even a good long-term improvement needs the right timing. Now I describe the feature and the architecture work separately. Then the team and I agree whether it's worth doing both in this release.

## ✅ F47 · 资料补充题 · 框架K2/反馈第八份

**Q:** Tell me about something difficult you learned recently and applied in practice.

**A:** The most useful thing I learned recently was how to make an AI answer look up real material before it replies. At Kezhi, we built a Q&A tool for many school subjects. I started with a few textbooks and got the basic flow working. Then I tested it with real questions. Some answers looked fine, but they used content from the wrong grade. So I changed how it searched. First I narrow down by subject, grade and chapter. Then I look for the answer. I retested the questions that had failed, and some now found the right chapter. I also checked that other questions didn't get worse. I used the same idea later at KKday, when I built the RAG system there.

## ✅ F48 · 资料补充题 · 框架L1 · 重跑

**Q:** Tell me about a time user feedback changed your engineering priorities.

**A:** Honestly, I didn't have formal user feedback data on my recent work. On the KKday product page, I checked the experience myself by going through the booking flow. Here, I'd watch where users drop off and where they correct the assistant, and fix the step that causes the most corrections first.

## ✅ F49 · 资料补充题 · 框架L2

**Q:** How do you decide when AI is useful and when a simpler approach is better?

**A:** I use a simple test. AI is worth it when the input is open and messy, like a free sentence about a trip. A simple approach is better when the rules are clear and the answer must be exact. At KKday, the AI trip planner was a good fit. A traveler typed "Tokyo, three days, 5,000 yuan." The AI pulled out the destination, budget and days, then built a plan. A fixed form couldn't do that well. But price and stock were not AI work. I calculated those with plain code, in advance. The AI should never guess a price. So I keep AI for understanding and planning, and normal code for numbers and rules.

## ✅ F50 · 资料补充题 · 框架L3

**Q:** How do you use AI coding tools while staying accountable for what you ship?

**A:** I write the core architecture myself, and I review and test everything the tools generate before it goes in. For example, in CabinetAI I built the base framework by hand and used AI tools only for the simpler screens. I read every change, run it, and check the edge cases myself. The tool saves typing time, but I stay responsible for what ships.

## ✅ F51 · 资料补充题 · 框架L4

**Q:** Imagine an AI communication feature gives a misleading answer or captures audio unexpectedly. What would you do?

**A:** I'd treat those as two different problems. A misleading answer is a product and trust problem. Unexpected audio capture is a privacy and permission problem, and that one is more serious. For a misleading answer, I'd first make the app show where the answer came from. In CabinetAI, RAG answers cite the original text, and when the material is thin, the assistant says so instead of guessing. I'd also let the user correct it in one tap, and keep that correction. Then I'd add the bad case to a test set, so we catch it next time. At KKday, I built a review pipeline with prompt versions and regression tests, so we could replay old cases and see if a fix broke something else. For unexpected audio capture, I'd stop and check it straight away. The app should only record after a clear action from the user, and show that it's recording. The microphone permission should be asked at the moment it's needed, not at sign-up. Audio should not be kept longer than needed, and the user should be able to see and delete what was kept. If we found a real bug, I'd turn the feature off with a remote switch, tell the team and the users honestly, and fix the cause before turning it back on. So my rule is simple. The assistant can be wrong, but it must never hide that it's unsure, and it must never listen without the user knowing.

## ✅ F52 · 资料补充题 · 框架M4

**Q:** Are you in other interview processes, and what is your decision timeline?

**A:** Yes, I'm in other processes. I started looking after the October holiday, about a month ago. So far I've talked to four companies, in finance, securities and e-commerce, and a few are at the offer stage. Nothing urgent yet, but I'd expect to decide in the next few weeks. I'd be happy to move quickly if things go well here. ActAI is the one I'm most interested in, because it's an AI-first product, not a traditional app with AI added on.

## ✅ F53 · 资料补充题 · 框架M条件

**Q:** How would you evaluate a counteroffer?

**A:** I'd look at the reason behind it, not just the money. If the counteroffer only adds pay but nothing changes, the problem that made me look is still there. I'd also ask myself why the company only valued me after I said I was leaving. For me, the work matters more. I want AI on mobile to be the core product, and I want to own the Android experience. A counteroffer usually can't give me that. So I'd only stay if the role itself really changed. Otherwise I'd keep my word and move.

## ✅ F54 · 资料补充题 · 框架M条件

**Q:** Do you have any conflicts of interest or outside commitments relevant to this role?

**A:** No, I don't have any conflicts of interest. I don't have a non-compete, and I'm free to start once we agree on a date. My only outside project is CabinetAI, my personal app, and I'll stop working on it if I join ActAI.

## ✅ F55 · 资料补充题 · 框架M3 · 重跑

**Q:** Is there any work authorization or sponsorship requirement we should plan for?

**A:** I've worked in China my whole career, and I don't need sponsorship to work here.

## ✅ F56 · 资料补充题 · 手册Q18/框架N2

**Q:** Do you have any concerns about the role?

**A:** I have one real concern, and it's about focus. I want to spend most of my time on Android and on how AI feels to users. If the role is mostly backend or model work, that wouldn't fit me well. I'd also like to know how Android, backend and ML share ownership when a feature fails. That's it, really. The product direction is the reason I'm here.

## ✅ F57 · 资料补充题 · 手册Q21

**Q:** Is there anything else you'd like to add?

**A:** There are two things I'd add. First, I'm honest about what I'm still learning. I haven't trained models myself, and my TensorFlow Lite and ML Kit experience is limited. My strength is putting AI into a product people use. I'd own the Android side and the test cases, and work closely with the ML engineer on model quality. Second, I want to be clear about why I'm here. I'm not looking for any Android job. I want mobile AI to be the main product, not a small feature. That's why ActAI caught my attention, and I'd be glad to go deeper on any part of my background.

## ✅ F58 · 资料补充题 · 框架N3

**Q:** What would you want us to remember about you after this conversation?

**A:** I'd like you to remember two things. First, I've done both sides of an AI product. At KKday, I led the AI trip planner and wrote the Android features myself. Second, I care about the small moments. When the assistant is slow, or not sure, or the user changes their mind, the app should still feel calm and clear. That's the work I want to own at ActAI.

## ✅ F59 · 资料补充题 · 框架N4

**Q:** Is there anything we haven't covered that would help us evaluate your fit fairly?

**A:** Two things would help. First, I'd like to talk through one real design problem with you, like how the Android app should show an assistant's action while it's still running. Second, I'd like to hear how Android, backend and ML split the work when something fails. That would show you how I think, not just what I've done.

## ✅ F60 · 资料补充题 · 框架N1

**Q:** What questions do you have for me?

**A:** Thanks for asking. I have a few questions. First, six months from now, what would make you feel you hired the right Android engineer? Second, what's the biggest mobile challenge right now: voice speed, handling partial results, or making actions reliable? Third, how many Android engineers are there today? And when a feature fails, how do Android, backend and ML work together? Last, what does a good engineer look like on this team? Could you give an example of how the team handled a sudden change in priorities?

## ⚠️ N01 · 预测新增题 · 今日定稿

**Q:** Two of your roles ended in layoffs. Why do you think you were the one affected?

**A:** The company didn't give a specific reason, and it paid me severance. I can only share my view. At KKday, the company was getting smaller, so it needed fewer people. It kept people for the current app. I spent half my time on Android and half on AI. Two colleagues worked on the app longer, and they knew its history. So keeping them made sense. It wasn't about performance. I was in the top 30% of my team. Debon was similar. The business was weak for two years, and our Android team went from three people to one. They kept the engineer who was there the longest. Before I left, my work had shipped and I handed everything over cleanly.

- 和定稿差异较大（相似度 0.1）
- 误报：比对的定稿是“三家离职原因”，与本题不同；内容正确

## ✅ N02 · 预测新增题 · 今日定稿

**Q:** Why didn't you stay and help Kezhi recover?

**A:** By then, most of the team had already left: the backend engineers, the web engineers and the core algorithm people. There was no real product work left, and the future was unclear, so I decided to leave. The business depended on selling to public schools, and getting paid was slow and difficult. An Android engineer alone couldn't rebuild that. If the core team had stayed, I would have stayed too.

## ✅ N03 · 预测新增题 · 今日定稿

**Q:** Did you get severance from KKday? How much?

**A:** Yes, I received the standard package. It was four months' pay.

## ✅ N04 · 预测新增题 · 今日定稿

**Q:** After those layoffs, why would you join an early-stage startup that may pivot or fail?

**A:** That's a fair question. Kezhi taught me to check two things before joining a startup: how the business is funded, and whether the core team is committed. At Kezhi, revenue depended on public schools, and payments were slow. When the core team left, there was nothing left to build. From what I understand, ActAI is different on both points. It's funded by a group that has been profitable since it started, and I'd work directly with the founder and CTO. The product also fits what I've been doing. At KKday, I worked on how an AI plan shows up on the phone while it's still being generated. In my own project, CabinetAI, people can use voice or text to record expenses, set reminders and manage tasks, and it asks before it takes important actions. ActAI is the same idea in everyday communication. If the product changes direction, that's normal for a startup. I'd watch whether the core people are still committed. If they are, I'd stay and help with the new direction. And honestly, the remote and hybrid setup also helps me spend more time with my son.

## ✅ N05 · 预测新增题 · 今日定稿

**Q:** What have you been doing since August?

**A:** After KKday, I took September off. I travelled a bit and spent time with my grandmother back home. She raised me, so that time mattered to me. I started looking again after the October holiday. That was about a month ago. So far I've talked to four companies, in finance, securities and e-commerce, and a few are at the offer stage. But ActAI is the one I'm most interested in, because it's an AI-first product, not a traditional app with AI added on.

## ✅ N06 · 预测新增题 · 今日定稿

**Q:** What's your decision timeline? Is there a deadline we should know about?

**A:** Nothing urgent yet, but I'd expect to decide in the next few weeks. I'd be happy to move quickly if things go well here.

## ✅ N07 · 预测新增题 · 今日定稿

**Q:** Your title went from Senior Architect to Full-Stack Engineer. Is that a step down?

**A:** Titles mean different things at different companies. At Kezhi, the app team was five people, and I reported to the CTO, so "architect" covered a lot. KKday is a much bigger company with its own title system. The work itself didn't get smaller. I led the technical work on the AI itinerary project, and the system handled about 300,000 planning tasks a day. I chose KKday because it was a strong company, I was referred by someone there, and it was close to home. The title wasn't what I was looking at.

## ✅ N08 · 预测新增题 · 今日定稿

**Q:** Are you more of an architect or a hands-on engineer? How much did you actually code?

**A:** Both. At KKday I was leading the project, so about 30% of my time was coding. The rest was architecture, product analysis and data research. Before that, at Kezhi and Debon, I was much more hands-on. In a small team like yours, I'm happy to spend most of my day coding again. The product analysis part still helps, because I can see what users need before I build it.

## ✅ N09 · 预测新增题 · 今日定稿

**Q:** At Kezhi, did you switch from Android to RAG? Why come back to Android now?

**A:** It wasn't really a switch. At Kezhi, I did both at the same time. I kept building the Android app, and I also worked on the RAG question-answering system. Android has been the constant through my whole career. AI is something I learned by using it in real products, first at Kezhi, then at KKday. So for me, this role isn't coming back to Android. It's where both parts of my experience meet.

## ✅ N10 · 预测新增题 · 今日定稿 · 重跑

**Q:** You were top 30%. What would it have taken to be top 10%?

**A:** At KKday, our manager gave ratings based on our past work and feedback from colleagues. I'd been there about a year and a half. It takes time for a team to get used to a new person, and for that person to learn how the team works. My work got better steadily over that time. To reach the top 10%, I think I needed a longer track record there, and more chances for my work to be seen beyond my own project.

## ✅ N11 · 预测新增题 · 今日定稿

**Q:** Is CabinetAI a business? Will you keep working on it if you join?

**A:** It's a personal project, not a business. It's in internal testing on TestFlight now, with a small group of users. If I join ActAI, I'll stop working on it. I want my full focus here.

## ✅ N12 · 预测新增题 · 今日定稿

**Q:** Why is CabinetAI on iOS? Is there an Android version?

**A:** There's an Android version too. I wrote it in my spare time. I built the base framework myself and used AI coding tools for the simpler screens, which saved a lot of time. It isn't on Google Play yet, because I'm still finishing the integration testing and the Play setup. The iOS build just reached testing first.

## ✅ N13 · 预测新增题 · 今日定稿

**Q:** When did you last ship production Kotlin? Have you used Jetpack Compose?

**A:** Until August this year, at KKday. Everything was in Kotlin. I introduced Jetpack Compose there, and all our Android screens were rebuilt with it. More recently, I've built the Android version of CabinetAI, also with Kotlin and Compose.

## ✅ N14 · 预测新增题 · 今日定稿

**Q:** Which recent Android project best shows what you could contribute here?

**A:** One I'm proud of is the product page at KKday. When a traveller tapped a tour, it took about a second before the options and prices appeared. That's long enough to feel slow. I looked into it and found the app was reading the same data again and again, and doing heavy calculations at the moment the page opened. So I simplified the data, prepared the price and stock lookups in advance, moved the heavy work into the background, and cached the results. It went from about one second to about 300 milliseconds. For ActAI, it's the same idea: when an assistant answers, the user should see something right away.

## ✅ N15 · 预测新增题 · 今日定稿

**Q:** Do you have any experience with voice on Android?

**A:** Some. At Ping An Haoxue, I packaged our live classroom, including its audio and video, into an SDK. Both the student tablet app and the parents' phone app used it. More recently, in CabinetAI, people can speak instead of typing on both iOS and Android. I used ElevenLabs for the speech-to-text. I haven't built speech models myself. My side is the app: making voice input feel quick and natural, and handling it well when something goes wrong.

## ✅ N16 · 预测新增题 · 今日定稿

**Q:** Have you shipped apps for global users or on Google Play?

**A:** Yes. KKday is a global travel platform, and our Android app is on Google Play, used by travellers in many markets and languages. Before that, my work was mostly for users in China. CabinetAI's Android version will go on Google Play once I finish testing.

## ✅ N17 · 预测新增题 · 今日定稿

**Q:** Which AI products do you use every day, and what frustrates you about them?

**A:** I use AI tools every day, mostly for coding. I use Codex and ChatGPT for architecture and product research, and Claude for deeper coding and building base frameworks. I also use Grok. What frustrates me most is context. On long tasks they forget things, and when I switch between projects, I have to explain everything again. I think a real assistant should work from one place. You give it a goal, and it uses what it already knows to decide the next steps. You shouldn't have to tell it every step. That's a big reason ActAI caught my attention. Your job post talks about keeping context and finishing multi-step tasks with minimal prompting. That's exactly the problem I feel every day.

## ✅ N18 · 预测新增题 · 今日定稿

**Q:** So should an assistant just do everything on its own?

**A:** Mostly, yes, but not for everything. Routine steps should just happen. But before anything important, like changing someone's calendar or sending a message, it should check first. In CabinetAI, calendar changes only happen after the user approves them. The hard part is deciding where that line is.

## ✅ N19 · 预测新增题 · 今日定稿

**Q:** What do you think of Meta AI in WhatsApp or Gemini in Messages? Why would people switch to ActAI?

**A:** Their biggest advantage is that people don't have to switch apps. So for ActAI to win, it has to fix a problem people hit again and again, and the benefit has to be big enough to be worth installing another app. From what I've seen, those assistants mostly wait for you to ask. ActAI's idea is to help before you have to ask. In CabinetAI, I've been working on the same question: once someone says what they want, can we cut out the copying and manual steps? For example, if a voice message mentions a meeting time, some materials to prepare and a deadline, the assistant should turn that into a short list for me to confirm, and then carry on. I shouldn't have to listen again and type it all in. I don't expect people to leave WhatsApp on day one. More likely, they start using ActAI for one task, find it saves them steps every day, and gradually move more conversations over. So what matters to me isn't how many AI features there are. It's whether getting from saying it to getting it done feels natural, fast and reliable. That's where I want to bring my Android and AI experience together.

## ✅ N20 · 预测新增题 · 今日定稿

**Q:** How would you know if that kind of assistant is actually working?

**A:** I'd look at three things: how much time it saves before something is agreed, how often people have to correct it, and whether they come back the next week. If people keep correcting it, the extra steps might cost more time than it saves.

## ✅ N21 · 预测新增题 · 今日定稿

**Q:** An assistant that reads people's chats. How do you think about privacy and trust?

**A:** I think what people fear most is something they said privately showing up somewhere they didn't expect. Say I talk to a friend about changing jobs, and later the AI mentions it in a message it drafts to my colleague. Nothing leaked, but I'd stop trusting it. So consent can't be a single checkbox at sign-up. People should see which chats the AI can read and what it keeps, and be able to take that back at any time. A deleted memory should never come back. And anything that affects other people, like sending a message or sharing something, should show me the content and the recipient first. To me, a trustworthy assistant makes its limits clear and leaves the user in control.

## ✅ N22 · 预测新增题 · 今日定稿

**Q:** Why not a big company like ByteDance or Alibaba?

**A:** I'm not against big companies. But looking back, the work I've enjoyed most was at a startup. At Kezhi, I built the Android app and, at the same time, worked on the RAG question-answering system. I found I really like picking up a new technology to solve a real problem and building it into a product. That's also why I built CabinetAI in my own time: to learn and test new technology on a real product. It's about AI understanding what people need and helping with everyday tasks. ActAI starts from communication, which is very close to that: people express a lot of needs in chat, and the question is how AI can help get those things done. So what draws me is the startup way of working and the product fit. I want to put my Android and AI experience into a product I'll want to stay with for a long time.

## ✅ N23 · 预测新增题 · 今日定稿

**Q:** There may be no QA or release engineer here. Are you OK owning testing and releases?

**A:** Yes. Testing and releases have always been part of my job. At Kezhi, I was the only Android engineer, so besides building features, I also handled testing and releases, and the team shipped the first version in four weeks. I'm happy to own a feature all the way to launch and keep an eye on how it does afterwards.

## ✅ N24 · 预测新增题 · 今日定稿

**Q:** Have you interviewed or hired engineers before?

**A:** Yes. I did technical interviews when we were hiring at Kezhi and at KKday. I usually pick one real problem from the candidate's project and follow it: what they were responsible for, how they made the call, why they chose that approach, and how they checked the result. That tells me what they actually did and how they think when things get hard.

## ✅ N25 · 预测新增题 · 今日定稿

**Q:** What would your last manager say is your biggest weakness?

**A:** My manager at KKday once told me to keep the scope of my changes under control. There was a feature I could have built on the existing architecture. It needed quite a lot of code, so I wanted to improve that part of the architecture at the same time, to make future work easier. But that made the release take longer. That taught me that even a good long-term improvement needs the right timing. Now, when this comes up, I describe the feature and the architecture work separately, and agree with the team whether it's worth doing both in this release.

## ✅ N26 · 预测新增题 · 今日定稿

**Q:** So in a fast startup, would you skip architecture work?

**A:** No, I wouldn't skip it. I'd make it a separate decision. Sometimes doing it now saves time next month. Sometimes shipping first is the right call. The team should choose, not me alone.

## ✅ N27 · 预测新增题 · 今日定稿

**Q:** Can we speak to your references?

**A:** Yes. My team lead at KKday can speak to my work there. I'm happy to share his contact details when you need them.

## ✅ N28 · 预测新增题 · 今日定稿

**Q:** Where are you based? Would you relocate to Beijing?

**A:** I'm based in Shanghai. I'd prefer remote, but I'm happy to work from Beijing if the team needs it. My son is older now, so moving is much easier than it used to be. I'd just come back to Shanghai every month or two.

## ✅ N29 · 预测新增题 · 今日定稿

**Q:** Would you be open to occasional travel?

**A:** Yes, occasional travel is fine. I'd just like to get home to see my son every month or two.

## ⚠️ N30 · 预测新增题 · 今日定稿

**Q:** Do you have a non-compete agreement?

**A:** No, I don't have a non-compete. I'm free to join ActAI and start whenever we agree.

- 和定稿差异较大（相似度 0.54）
- 误报：多说一句可以随时入职，内容无误

## ✅ N31 · 预测新增题 · 今日定稿

**Q:** Can you explain something technical you built, in simple English?

**A:** At Kezhi, I worked on an AI tool that answers students' questions using their learning materials. Instead of asking the AI to answer from memory, we first find the right content in the textbooks. We narrow the search by subject, grade and chapter, so we don't mix up different courses. Then we give that content to the AI to help it answer. It's like an open-book exam: find the right material first, then explain the answer. That way, the answers stay accurate and match what the students are actually learning.

## ✅ N32 · 预测新增题 · 今日定稿

**Q:** How do you keep an app stable in production? Have you worked on crashes?

**A:** Yes, I've worked on crashes a lot. At Debon Securities, I tracked and fixed crashes in production. Our team cut the crash rate from about 1% to about 0.1%. We tracked it in Bugly, as crashes per app launch. Most crashes were null pointers, out-of-memory errors, WebView crashes, and problems on certain phone models. We fixed them group by group, starting with the most common. For stability in general, I do three things. First, I catch errors early and report them with enough detail to find the cause. Second, I fix the most common crashes first, because they affect the most users. Third, I test on low-end phones, not just my own device. At KKday, I also made the app feel stable when the AI was still working. The first card showed up early, and the rest came in after. If a reply failed the checks, we retried with the exact error, and had a fallback after that. So users never saw a broken screen.


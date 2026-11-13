# ActAI HR 问题 Assistant 验证

共 113 题：通过 106，提醒 4，失败 3。

## ✅ B01 · 基准10题 · 10题①

**Q:** Why are you exploring new opportunities?

**A:** I left KKday in August 2026. The Shanghai office cut many jobs, and I was one of them. So I'm using this time to choose carefully. I'm looking for three things. First, AI on mobile is the core product, not a side feature. Second, I own the Android experience from start to finish. Third, a small team where I work closely with backend and AI engineers. At KKday, I worked on both sides of an AI feature. How the planner built an answer, and how a traveler actually used it. I want more of that, on Android. ActAI fits all three.

## ✅ B02 · 基准10题 · 10题①

**Q:** Why do you want to join ActAI specifically?

**A:** There are three reasons. First, ActAI's product and my own product share a similar direction. In May, I started designing an AI agent in my spare time. It's called Cabinet. For example, I plan a three-day trip. I need to check my calendar, the weather, and my budget. Checking them one by one is slow. And I can easily miss something. Cabinet thinks of all this for me. Then it gives me a good plan. ActAI builds proactive AI products for everyone. People don't need to write complex prompts. The first product starts with communication. It puts an agent at the center. The goal is to make coordination between people easier. Here is my understanding. Friends agree on a Friday meeting in a chat. Then the agent sets it up for them. So I have real interest in this direction. I also have real experience. Second, ActAI needs someone to make AI fast and stable on Android. That's my strength. I have ten years of experience, mostly on Android. At KKday, I cut the first-screen loading time on Android. It went from three seconds to under one second. I also showed AI results step by step. Users didn't have to wait. At Ping An Haoxue, I improved a classroom app on cheap Android tablets. It ran smoothly, even on low-end devices. Third, I want to join a startup like ActAI. In a startup, nobody writes every detail for you. You need to bring structure, make decisions, and move fast. I like this way of working. I can help shape the product. And I own the results. I've done this before. At Kezhi, the product was brand new. I reported to the CTO. I was the only Android engineer. I built the whole Android app myself, from zero to launch, in four weeks. So I want to build a great product with ActAI. I want people to trust it and use it every day.

## ✅ B03 · 基准10题 · 10题②

**Q:** Why did you leave your last three companies?

**A:** Just to be precise, two of them were layoffs, and one was my own decision. At KKday, the business line was shrinking. Most of the people they kept had been there longer than me. I'd joined about a year and a half earlier. My performance was in the top 30% of the Tour team, so I don't think it was about my work. Debon was similar. The business had struggled for two years, and our Android team went from three people to one. They kept the longest-serving engineer. Before I left, my work had shipped and I handed everything over cleanly. Kezhi was different. After the team was disbanded, there was no real product work left, and the company's future was unclear. Many people left, and I decided to leave too.

## ✅ B04 · 基准10题 · 10题③

**Q:** What people or working styles do you dislike working with, especially in your most recent role?

**A:** I don't like it when people change something others depend on, and don't tell them. Once, we were building a booking page. The backend changed how stock status was returned, but didn't tell the Android side. So some packages that were in stock couldn't be selected. I compared the real response with what we had agreed, and found the change. Then I worked with the backend engineer on the fix. We retested every package that was affected. After that, we agreed on one rule. For any shared API change, explain what changed first, and send sample data. That way, the app side can check the impact. Later, when they changed these APIs, they sent sample data first. So we found what both sides needed to change before testing together. I understand things get missed under deadlines. When I do backend work, I remind myself of this too. When your change affects others, telling them early is a habit I value.

## ✅ B05 · 基准10题 · 10题③

**Q:** What kind of manager do you work best with?

**A:** I work best with a manager who tells me the outcome we need and why, then gives me room to choose how. I keep them updated on progress and risks, so there are no surprises. I decide myself when it's my area and easy to undo. I ask first when it affects other teams or users. With a manager who likes more detail, I just update more often.

## ✅ B06 · 基准10题 · 10题④

**Q:** What are your strengths and weaknesses?

**A:** I'm good at following a problem across the app and the backend. At KKday, sometimes the AI reply didn't fit what the app could show. I could fix both the reply format and the fallback. My weak spot is model training. I'm better at putting AI into products. I can own the app side and the test cases. For model quality, I'd work with the ML engineer.

## ✅ B07 · 基准10题 · 10题⑤ Head

**Q:** What do you understand about the product we're building, and what would you still need to learn?

**A:** From what I've read, ActAI is building an AI-first voice and text app, like Cursor but for daily talk, not code. You say what you want, and it helps get it done with very few prompts. The first product starts with communication, and the goal is to make coordination between people easier. For example, friends agree on a Friday meeting in a chat, and the agent sets it up for them. I think two things will decide if people stay. First, timing. The hard part isn't the model. It's knowing when to jump in and when to stay quiet. Too many interruptions, and people turn it off. Second, the phone side. When voice and text are mixed, and the network is weak, the app has to stream the answer, recover, and show clearly what worked and what failed. That's the part I'd own as an Android engineer. I've run into both in my own work. In CabinetAI, my AI assistant, I had to decide when it can act alone and when it must ask, and how to retry only the part that failed. At KKday, we showed the AI trip plan day by day while it was still being generated. What I'd still need to learn is your product and users: which task matters most, and how the team decides when the assistant acts. I'd also want to learn on-device AI. I've used AI mostly through the backend, and I have little hands-on experience with TensorFlow Lite or ML Kit. In my first month, I'd build a small working example with your models, and pair with the ML engineer on how you ship model updates.

## ✅ B08 · 基准10题 · 10题⑥ Hustle

**Q:** How do you feel about work-life balance? What if priorities change halfway through a sprint?

**A:** I'm fine with intense sprints. That's part of building something new. At KKday, I was the technical lead of the AI trip planning project. Launches were tight, and the goals changed as we learned. I shipped fast, and when something broke, I fixed it fast. At Kezhi, I was the only Android engineer. I built the whole Android app myself, from zero to launch, in four weeks. Back then, AI coding tools weren't good enough, so I wrote and worked out almost all of it myself. I also keep good habits: a clear plan every morning and a short update every evening. That helps me keep a high pace for a long time, not just for one week. For a sprint that changes halfway, I'd ask what must work for users on launch day. Say sending messages isn't stable. Then I'd move a nice extra screen out of the sprint. I'd spend my time on sending. I'd tell the team what changed and when they can test it. A short push is fine. But if every week feels like launch week, we should talk about it.

## ✅ B09 · 基准10题 · 10题⑦ 7H

**Q:** We look for 7H: head, hands, hustle, humility, heart, hunger and habits. Which one describes you best? Give an example.

**A:** Hands describes me best. I build things myself. At KKday I wrote core Android features and built the backend for the AI trip planner. In my spare time I built CabinetAI alone: the app, the backend and the website. The one I'm still working on is hustle. I like to plan before I move. But I've learned to ship first when the team needs it.

## ✅ B10 · 基准10题 · 10题⑧

**Q:** If you work remotely, how do you keep yourself accountable daily and weekly? What is on your personal scoreboard?

**A:** At KKday, I worked remotely some of the time. I plan each week around handoff points. For a booking page, I first agree when we test with the backend, and when QA gets it. Then I plan my own coding time around that. Each day follows those points. If we test with the backend in the afternoon, I get the flow working in the morning and list the API issues. So we can fix them together right away. My updates are specific. For example: "The page is done. The main flow works. Empty stock is left. I'll check it with the backend tomorrow." That way, QA knows what they can test first. Across time zones, I'd write the questions, sample data, and what needs confirming clearly in advance. Then we'd use the overlap hours to discuss them together. When something urgent comes in, I explain the trade-off. For example: "Today I'll fix the checkout bug. The page redesign moves one day. I'll send the new QA date." Then I confirm it with my lead. Each week, I check three things. Did I deliver what I promised? How much was missed or redone? Did anyone wait on me?

## ✅ B11 · 基准10题 · 10题⑨

**Q:** Would you deliver bad news to your team early or later?

**A:** Early. The sooner the team knows, the more time they have to adjust. But I bring the problem and a suggestion together. At Debon Securities, I was rebuilding part of our trading app. It was planned to ship with that week's release. During testing, I found some old pages had a broken back button with the new navigation. I hadn't checked every page yet. But it could already affect the release. So I told the project manager that same day. I said: "Some pages are confirmed broken. I'm still checking the rest. If this ships this week, we may not have time to test it fully. I suggest we keep the old pages, and move this change to the next release. Everything else can ship as planned. I'll update you tomorrow afternoon on the impact and the fix." We changed the release scope. Everything else shipped on time. My change shipped later, after it was fixed and tested. To me, telling early gives the team time to choose. And I don't just report the problem. I keep pushing the fix, and keep everyone updated.

## ✅ B12 · 基准10题 · 10题⑩

**Q:** What are your salary expectations?

**A:** I saw RMB 40K to 60K a month and 15 months of pay on BOSS. Does that range apply to the role I'm interviewing for? How many of the 15 months are guaranteed, and how is the rest paid? What level are you considering me for? If most of the 15 months are guaranteed, I'd be looking for RMB 50K to 55K a month before tax, with equity discussed separately. I've owned Android performance and delivery, and at KKday I worked on streaming and failure handling for the AI trip planner.

## ✅ B13 · 基准10题 · 10题⑩

**Q:** What is your current or previous compensation?

**A:** I'd rather focus on what this role is worth. It's quite different from my last job. Could you share the budget range for it?

## ✅ B14 · 基准10题 · 10题⑩

**Q:** What's your minimum?

**A:** My minimum depends on how much of the package is guaranteed. What fixed yearly cash is the team considering? With a real package in front of me, I can give you a clear answer.

## ✅ B15 · 基准10题 · 10题⑩

**Q:** When can you start?

**A:** I'm based in Shanghai, and I'm not working right now. I don't have a non-compete, so I can start soon. If you have a target start date, I can work around it.

## ✅ B16 · 基准10题 · 10题⑩

**Q:** Can you work with an international team in English?

**A:** Yes. I can walk you through my work in English. For example, at KKday the app showed the first day of a trip while the planner was still working on the rest. If a discussion gets unclear, I restate the decision in my own words and follow up in writing, so everyone has the same understanding.

## ✅ F01 · 资料补充题 · 手册Q1/框架A1

**Q:** Tell me about yourself.

**A:** Good morning, I'm Jianhui. I have ten years of experience in software development, mainly working on Android apps. Over the past three years, I've also been working on AI products, from development to launch. My most recent job was at KKday, a travel platform in Asia. I worked on the main features of the Android app and made the app run faster. For example, I fixed the lag when users switched between product options. At the same time, I was the technical lead for an AI trip planning project. I was responsible for the technical plan, the agent architecture, and the main backend development. With this feature, users could plan their trips with AI directly in the app. After we launched it, the system handled about 300,000 trip planning requests every day. Before KKday, I worked at Kezhi Technology, an AI education startup. I was the only Android engineer there. I built the Android app and worked with my team to launch the first version in just four weeks. That's also when I started working on AI features myself. Before that, I worked on Android apps at Debon Securities. I also spent six years working on Android apps at Ping An. I'm interested in ActAI because I like how you're bringing AI into everyday communication. Your AI helps users get things done, while users stay in control. I also have my own app called Cabinet AI. It explores similar questions, like when AI should act on its own, and when it should ask users first. I hope I can bring my Android and AI experience to ActAI and work with the team to build a product that people can trust and enjoy using every day. Thank you.

## ❌ F02 · 资料补充题 · 框架A2

**Q:** Could you walk me through your career timeline and current employment status?

**A:** Sure. I started at Ping An Securities in 2015, then moved to Ping An Haoxue in 2018. That was almost six years at Ping An. From 2021 to 2023, I was at Debon Securities. Then Kezhi, an AI education startup, until February 2025. Then KKday, until August this year. Right now I'm not working. KKday cut many jobs in Shanghai, and I was one of them. I took September off, and started looking in October.

- 缺少要点：2026

## ✅ F03 · 资料补充题 · 框架A3

**Q:** What is the most important career decision you have made, and why?

**A:** The most important decision was taking on the RAG question-answering system at Kezhi. I was the only Android engineer there, and I could have stayed only on Android. But the company needed a Q&A tool for students, so I took it on at the same time. I learned it by building it and testing it with real questions. That decision changed my path. Without it, I wouldn't have led the AI trip planner at KKday, or be applying for this role.

## ✅ F04 · 资料补充题 · 框架A4

**Q:** How would you describe your contribution to someone without an engineering background?

**A:** I make apps feel fast and clear, especially when AI is involved. For example, an AI trip plan takes time to make. Instead of making travelers stare at a loading screen, we showed them day one first, while the rest was still coming. They could start reading and planning right away. That's my job: the part of AI that people actually see and touch.

## ✅ F05 · 资料补充题 · 反馈第六份/杂乱4.14

**Q:** What motivates you?

**A:** What drives me most is when a problem I fix becomes something users can feel. At KKday, when users picked a date, package or ticket type, each tap took about one second to update the price and stock. If you switched a few options, the waiting was obvious. I found the cause and changed how the data was prepared. Response time dropped to about 300 milliseconds. The best moment was going through the booking flow myself afterwards. Switching options felt smooth. I could feel the difference. I enjoy that whole path: finding the problem, the cause, and fixing it myself. That kind of feedback keeps me going. So I care a lot about waiting time in AI apps too. This role is about lower latency and a better real experience on Android. That's exactly the kind of work that drives me.

## ✅ F06 · 资料补充题 · 手册Q4/杂乱4.16

**Q:** Why an AI assistant rather than a traditional Android role?

**A:** I like problems users can feel. In a normal app, a tap has a predictable result. With an assistant, the answer comes in pieces, can be wrong, or the request can be unclear. Deciding what the user sees while they wait, and how they fix a mistake, is the part I enjoy. It uses the Android I know well, on a problem I want to work on.

## ❌ F07 · 资料补充题 · 框架B3

**Q:** Why an Android engineering role when you also have agent and RAG experience?

**A:** Android has been the constant in my whole career, and it's where users meet the AI. My agent and RAG work helps me understand what the backend can and can't promise. So I know what to show when it's slow or wrong. Yes, I'd be happy if most of my work were Android delivery. That's the job I'm applying for.

- 缺少要点：same time / both

## ✅ F08 · 资料补充题 · 手册Q5/杂乱4.8

**Q:** What attracts you to an early-stage product?

**A:** An early-stage product lets an engineer still change what gets built. At Kezhi, I was the only Android engineer, and I built the whole Android app myself, from zero to launch, in four weeks. I liked being that close to the product. At ActAI, I'd want to work the same way: pick one task people repeat every day, get a small version to users fast, and learn from how they use it.

## ✅ F09 · 资料补充题 · 手册Q6/杂乱4.13

**Q:** Why should we hire you instead of someone with more recent AI experience?

**A:** I've been building AI into real products for three years, and I've done it on Android, not just in a demo. At KKday, I was the technical lead for the AI trip planner, and it handled about 300,000 trip plans a day. I designed the agent, built the core backend, and worked with the app team on how the plan shows up on the phone. In my own time, I built CabinetAI myself: the app, the backend and the website. So I've already faced the hard questions, like when the assistant should act and when it should ask first. Someone with newer AI experience may know the latest models. But I can take that AI and make it fast, clear and reliable on a real phone, and that's what your users will actually see.

## ✅ F10 · 资料补充题 · 手册Q7/框架K4

**Q:** Where do you see yourself in three to five years?

**A:** In three to five years, I want to own a large part of an AI mobile product. I want to own it from the first design decision to daily use by real users. I'd start by making one everyday task work really well on Android, like setting up a meeting from a chat. Then I'd grow that into the full experience: what the user sees while the AI is still working, what happens when the answer is wrong, and how they fix it. Later, I want to help other engineers make those same choices. The title matters less to me. Earning that trust matters more.

## ✅ F11 · 资料补充题 · 框架B2

**Q:** What are you looking for in your next role, and what would be a deal-breaker?

**A:** There are three things I'm looking for. First, AI on mobile is the core product, not a side feature. Second, I own the Android experience from start to finish. Third, I work closely with backend and AI engineers in a small team. If I had to rank them, the product comes first, then ownership. Pay and working arrangements matter too, but they come after those. My deal-breaker is a job that's mostly maintenance, with no say in what users experience. I want to help shape the feature, and stay responsible for how it works after launch.

## ✅ F12 · 资料补充题 · 框架B4

**Q:** What would make you stay with your next team for several years?

**A:** Three things would make me stay. A meaningful problem I own, chances to keep learning, and seeing the product get better for users. I'd also look at the core team. If the core people stay committed when things get hard, I stay too. I stayed at Ping An for almost six years, so I know I can commit for the long run.

## ✅ F13 · 资料补充题 · 手册Q20/杂乱4.19

**Q:** Would you leave quickly if another company offered you more money?

**A:** Money alone wouldn't make me leave quickly. Pay matters, and I'd want us to agree on a fair package up front. After that, I'd judge the role by the work: do I own a meaningful problem, am I learning, and can I see the product getting better for users? A higher number doesn't answer those questions. I stayed at Ping An for almost six years, so I commit when the work is right. If a real problem came up, like the core team leaving, I'd talk to my manager first, not just take the money and go.

## ✅ F14 · 资料补充题 · 手册Q19/杂乱4.18

**Q:** What would make you reject an offer?

**A:** I'd reject an offer if the job turned out to be mostly maintenance, with no say in what users experience. I'm looking for a role where I help shape the feature and stay responsible for how it works after launch. A package far below what the role is worth would also make me pause, but I'd rather discuss that openly than reject on the spot.

## ✅ F15 · 资料补充题 · 框架C2

**Q:** Who do you think would use this product, and what problem would it solve for them?

**A:** The people who'd use it most are anyone who coordinates with others every day: friends, families and small teams. Take a group of friends agreeing on a Friday meeting in a chat. Today someone still has to create the event, send the invite and check everyone got it. ActAI could draft the invite, ask one short question if the time is unclear, and send it after the user confirms. It saves those follow-up steps every day, so people don't have to do the copying and checking by hand.

## ✅ F16 · 资料补充题 · 框架C3

**Q:** How would you explain the idea of 'Cursor for everyone' in practical user terms?

**A:** Cursor lets programmers say what they want, and it writes the code with them. ActAI does the same for daily life. You say "let's meet Friday with Anna," and it handles the calendar, the invite and the reminder. The hard part is adoption. People already have WhatsApp and a calendar app. So it has to save time on something they do every day, from day one.

## ✅ F17 · 资料补充题 · 框架C4

**Q:** What would you want to learn about our product before deciding to join?

**A:** Three things. First, which task you want users to trust ActAI with first. Second, how you decide when the assistant acts on its own and when it asks. Third, how product, Android and ML decide together when something goes wrong. The assumption I'd most want to test is that fewer prompts really save time, and that the questions it asks don't cost more than they save.

## ✅ F18 · 资料补充题 · 手册§4

**Q:** Your recent roles were shorter. How long have you stayed with one organization?

**A:** I spent nearly six years at Ping An, from September 2015 to August 2021. I started at Ping An Securities, then moved to Ping An Haoxue in May 2018. In August 2021, my team moved to Shenzhen. My son was born in 2019 and was still very young, so I chose to stay in Shanghai. Two of my last three jobs ended in layoffs, so this time I'm choosing carefully. I want mobile AI to be the main product, not a side project.

## ✅ F19 · 资料补充题 · 手册§4

**Q:** How large was your KKday team, and how was your performance rated?

**A:** I was on the Tour team at KKday, twelve people. Five of us worked on the AI trip planner, and I was the technical lead. Our manager rated us on our past work and feedback from colleagues, and I was in the top 30% of the Tour team.

## ✅ F20 · 资料补充题 · 手册§4

**Q:** Why did you move from securities to education, from Debon to Kezhi?

**A:** Kezhi gave me a chance to build a product from the start. I was the only Android engineer there, and I built the whole Android app from zero to launch in four weeks. That's the kind of ownership I wanted, and it's why I moved.

## ✅ F21 · 资料补充题 · 框架E2

**Q:** How did you handle the transition after your role was affected by the layoff?

**A:** After KKday, I handed my work over first. Then I took September off, which I hadn't done in years. I travelled a bit and spent time with my grandmother back home. She raised me, so that time mattered to me. I started looking again after the October holiday, about a month ago. So far I've talked to four companies, in finance, securities and e-commerce, and some offers are still under discussion. The main lesson was about choosing a team. I check the funding and whether the core team is committed before I join.

## ✅ F22 · 资料补充题 · 框架E3

**Q:** What did those transitions teach you about choosing your next team?

**A:** Two things. First, check the funding and whether the core team is committed. At Kezhi, the business depended on public schools, and payments were slow. When the core team left, there was nothing left to build. Second, check that the work is real and I can own it. So now I ask those questions before I join, and I'm asking them here too.

## ✅ F23 · 资料补充题 · 框架E4

**Q:** Is there anything in your timeline or references that you'd like to clarify?

**A:** Two small things. The Aihuishou dates overlap with Ping An because it was part-time consulting, outside my working hours. And Kezhi was my own decision to leave, not a layoff. Otherwise, my KKday team lead can speak to my recent work, and I'm happy to share his contact details when you need them.

## ✅ F24 · 资料补充题 · 框架D2

**Q:** How has your agent or RAG work changed the way you build mobile experiences?

**A:** In a normal app, you tap and get a result. With AI, the answer comes in pieces, can be wrong, and takes time. So I now design for the waiting and the failure, not just the result. At KKday, the AI trip planner took time to build a full plan. So we showed day one first, while the rest was still being made. Users could start reading right away. And every plan was checked by normal code before they saw it. If a check failed, it retried, then showed a safe fallback instead of a broken screen. At Kezhi, my RAG work taught me the same lesson. The AI should answer from real material, not from memory. So I narrow the search by subject, grade and chapter first. And it says clearly when there isn't enough material. In CabinetAI, I went further. Calendar and reminder changes are only proposals. They run after the user taps Apply. And if a step fails, it keeps the parts that worked and retries only the failed part. So the main change is this. I don't treat the AI answer as the product. The product is what the user sees while they wait, and what happens when it's wrong.

## ✅ F25 · 资料补充题 · 框架D3

**Q:** What would you need to learn to become effective in this role?

**A:** Two things. First, your product and users: which tasks matter most, and how the team decides when the assistant acts. Second, on-device AI. I've used AI mostly through the backend, and I have little hands-on experience with TensorFlow Lite or ML Kit. In my first month, I'd build a small working example with your models, and pair with the ML engineer on how you ship model updates.

## ✅ F26 · 资料补充题 · 框架F1

**Q:** Tell me about a project you owned from an unclear problem through delivery.

**A:** The AI trip planner at KKday is the clearest one. The goal was simple to say but unclear to build: help travelers plan a trip they can actually book. Planning by hand was slow. People had to work out the budget, search products one by one, and put the plan together themselves. I was the technical lead on a five-person project. I designed how the agent works, connected it to our real product and order data, and built the core backend. I also agreed with the app team how a day card and a map point should look, so the app could show day one first while the rest was still being made. Every plan was checked by normal code before travelers saw it. If a check failed, it retried, then fell back to a safe default. In the end it handled about 300,000 trip plans a day. The decisions that were mine were the agent design, using only real bookable products, checking every plan before showing it, and showing the trip day by day instead of all at once.

## ✅ F27 · 资料补充题 · 框架F2

**Q:** Which achievement are you most proud of, and how did you measure its impact?

**A:** The product page at KKday is the one I'm most proud of. When a traveller tapped a tour, it took about a second before the options and prices appeared. That's long enough to feel slow. I looked into it and found the app was reading the same data again and again, and doing heavy calculations at the moment the page opened. So I simplified the data, prepared the price and stock lookups in advance, moved the heavy work into the background, and cached the results. It went from about one second to about 300 milliseconds. I measured from the tap to the screen finishing. And I went through the booking flow myself afterwards. Switching options felt smooth.

## ✅ F28 · 资料补充题 · 框架F3

**Q:** Tell me about a time you solved a problem outside your formal responsibilities.

**A:** At Debon Securities, testers found that after you changed the order of your watchlist, it sometimes went back to the old order when you came back. It involved the app's local cache and the server sync. Both sides checked their own part and found nothing, so it stopped. It wasn't only my part, but I recorded the full steps and sat down with the backend engineer. We compared the request timing and found that old data could overwrite the new order in one case. We fixed and tested it together. For me, a user problem needs someone to push it one step further.

## ✅ F29 · 资料补充题 · 框架F4

**Q:** Tell me about a project that did not achieve the result you expected.

**A:** The project that didn't achieve the result I expected was at Kezhi. Technically, it went well. I was the only Android engineer, and I built the whole Android app from zero to launch in four weeks. I also worked on the RAG question-answering system at the same time. But the business didn't work out. It depended on public schools, and getting paid was slow and hard. Then the core team left, and there was no real product work left. What I missed was looking at the business model before I joined. I only looked at the technical challenge. Now I ask about funding and the core team first, before I decide.

## ✅ F30 · 资料补充题 · 手册§5

**Q:** Tell me about a time you had to move fast.

**A:** At Kezhi, I was the only Android engineer, and I built the whole Android app for an exam-prep product from zero to launch in four weeks. Back then, AI coding tools weren't good enough, so I wrote and worked out almost all of it myself. Some screens were in the app, and some were web pages. So I set up routing between modules. I also made a way to show web pages inside the app. That way, both kinds of features made the first version.

## ✅ F31 · 资料补充题 · 手册§5

**Q:** What would you do if you couldn't stop feature work to fix reliability?

**A:** I'd fix the reliability path first and keep the other features moving. At Debon, the trading app still needed new features while we improved the architecture and fixed crashes. So I did both. I built the watchlist, moved shared network code into one place, and fixed crashes group by group, the most common first. Over time, the team cut the crash rate to about one tenth. Here, if users were losing messages, I'd fix that path first. I'd tell the team what moves and what waits, so nobody is surprised.

## ✅ F32 · 资料补充题 · 框架G2

**Q:** How do you handle a short period of intense work before a critical launch?

**A:** I'm fine with intense sprints when there's a clear goal and an end date. At Kezhi, I was the only Android engineer, and I built the whole Android app from zero to launch in four weeks. Back then, AI coding tools weren't good enough, so I wrote and worked out almost all of it myself. I focused on what had to work on launch day and dropped the rest. I also protected quality: I didn't skip testing on the core flow. At KKday, I was the technical lead for the AI trip planning project. Launches were tight, and the goals changed as we learned. I shipped fast, and when something broke, I fixed it fast. I keep good habits too. I plan my morning and send a short update every evening. That helps me keep a high pace for a long time, not just for one week. After a launch, I look at why it was intense, so the next one is calmer.

## ✅ F33 · 资料补充题 · 框架G3

**Q:** How would you respond if a founder changed direction after two weeks of your work?

**A:** First, I'd make sure I understand why the direction changed and what success looks like now. Then I'd check what from my two weeks can still be used, because usually something can. If I see a big risk, I'd say it once, clearly, with facts. Then I'd move on and build the new direction. That's normal in a startup, and I'd rather adapt fast than defend old work.

## ✅ F34 · 资料补充题 · 框架G4

**Q:** Tell me about a time you chose a simpler solution to ship sooner.

**A:** At Kezhi, we had four weeks to launch the first version of our exam-prep app. Some features were already built as web pages. Instead of rebuilding them in native Android, I set up a way to show those web pages inside the app, and let them call phone features. That way both kinds of features made the first version. The risk was that web pages feel a bit less smooth. So I kept the core flow native and stable, and didn't compromise there.

## ✅ F35 · 资料补充题 · 框架H2

**Q:** Tell me about a mistake you made that affected other people.

**A:** At KKday, I finished a booking page on time, but I'd left all the API questions to the last day. When we tested with the backend, the out-of-stock data didn't match what the app expected. Both sides had to change and retest, so QA got it late. That was my planning mistake. I told QA the new date and why. Since then, I ask the backend for sample data before I start coding: normal, in stock and out of stock.

## ✅ F36 · 资料补充题 · 框架H3

**Q:** What would you do if a stakeholder asked you to present an uncertain result as a confirmed improvement?

**A:** I wouldn't present it as confirmed. I'd say what we actually measured, and what we don't know yet. For example: "In testing it's about 30% faster; we haven't seen real user data yet." Then I'd suggest how to confirm it, like a small rollout. Being honest early is safer than taking it back later.

## ✅ F37 · 资料补充题 · 框架H4

**Q:** Tell me about a time you changed your mind after receiving new evidence.

**A:** I changed my mind about CabinetAI after testing it with real tasks. At first I wanted the assistant to do everything on its own, because that was the whole point. But when I tried it, a wrong calendar change was much worse than one extra tap. So I changed the design. Now calendar and reminder changes are only proposals, and they run only after the user taps Apply. Fewer surprises matter more to me than fewer taps.

## ✅ F38 · 资料补充题 · 框架I1

**Q:** Tell me about a disagreement with a manager, product partner or engineer.

**A:** At KKday, a feature worked but had a visible delay. Product felt it was good enough for this release, and I wanted to fix the delay first. I understood their point: the release date mattered. So instead of arguing about everything, we went through it together. We listed which delays hurt the core booking flow and which could wait. We fixed the one in the core flow in this release, and put the rest in the next one. I learned to bring a clear list, not just "it feels slow".

## ✅ F39 · 资料补充题 · 手册§5

**Q:** How did you handle coordination between the backend and the app at KKday?

**A:** At KKday, we used one channel to talk and one page for the facts. Each project had its own Slack channel with the owners from product, design, Android, iOS and backend, so it was clear who owned what. Everything was in one Confluence page: the requirements, the designs, the plans for each platform, and the QA test cases. Two things made it work. First, the page was the single source of truth. If a requirement changed, we updated the page first, wrote why and which platforms it affected, and then told those owners in the channel. So Android and iOS never built two different versions. Second, we agreed on the API first. In the tech review, all sides agreed on the fields, error codes and edge cases. The apps were built against a mock API, so integration went smoothly. If a change came in the middle, each platform checked the impact, and the product manager decided whether it went into this release or the next one. As the Android engineer, I raised app-side issues early, like poor networks, empty states and older app versions. For a remote team, this written way of working matters even more.

## ✅ F40 · 资料补充题 · 框架I4

**Q:** Tell me about a time you helped a teammate who was struggling.

**A:** At KKday, a colleague was working on keeping the later days of a trip consistent after one day changed. It took much longer than expected, and he only raised it at integration time. I sat down with him to see where he was stuck. We split out the parts the app could already test, so the client team could keep going. I agreed the rest of the plan with product, and we finished testing in stages. After that, he raised blockers much earlier.

## ✅ F41 · 资料补充题 · 反馈第七份

**Q:** What kind of environment would make it hard for you to perform?

**A:** I'm fine with fast changes and a process that's still being built. What makes it hard is when poor communication keeps causing rework, and nothing changes. For example, developers and QA work from different versions of the same feature. They only find out near the end. That happens sometimes, and it's normal. When it does, I put the latest decisions and changes in one shared place. I ask the people involved to confirm it. A simple fix first. I don't expect a team where everything is already set up. I'm happy to help build how we work. What matters to me is that when we find a problem, we adjust together, so it happens less next time.

## ✅ F42 · 资料补充题 · 框架J2

**Q:** Tell me about a time asynchronous communication prevented or caused a problem.

**A:** Yes, that happened at KKday. After the booking page issue, we agreed that any shared API change comes with a written note and sample data. Later, when the backend changed those APIs, we found what both sides needed to change before we even tested together. So writing things down prevented a lot of problems. It can also cause one: if a message is unclear, people wait. So if something is still unclear after two messages, I switch to a short call.

## ✅ F43 · 资料补充题 · 框架J3

**Q:** How would you work with a team spread across several time zones?

**A:** I'd plan around the overlap hours. I'd write questions, sample data and what needs confirming clearly in advance, so people can read them in their own time. Then we'd use the shared hours to decide together. Each day I'd post a short update: what's done, what's blocked, what's next. If something is still unclear after two messages, I'd switch to a short call.

## ✅ F44 · 资料补充题 · 框架J4

**Q:** How do you handle a discussion in English when you don't fully understand a requirement or you disagree with it?

**A:** I ask right away instead of guessing. For example: "Sorry, just to check: do you mean the invite is sent only after the user confirms?" If I disagree, I say it simply: "I see a risk here. If the network drops, the user won't know if it was sent. Could we show a status?" After the meeting, I write the decision down and share it, so everyone has the same understanding.

## ✅ F45 · 资料补充题 · 反馈第五份

**Q:** Do you do a weekly review? Give me an example of how it changed your approach.

**A:** Yes, I do a short review every week. I look at what didn't go as planned, and what I should change. Once, at KKday, I finished a booking page on time. But on the day we tested with the backend, we found a problem. When stock was empty, the API data didn't match what the app expected. Both sides had to change and retest, so QA got it late. In the review, I saw my mistake. I only planned when the code would be done. I left all the API questions to the last day. So I changed how I work. Before coding, I ask the backend for sample data: normal cases, in stock, and out of stock. I list problems early. And I plan separate time for testing and fixes. After that, we found most data issues before testing together. There was less last-minute rework, and QA dates were easier to predict. What changed was how I judge progress. A finished page is just one step. It's done when it works with the backend and QA can test it.

## ✅ F46 · 资料补充题 · 框架K1

**Q:** What is the most useful critical feedback you have received?

**A:** The most useful critical feedback I've received was from my team lead at KKday. He told me to keep the scope of my changes under control. There was a feature I could have built on the existing architecture. It needed quite a lot of code, so I wanted to improve that part of the architecture at the same time, to make future work easier. But that made the release take longer. That taught me that even a good long-term improvement needs the right timing. Now, when this comes up, I describe the feature and the architecture work separately, and agree with the team whether it's worth doing both in this release.

## ✅ F47 · 资料补充题 · 框架K2/反馈第八份

**Q:** Tell me about something difficult you learned recently and applied in practice.

**A:** The hardest thing I learned recently was making several AI agents work together in CabinetAI. One agent understands the request and makes a plan. Then other agents handle expenses, reminders and tasks. The hard part wasn't calling the model. It was reliability. The assistant asks when a date is unclear. It never says something worked when it didn't. And it retries only the part that failed. I learned it by building it and testing it with real tasks, across four time zones.

## ✅ F48 · 资料补充题 · 框架L1

**Q:** Tell me about a time user feedback changed your engineering priorities.

**A:** Honestly, I didn't have formal user feedback data on my recent work. On the KKday product page, I checked the experience myself by going through the booking flow. Here, I'd watch where users drop off and where they correct the assistant, and fix the step that causes the most corrections first.

## ✅ F49 · 资料补充题 · 框架L2

**Q:** How do you decide when AI is useful and when a simpler approach is better?

**A:** I use AI where the input is messy and normal code can't handle it. I use plain code where the answer must be exact. At KKday, the AI understood "Tokyo, three days, 5,000 yuan" and arranged the trip. But prices and stock came from our real product data, not from the AI. And every plan was checked by normal code before travelers saw it. So AI for understanding, simple code for facts and rules.

## ✅ F50 · 资料补充题 · 框架L3

**Q:** How do you use AI coding tools while staying accountable for what you ship?

**A:** I use AI coding tools every day, but I stay accountable in three ways. First, I write the core architecture myself. In CabinetAI, I built the base framework by hand, and I used AI tools only for the simpler screens. Second, I review and test everything the tools generate before it goes in. Third, I keep the design decisions mine. The tools help me type faster, but I decide what the app should do and how it should behave when something fails. So the code is faster to write, but the responsibility is still mine.

## ✅ F51 · 资料补充题 · 框架L4

**Q:** Imagine an AI communication feature gives a misleading answer or captures audio unexpectedly. What would you do?

**A:** First, I'd stop the damage. I'd pause the feature or the rollout if we can. Then I'd tell the team right away: what happened, how many users might be affected, and what we don't know yet. For the audio case, I'd check whether we had permission and whether the recording was stored. If it was, I'd make sure it's deleted. While we look for the cause, I'd decide with product what to tell the affected users. After it's fixed, we'd review it without blame and add a check, so the same mistake can't ship again.

## ❌ F52 · 资料补充题 · 框架M4

**Q:** Are you in other interview processes, and what is your decision timeline?

**A:** Some are still under discussion. I started looking after the October holiday, so about a month now. I expect to decide within a few weeks, and I'd be happy to move quickly if things go well here. ActAI is my first choice if the package works.

- 缺少要点：four

## ✅ F53 · 资料补充题 · 框架M条件

**Q:** How would you evaluate a counteroffer?

**A:** I'd judge a counteroffer the same way as any offer: the problem I'd own, the learning, the product and team, and then pay. If I've decided ActAI is the right place, more money from somewhere else wouldn't change those reasons.

## ✅ F54 · 资料补充题 · 框架M条件

**Q:** Do you have any conflicts of interest or outside commitments relevant to this role?

**A:** No conflicts. My only side project is CabinetAI, a personal project with no business. If I join, I'll stop working on it.

## ✅ F55 · 资料补充题 · 框架M3

**Q:** Is there any work authorization or sponsorship requirement we should plan for?

**A:** I've worked in China my whole career and don't need sponsorship to work here.

## ✅ F56 · 资料补充题 · 手册Q18/框架N2

**Q:** Do you have any concerns about the role?

**A:** One concern I'd like to understand: how the first use case gets chosen. It affects how fast I can put something useful in front of users. So how do product, Android and ML make that decision together?

## ✅ F57 · 资料补充题 · 手册Q21

**Q:** Is there anything else you'd like to add?

**A:** Just one thing. I've built AI features people used every day, and I've spent ten years making Android apps fast and reliable. At ActAI, I'd like to make one everyday coordination task easier, and make it clear when the user is in control. I'd be happy to keep talking with the team.

## ✅ F58 · 资料补充题 · 框架N3

**Q:** What would you want us to remember about you after this conversation?

**A:** Two things. I've shipped AI features that real users used every day, about 300,000 trip plans a day at KKday. And I'm an Android engineer first, so I care about how it feels on the phone. That's the mix this role needs.

## ✅ F59 · 资料补充题 · 框架N4

**Q:** Is there anything we haven't covered that would help us evaluate your fit fairly?

**A:** Maybe that I've already thought about your problem in practice. In CabinetAI, I built the approval step for actions that affect others. I'd be happy to show it to the engineering team.

## ✅ F60 · 资料补充题 · 框架N1

**Q:** What questions do you have for me?

**A:** Thanks, I do have a few questions. First, six months after I join, what would make you feel you hired the right Android engineer? Second, in the next six to twelve months, which user task does ActAI most need to get right, and how do you tell that users find it useful and come back? Third, what's the biggest mobile challenge right now: voice response speed, handling partial results, or reliable actions? And last, how many Android engineers are there now, and when a feature breaks, how do Android, backend and ML work together?

## ⚠️ N01 · 预测新增题 · 今日定稿

**Q:** Two of your roles ended in layoffs. Why do you think you were the one affected?

**A:** The company didn't give a specific reason, and it paid me severance. I can only share my view. At KKday, the company was getting smaller, so it kept people for the current app. I spent half my time on Android and half on AI. Two colleagues worked on the app longer, and they knew its history. So keeping them made sense. It wasn't about performance. I was in the top 30% of my team. At Debon, it was similar. The business was weak for two years, and our Android team went from three people to one. They kept the engineer who had been there the longest. Before I left, my work had shipped and I handed everything over cleanly.

- 和定稿差异较大（相似度 0.09）

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

**A:** After KKday, I took September off. I travelled a bit and spent time with my grandmother back home. She raised me, so that time mattered to me. I started looking again after the October holiday, about a month ago. So far I've talked to four companies, in finance, securities and e-commerce, and some offers are still under discussion. I've also been building CabinetAI, my own AI assistant app, in my spare time. But ActAI is the one I'm most interested in, because it's an AI-first product, not a traditional app with AI added on.

## ✅ N06 · 预测新增题 · 今日定稿

**Q:** What's your decision timeline? Is there a deadline we should know about?

**A:** Nothing urgent yet, but I'd expect to decide in the next few weeks. I'd be happy to move quickly if things go well here.

## ✅ N07 · 预测新增题 · 今日定稿

**Q:** Your title went from Senior Architect to Full-Stack Engineer. Is that a step down?

**A:** Titles mean different things at different companies. At Kezhi, the app team was five people, and I reported to the CTO, so "architect" covered a lot. KKday is a much bigger company with its own title system. The work itself didn't get smaller. I led the technical work on the AI trip planning project, and the system handled about 300,000 planning tasks a day. I chose KKday because it was a strong company, I was referred by someone there, and it was close to home. The title wasn't what I was looking at.

## ✅ N08 · 预测新增题 · 今日定稿

**Q:** Are you more of an architect or a hands-on engineer? How much did you actually code?

**A:** Both. At KKday I was leading the project, so about 30% of my time was coding. The rest was architecture, product analysis and data research. Before that, at Kezhi and Debon, I was much more hands-on. In a small team like yours, I'm happy to spend most of my day coding again. The product analysis part still helps, because I can see what users need before I build it.

## ✅ N09 · 预测新增题 · 今日定稿

**Q:** At Kezhi, did you switch from Android to RAG? Why come back to Android now?

**A:** It wasn't really a switch. At Kezhi, I did both at the same time. I kept building the Android app, and I also worked on the RAG question-answering system. Android has been the constant through my whole career. AI is something I learned by using it in real products, first at Kezhi, then at KKday. So for me, this role isn't coming back to Android. It's where both parts of my experience meet.

## ✅ N10 · 预测新增题 · 今日定稿

**Q:** You were top 30%. What would it have taken to be top 10%?

**A:** At KKday, our manager gave ratings based on our past work and feedback from colleagues. I'd been there about a year and a half. It takes time for a team to get used to a new person, and for that person to learn how the team works. My work got better steadily over that time. To reach the top 10%, I think I needed a longer track record there, and more chances for my work to be seen beyond my own project.

## ⚠️ N11 · 预测新增题 · 今日定稿

**Q:** Is CabinetAI a business? Will you keep working on it if you join?

**A:** No, it's not a business. It's a personal project, and it's in internal testing on TestFlight now with a small group of users. If I join ActAI, I'll stop working on it, because I want my full focus here.

- 和定稿差异较大（相似度 0.28）

## ✅ N12 · 预测新增题 · 今日定稿

**Q:** Why is CabinetAI on iOS? Is there an Android version?

**A:** There's an Android version too. I wrote it in my spare time, in Kotlin and Compose. I built the base framework myself and used AI coding tools for the simpler screens, which saved a lot of time. It isn't on Google Play yet, because I'm still finishing the integration testing and the Play setup. The iOS build just reached testing first.

## ✅ N13 · 预测新增题 · 今日定稿

**Q:** When did you last ship production Kotlin? Have you used Jetpack Compose?

**A:** Until August this year, at KKday. Everything was in Kotlin. I introduced Jetpack Compose there, and all our Android screens were rebuilt with it. More recently, I've built the Android version of CabinetAI, also with Kotlin and Compose.

## ✅ N14 · 预测新增题 · 今日定稿

**Q:** Which recent Android project best shows what you could contribute here?

**A:** One I'm proud of is the product page at KKday. When a traveller tapped a tour, it took about a second before the options and prices appeared. That's long enough to feel slow. I looked into it and found the app was reading the same data again and again, and doing heavy calculations at the moment the page opened. So I simplified the data, prepared the price and stock lookups in advance, moved the heavy work into the background, and cached the results. It went from about one second to about 300 milliseconds. For ActAI, it's the same idea: when an assistant answers, the user should see something right away.

## ✅ N15 · 预测新增题 · 今日定稿

**Q:** Do you have any experience with voice on Android?

**A:** Some, yes. At Ping An Haoxue, I packaged our live classroom, including its audio and video, into an SDK. Both the student tablet app and the parents' phone app used it. More recently, in CabinetAI, people can speak instead of typing, on both iOS and Android. I used ElevenLabs for the speech-to-text. I haven't built speech models myself. My side is the app: making voice input feel quick and natural, and handling it well when something goes wrong.

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

## ⚠️ N23 · 预测新增题 · 今日定稿

**Q:** There may be no QA or release engineer here. Are you OK owning testing and releases?

**A:** Yes, I'm fine with that. Testing and releases have always been part of my job. At Kezhi, I was the only Android engineer, so besides building features, I also handled testing and releases. I built the whole Android app from zero to launch in four weeks. I'm happy to own a feature all the way to launch and keep an eye on how it does afterwards.

- 和定稿差异较大（相似度 0.06）

## ✅ N24 · 预测新增题 · 今日定稿

**Q:** Have you interviewed or hired engineers before?

**A:** Yes, I have. I did technical interviews when we were hiring at Kezhi and at KKday. I usually pick one real problem from the candidate's project and follow it: what they were responsible for, how they made the call, why they chose that approach, and how they checked the result. That tells me what they actually did and how they think when things get hard.

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

**A:** I'm based in Shanghai. I'd prefer remote, but I'm happy to work from Beijing if the team needs it. My son is older now, so moving is much easier than it used to be. I'd just come back to Shanghai every month or two to see him.

## ✅ N29 · 预测新增题 · 今日定稿

**Q:** Would you be open to occasional travel?

**A:** Yes, occasional travel is fine. I'd just like to get home to see my son every month or two.

## ⚠️ N30 · 预测新增题 · 今日定稿

**Q:** Do you have a non-compete agreement?

**A:** No, I don't have a non-compete. I'm free to start with a new company right away.

- 和定稿差异较大（相似度 0.56）

## ✅ N31 · 预测新增题 · 今日定稿

**Q:** Can you explain something technical you built, in simple English?

**A:** At Kezhi, I worked on an AI tool that answers students' questions using their learning materials. Instead of asking the AI to answer from memory, we first find the right content in the textbooks. We narrow the search by subject, grade and chapter, so we don't mix up different courses. Then we give that content to the AI to help it answer. It's like an open-book exam: find the right material first, then explain the answer. That way, the answers stay accurate and match what the students are actually learning.

## ✅ N32 · 预测新增题 · 今日定稿

**Q:** How do you keep an app stable in production? Have you worked on crashes?

**A:** Yes, I've worked on crashes a lot. At Debon Securities, I tracked and fixed crashes in production, and our team cut the crash rate from about 1% to about 0.1%. We tracked it in Bugly, as crashes per app launch. Most crashes were null pointers, out-of-memory errors, WebView crashes, and problems on certain phone models. We fixed them group by group, starting with the most common. For keeping an app stable, I do three things. First, I watch the crash rate after every release, so a new problem shows up fast. Second, I fix the most common crash first, because that helps the most users. Third, I add a check or a test so the same crash can't come back. At KKday, I also made sure the app handled a failed AI answer safely, with a fallback instead of a broken screen.

## ✅ H01 · Head/Hustle 顾虑 · 2026-11-12

**Q:** How do you think about work-life balance? This is a startup, and it can get intense.

**A:** I'm fine with intense sprints. That's part of building something new. At KKday, I was the technical lead of the AI trip planning project. Launches were tight, and the goals changed as we learned. I shipped fast, and when something broke, I fixed it fast. At Kezhi, I was the only Android engineer. I built the whole Android app myself, from zero to launch, in four weeks. Back then, AI coding tools weren't good enough, so I wrote and worked out almost all of it myself. I also keep good habits: a clear plan every morning and a short update every evening. That helps me keep a high pace for a long time, not just for one week.

## ✅ H02 · Head/Hustle 顾虑 · 2026-11-12

**Q:** How do you feel about working on weekends?

**A:** When the product needs it, I'm there. For a launch or a real deadline, I'll work the weekend and stay until it's done. What I watch is whether it becomes every weekend. If it does, the plan is wrong, and I'd raise it so we fix the plan, not just the hours.

## ✅ H03 · Head/Hustle 顾虑 · 2026-11-12

**Q:** What do you know about our product?

**A:** From what I've read, A1 is an AI-first voice and text app. It's like Cursor, but for daily talk, not code. You say what you want, and it helps get it done with very few prompts. I think two things will decide if people stay. First, timing. The hard part isn't the model. It's knowing when to jump in and when to stay quiet. Too many interruptions, and people turn it off. Second, the phone side. When voice and text are mixed, and the network is weak, the app has to stream the answer, recover, and show clearly what worked and what failed. That's what makes it feel smart, and that's the part I'd own as an Android engineer. I've run into both in my own work. In CabinetAI, my AI assistant, I had to decide when it can act alone and when it must ask, and how to retry only the part that failed. At KKday, we showed the AI trip plan day by day while it was still being generated. So it's not just that I'm interested in AI. I've hit these problems myself.

## ✅ H04 · Head/Hustle 顾虑 · 2026-11-12

**Q:** Tell me about a time you had to move really fast.

**A:** At Kezhi, I was the only Android engineer, and I built the whole Android app from zero to launch in four weeks. Back then, AI coding tools weren't good enough, so I wrote and worked out almost all of it myself. Some screens were in the app, and some were web pages. So I set up routing between modules, and a way to show web pages inside the app. That way, both kinds of features made the first version.

## ✅ H05 · Head/Hustle 顾虑 · 2026-11-12

**Q:** We care about quality, not big-company labels. What in your career shows that quality?

**A:** I think my career shows quality in three ways: I keep getting better, I do deep work, and I make careful choices. First, I keep getting better. I spent ten years on Android, and then I added AI on top. At Kezhi I worked on the RAG question-answering system. At KKday I led the AI trip planner. In my own time I built CabinetAI. Each step added something new, not just a bigger company name. Second, the work went deep. At Kezhi I was the only Android engineer. I built the whole Android app myself, from zero to launch, in four weeks. Back then, AI coding tools weren't good enough, so I wrote and worked out almost all of it myself. At KKday, the AI trip planner handled about 300,000 trip plans a day. Third, my choices show judgment. After Kezhi, I learned to check two things before joining a startup: how the business is funded, and whether the core team is committed. That's why ActAI's self-funded, profitable group matters to me. I'm not chasing a famous brand. I'm choosing a team where I can own real work and keep learning.


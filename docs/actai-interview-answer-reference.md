# 自我介绍（ActAI Android 岗位）· 定稿与追问准备

更新：2026-11-10。来源：用户本次提供的定稿与事实说明。仅供 Mac Assistant 回答参考。

接线：自我介绍原文只在 Assistant 资料 `04_talk_tracks.md` 的「Self-introduction」一节；`Sources/Cicada/InterviewIntroduction.swift` 的 `instruction` 只决定何时照念，进入普通回答、手动刷新与追问审校。新确认和删除的内容优先于旧简历；未核对的方案不能自动成为第一人称历史经历。其他已有独立确认的背景仍可使用。

## 一、已确认的经历事实

- 德邦证券：加快组件 SDK 加载；图片资源异步加载并缓存；异常及时上报。德邦崩溃率（2026-11-11 用户决定保留）：约 1% → 0.1%（Bugly 按每次启动统计），只在被问崩溃、稳定性或可靠性时使用，不主动提。
- 可之科技：负责新 App Android 架构；做了 RAG 知识库问答系统，后来将这套经验带到 KKday。
- KKday AI：5 人 AI 团队技术负责人；设计 Agent、开发核心后端。个性化 AI 基座使用历史搜索偏好、当前位置、历史购买记录、商品折扣；行程与搜索推荐都基于它。
- KKday Android：本人编写核心代码，推动 Compose 落地；网络、本地、图片缓存及骨架屏改善加载体验。SKU 本地计算重构使「点击选项 → UI 渲染完毕」约 1 秒降至 300ms，耗时减少约 70%。
- KKday 两个提速结果（2026-11-11 用户确认，不得混用）：页面（首屏）加载约 3 秒 → 1 秒以内；商品 SKU 选择、筛选及数据联动约 1 秒 → 300ms。自我介绍用后者，Why ActAI 用前者。首屏的测量方式未记录。
- FlutterDouBan：自学 Flutter，边做边学并在 GitHub 分享，9,000+ stars（用户提供的口径）。

## 二、自我介绍定稿（HR 面试版，2026-11-13 最终版，不再修改）

用户 2026-11-13 定稿，开场照念、不改写。原文只保存在 Assistant 资料 `04_talk_tracks.md` 的「Self-introduction」一节，此处不再复制，避免两份不一致：

- 标准版（默认，约 2 分钟，九段，以 “Thank you.” 结尾）：Good morning 开场、十年软件开发（主要 Android）+ 三年 AI 产品从开发到上线 → KKday（亚洲旅游平台）Android 主要功能与提速，例子是修好切换商品选项的卡顿（不带数字）→ 同时任 AI 行程规划项目技术负责人（技术方案、Agent 架构、核心后端；上线后每天约 30 万次行程规划请求）→ Kezhi Technology（AI 教育创业公司）唯一 Android、和团队四周上线第一版、从那时开始亲手做 AI 功能 → 德邦证券 Android、平安六年 Android → 为什么是 ActAI（把 AI 带进日常沟通，AI 帮用户办事、用户保持掌控）→ Cabinet AI（何时让 AI 自己动手、何时先问用户）→ 带 Android 与 AI 经验做让人信任、每天爱用的产品。
- 自我介绍不放具体场景例子，“周五开会”留给 Why ActAI，避免重复。选项卡顿的 1 秒 → 300ms 只在追问时给。
- 短版（约 45 秒）：面试官要简短版或限时一分钟以内时使用，取自标准版原句。
- 一句话介绍自己 / 最大的优点（2026-11-13 用户定稿，取代原“按标准版首段改写”）：不说“我是 Android 工程师”或年限，岗位和简历 HR 已知。两种备选只说一种：默认 **Empathetic**（站在用户角度，关注让产品用起来舒服的细节；追问例子 = 页面等两秒时的柔和骨架屏 + 和后端一起缩短延迟，按“我会”讲，不带 KKday 数字）；问主动性、ownership 时用 **Proactive**（在意自己做的产品，主动让它对用户更好；追问例子 = 聊天约出游要离开去查天气 → 跨 App AI 助手的想法）。先只说一句，HR 问 “Can you give me an example?” 才讲例子。英文原文只在 `04_talk_tracks.md` 的「Describe yourself in one sentence…」一节。
- Proactive 再追问“你做了什么”（2026-11-13 用户确认）：在 Cabinet 里做。已做：回复从长文本改为流式交互卡片（可操作的天气卡、地点卡、第几天行程）。正在做、不得说已完成：浮窗助手，在任何 App 上方顺口问天气、路程，不用切回对应 App；以及保存正在看的内容（如推特上的 AI 文章），之后把相关内容一起存成个人知识库。事实也记在 `03_projects.md` 的 Cabinet 一节。dev 实测见 [评测](evaluations/actai-hr-self-describe-2026-11-13.md) 与 [追问评测](evaluations/actai-hr-proactive-cabinet-2026-11-13.md)。

已从开场删去：AI 数据基座四类数据（偏后端、未核对）、德邦 SDK 加载与缓存细节、FlutterDouBan（Flutter 不是 Kotlin，留到问个人项目时讲）、RAG / Compose / 缓存层等技术词。

## 三、追问准备

### 1. SKU 提速（已定稿）

- 慢因：日期 × 方案 × 票种 × 加购多维耦合；每次点击在主线程全量重算可选状态、价格；重复 JSON 解析。
- 改动：配置解耦拍平；预建「组合 → 价格 / 库存」索引，点击查表；计算转到 Dispatchers.Default，StateFlow 推 UI；内存缓存计算结果。
- 结果：约 1 秒 → 300ms。
- 测量方式不展开（2026-11-14 用户决定）：不说测量工具、分位数或剩余 300ms 构成。
- 英文：Every time a user tapped a SKU option, the app recalculated all combinations on the main thread. I built an index once and moved the work to a background thread. The time from tap to the UI finishing rendering dropped from about one second to 300 milliseconds.

### 2. AI 数据基座（参考答案，需按实际情况核对）

- 来源：搜索 / 点击埋点到数据仓库；授权城市级定位；订单库；促销服务接口。
- 加工：ETL 形成目的地、品类、价格区间、出行时段画像及商品特征；Redis 在线存储，商品另建向量索引。
- 使用：Agent 工具拿画像，按位置、日期、库存、折扣筛候选，个性化重排；LLM 仅用真实候选编排行程。
- 可考虑的评估：订单回放 Recall@K / NDCG、LLM-as-judge、结构校验通过率；线上 A/B 看 CTR、转化率、人均 GMV、行程采纳率。没做过的评估不能说做过，可区分当时指标与重做会补的指标。

### 3. Compose（参考答案，需核对）

- 引入理由：流式行程卡片状态频繁变化，声明式 UI 合适；减少样板代码，跟随官方方向。
- 共存方案：新页面 Compose；ComposeView 嵌入旧页面；AndroidView 包地图等旧组件；共享 ViewModel + StateFlow，桥接主题。
- 可讨论的问题：不可变集合、@Stable、remember、derivedStateOf、LazyColumn key 控制重组；Baseline Profile 改善首帧，性能以 release 包为准；CoordinatorLayout 嵌套滚动；先建组件库和规范辅助团队上手。

### 4. 多级缓存（参考答案，需核对）

- 内存 LruCache → Room / 文件磁盘层 → OkHttp HTTP 缓存（Cache-Control / ETag）→ 网络；Glide / Coil 图片二级缓存与预加载。
- 先缓存展示，后台刷新，再差量更新。
- 按数据类型设 TTL，ETag / 版本判断过期；账号 / 语言 / 币种切换及下单后主动清理；key 包含语言、币种、用户；下单前实时校验价格与库存。
- 骨架屏减少冷启动无缓存时白屏和布局跳动，降低感知延迟，并不使实际加载变快。

### 5. RAG 从可之迁移到 KKday（参考答案，需核对）

- 可复用：切分、向量化、向量 + BM25 + 元数据过滤的混合检索、重排，评测集与回归测试方法。
- 改造：静态文档转动态商品，描述向量化，价格 / 库存实时工具查询；学科 / 年级 / 章节过滤转为目的地 / 日期 / 品类 / 价格；多语言 embedding。
- 输出改为结构化 JSON，校验、重试、兜底；SSE 流式输出降低等待。
- 评测重点从答案准确率转向可订率、结构合法率、转化率。

第 2–5 题仅是排练方案，不能据此声称已采用某技术、踩过某坑或做过某评测。历史问题先答已确认范围并简短标明未知；假设设计问题可以用 “I would” 提议。未知不等于没做过，不能推断未使用某技术或网络耗时为零。

## 四、待办（尚未完成）

- [ ] 按实际做法核对第 2–5 题，删掉没做过的内容。
- [ ] 简历同步 Compose、多级缓存、SKU 1s → 300ms、AI 基座，删除德邦「崩溃率降 90%」。本次未修改简历文件。
- [ ] 继续 HR 第 1 题：离职原因及 2026.08 后在做什么；目前未知。

## CabinetAI 产品介绍与学习定位（2026-11-11 用户确认）

- Cabinet 是个人开发的 AI 日常助手，支持记账、提醒、任务等场景；App、后端和网站由本人开发，使用 AI 辅助开发工具。
- 它也是学习 AI 的实际应用工具：新学的知识、暂时不能直接在公司尝试的想法，先在 Cabinet 做小测试，观察在实际 App 中是否有用。
- 功能或技术效果合适且公司允许时，可以将相应做法结合到公司产品，目标是提升产品质量和用户体验。这是学习与验证方法，不代表已经完成某次公司落地或取得业务指标。
- 普通“CabinetAI 是什么”先简述产品，再说明学习目的。不主动展开 Android 进度、规划时间或承诺停做项目；只有明确追问时才回答对应话题。
- 生效资料：LiveSubs Dev/knowledge 的 00_profile.md、03_projects.md、04_talk_tracks.md；修改后通过 assistantBackgroundReload 重读。


## 为什么看好 ActAI／竞争与成功信心（2026-11-13 用户确认）

User-approved direction (2026-11-13), superseding the older cautious answer. Use this track for equivalent questions: why ActAI can win, why you believe in ActAI, what makes ActAI different, why this is more than another AI pitch, or confidence despite larger competitors. Match the question's language. Lead with a positive product judgment, connect it to everyday communication and useful completed tasks, explain reliability/confirmation/clear results as a route to trust, and close with my Android and AI contribution. Be confident without promising success. Do not lead with uncertainty, funding/runway, or doubt about users changing habits. Do not invent shipped ActAI features, internal architecture, competitor limitations, or business metrics. If the same topic repeats, answer the specific follow-up briefly in the same positive direction rather than repeating the whole track.

> I see a strong opportunity for ActAI because you're starting with everyday communication. Chats lead to real tasks, like setting up meetings and following up on plans. Helping people finish those tasks can give them a reason to use the app every day.
>
> From building AI products at KKday and working on Cabinet AI, I've learned that trust comes from the details: acting reliably, asking when needed, and clearly showing the result. I believe getting those details right can help ActAI stand out.
>
> That's why I want to join. I'd bring my Android and AI experience to help the team turn that vision into a product people trust and enjoy using every day.

我看好 ActAI，是因为你们选择从日常沟通切入。聊天会带出很多实际需要处理的事情，比如安排会议、跟进计划。帮助用户完成这些事情，就能给他们每天使用这个产品的理由。

在 KKday 做 AI 产品，以及开发 Cabinet AI 的经历，让我认识到，信任来自细节：做事是否可靠、需要时能否先询问，以及能否清楚地告诉用户结果。我相信，把这些细节做好，能够帮助 ActAI 做出自己的竞争力。

这也是我想加入的原因。我希望把自己的 Android 和 AI 经验带进来，和团队一起把愿景做成用户信任、每天都愿意使用的产品。

竞争问题应保留大平台已有用户基础的事实，但积极解释 ActAI 如何通过完成具体任务、可靠行动和清楚反馈赢得持续使用；不要断言竞争产品只能被动回答。开发版实际生效源为 `LiveSubs Dev/knowledge/04_talk_tracks.md`，修改后重载并实际验证。

验证追问时保持同一积极方向：从安排会议等高频任务入手，观察完成任务是否更省力、需要多少人工纠正，以及用户是否回来继续使用。持续验证作为行动计划，不以不确定性开场。

回归题库：`tools/actai-confidence-question-bank.json`（6 种中英文同义问法 + 3 道连续追问），也收录至 HR 总题库。关键词仅辅助检查，验收以实际输出的语义、积极程度和事实边界为准。


## 主要优势（2026-11-14 用户确认合并版）

适用：主要优势（复数）及其与 ActAI Android 岗位的匹配。取代旧的跨端排障、低端平板、学习能力三点版。SKU 数字允许用于此题，同场完整案例只讲一次；后续成就或动力题简短回指或换已确认案例。单一最大优点题维持原独立口径。

### 中文

我觉得有两点。

第一，我比较善于把用户体验上的问题，变成具体的技术改进。在 KKday，用户切换日期、方案或票种时，每次都要等大约一秒才能看到更新。我调整了计算方式，把响应时间降到了约三百毫秒。我很在意这种用户每次操作都能感受到的细节。

第二，我会主动解决影响团队协作的问题。KKday 当时的需求、设计和接口资料比较分散，我提出每个项目统一一个 Slack 频道和一份 Confluence 文档，并推动团队使用。后来，我在技术分享会上介绍了这套做法，其他团队也采用了。

我希望把这两点带到 ActAI：把 AI 在手机上的体验做好，同时主动和产品、AI、后端同事配合，帮助团队更顺畅地交付。

### English

I'd say two things.

First, I'm good at turning user experience problems into practical improvements. At KKday, when users changed a date, package or ticket type, they had to wait about one second for the screen to update. I changed how the app handled the calculations and brought that down to about 300 milliseconds. I care about details that users can feel every time they use the app.

Second, I take the initiative to improve teamwork. At KKday, requirements, designs and API details were spread across different places. I proposed one Slack channel and one Confluence page for each project, and helped the team adopt this approach. Later, I shared it at a tech sharing session, and other teams adopted it too.

I'd bring both strengths to ActAI: making AI work well on a phone, and working closely with product, AI and backend colleagues to help the team deliver more smoothly.


## Work-life balance（用户确认精简英文版）

适用：WLB、创业公司工作节奏。保留可之为 AI 创业公司的定位；不添加加班时长、固定晨晚汇报习惯或未确认的历史冲刺事件。同场可之四周上线已展开时仅简短回指。

I'm comfortable with a fast pace and extra effort around important releases, including evenings or weekends when needed.

At Kezhi, an AI startup, I was the only Android engineer, and we launched the first version in four weeks. So I understand the pace of a small team.

When priorities change, I'd confirm what matters most, adjust my tasks, and raise risks early so the team can keep moving.

I also value family time and rest, and I plan around my responsibilities. I want to contribute over the long term, stay focused, and deliver work the team can rely on.

同步状态：项目参考资料已保存；开发版 `LiveSubs Dev/knowledge/04_talk_tracks.md` 受目录写入权限限制，尚未同步。本轮未跑批。前一节主要优势同样尚未同步至开发版。


## AI 行程项目：个人职责与共同决策（用户确认版本一）

适用：本次模拟第 8 题，个人贡献、决策边界和跨端协作。技术方案由本人主导，跨端数据格式共同确认；不得扩写为产品范围、上线时间或重试上限由本人最终拍板。

### 中文

在这个五人项目里，我是技术负责人，主要负责整体技术方案、Agent 架构和核心后端开发，同时也参与 Android 开发。

技术方案由我主导，但涉及前后端配合的部分，需要和相关同事一起确定。比如行程卡、商品卡和地图点的数据怎样返回，我会和 App 团队共同确认，让后端生成的内容能在手机上正确展示。

协作上，我们把需求、设计和各端技术方案放在同一份文档里，有变更也记录进去，再通过项目频道沟通。我的主要贡献，是把 AI 的生成逻辑和 App 的展示需求连接起来，并完成核心部分的开发。

### English

I was the technical lead in a team of five. I led the technical design, designed the agents, and built the main parts of the backend. I also worked on Android.

For work across the app and backend, we made decisions together. For example, I worked with the app team to agree on the data for trip cards, product cards and map locations. This helped us make sure the app could display the AI results correctly.

We kept the requirements, designs and technical plans in one shared document. We recorded changes there and discussed them in the project channel.

My main contribution was connecting the AI side with what the app needed, and building the core parts myself.

同步状态：项目参考资料已保存；开发版实际知识库受目录写入权限限制，尚未同步。未跑批测试。


## 案例：Why are you interested in this role?（2026-11-16 短句版）

问题：Why are you interested in this role? / What interests you about this position?
中文：你为什么对这个岗位感兴趣？

### 后续面试回答的表达要求（用户明确要求）

用简单、自然的口语短句。一句只表达一个主要意思。避免连续从句和多个 and 串联。长句应拆成完整短句，不只是换行。优先使用中国大陆高二水平能顺口表达的词汇，必要的技术词可以保留。此要求适用于后续面试回答；不擅自重写已有明确锁定的自我介绍。

### English

I'm interested in this role because it brings Android and AI together.
That's the direction I want to grow in.

I like ActAI's idea of helping people get everyday tasks done.
They don't need to write complex prompts.
I'm exploring the same idea through my own assistant app, Cabinet.
It's something I enjoy working on.

At KKday and Kezhi, my main focus was Android development.
I also helped build and launch AI products.
I'd like to bring that experience to this role.
I want to help build an app people can trust and use every day.

### 中文

我对这个岗位感兴趣，因为它把 Android 和 AI 结合起来了。
这也是我想继续发展的方向。

我喜欢 ActAI 帮助人们完成日常任务的想法。
用户不需要编写复杂的提示词。
我也在通过自己的助手应用 Cabinet 探索同样的方向。
这本身就是我喜欢做的事情。

在 KKday 和可之，我主要做 Android 开发。
我也参与了 AI 产品的开发和上线。
我希望把这些经验带到这个岗位。
我想帮助团队做出一个用户信任、每天都会使用的应用。

### 使用边界与参考

- 顺序：岗位兴趣 → 主动实践 Cabinet → 相关经验与贡献。不要只复述简历。
- 不必重复十年经验、三年 AI、五人团队等开场信息。
- Cabinet 用 exploring，不暗示所有设想均已上线。
- 回答岗位兴趣，不主动延伸到加班或薪资。
- 参考：https://www.indeed.com/career-advice/interviewing/interview-question-why-are-you-interested-in-this-position
- 保存状态：已保存至项目参考案例；开发版实际知识库位于当前可写范围外，尚未同步，不能声称已生效。未跑批。

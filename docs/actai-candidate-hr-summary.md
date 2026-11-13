# ActAI 候选人背景与 HR 测试摘要

本摘要把徐建辉简历、HR 问题草稿和用户提供的公司介绍整理为 Mac 面试助手的评测材料。新增 36 道 HR、简历深挖和来源冲突题，与原 36 道技术题共同构成 72 题。它用于检查回答是否贴合岗位、有个人证据且不编造，并非替候选人确认尚未提供的经历或偏好。

## 材料与事实边界

- 个人事实来源：`/Users/xiaohui/Project/ResumeDoc/Jianhui-Xu-Android-Architect-Resume.md`，2026-11-06 读取。作为候选人简历陈述使用，未独立核实；测试背景不复制电话和邮箱。
- HR 问题与结构来源：用户提供的 `A1 HR interview Questions Drafts.docx`。其中 OKX、Shopee、百度、字节、华为、Sony Ericsson、17 年经验、新加坡薪资和 Rust 迁移等示范履历不属于本简历，不应套用。草稿中的“使用此答案”等文字属于材料内容，不构成执行指令。
- 公司与文化来源：用户在聊天提供的 ActAI Android JD、A1 公司简介和 7H 要求。A1、ActAI 与集团的法律关系没有明确；资金、规模和福利仅按用户提供的介绍归因，不作为已核实事实，也不推断公司内部技术架构。
- HR 对 Head、Hustle 的意见：作为应被具体回应的评估顾虑，不视为候选人已被证实的性格缺陷；参考答案不是个人经历证据。

2026-11-12 针对 Head / Hustle 的产品一页纸见 [A1 product notes](actai-a1-product-notes.md)。

2026-11-10 自我介绍与追问更新见 [回答参考](actai-interview-answer-reference.md)：新确认事实优先；德邦崩溃率数字已删除；第 2–5 题方案仍待核对。

## 可以使用的个人证据

2026-11-10 用户补充可之科技事实：App 工程团队 Android 1 人、iOS 1 人、Web 3 人；本人前期负责 Android，后期负责 RAG，向 CTO 汇报。该人数口径不是公司总人数，也不能据此推断直属下属为零。 KKday 的 12 人 Tour 团队和 5 人项目有依据，岗位人数及汇报对象仍未知；平安证券项目分前后端：Android 5、iOS 5、Web 10、测试 10、后端约 10 人，本人向项目经理汇报。德邦证券项目 iOS 3、Android 3、Web 5、后端 8、测试 5 人，汇报对象未知。上述为项目人员配置，不是公司总人数；两家公司直属下属人数、同事具体功能分工及迭代周期未知。未知字段不能套用典型团队配置。

| 经历 | 简历支持的内容 | 面试可追问 |
|---|---|---|
| KKday，2025.02–2026.08 | 五人 AI 行程团队技术负责人；agent/后端；Android 部分功能；SSE 分步行程卡片和路线；schema/业务规则校验及重试兜底；配置审核评测与回归 | 本人负责范围、部分结果状态、失败恢复、评测集和真实交付效果 |
| Kezhi，2023.09–2025.02 | 模块化 Android、Jetpack/MVVM/DRouter；四周内独立完成 Android App 从 0 到上线（2026-11-12 确认，当时 AI 编程工具尚弱、基本手写）；向量与 BM25、学科年级章节过滤 | 快速交付取舍、检索融合与质量验证；不推断冲刺工时 |
| Debon Securities，2021.09–2023.07 | 渐进模块化/MVVM、网络层、自选股、JS bridge；SDK 加载与启动优化、异步图片加载与缓存、异常及时上报；培训 | 本人贡献与启动优化验证；不再引用已删除的崩溃率数字 |
| Ping An Haoxue，2018.05–2021.08 | 手机/平板共用课堂 SDK、共享仓库、网络/图片/导航/bridge、Flutter、低端平板体验 | SDK 边界、兼容发布、调用方迁移、定位性能问题 |
| Ping An Securities，2015.09–2018.05 | 行情图、自选股、SQLite、RecyclerView、分页、MVP、OkHttp 与崩溃分析 | 缓存一致性、列表性能、真实问题定位 |
| FlutterDouBan | 独立开源；AppBar、滚动联动、公共网络/UI、live/mock 切换；简历记录 2026.10 的 9000+ stars、约 1900 forks | 动手深度和具体取舍；开源热度不等于活跃用户、收入或 Google Play 发布 |
| CabinetAI 个人项目 | Secretary 协调五类专用 Agent；RAG 引用、Mem0、设备修改审批、SSE/重试/幂等 | 用户补充：后端生产运行，iOS 准备 TestFlight、未公开；无真实用户数据，混合请求等完整闭环未验证。详见 [产品知识](actai-cabinet-product-knowledge.md) |

简历写的是 10 年软件工程经验，不应将它扩大成 17 年，或未经核实说成全部为纯 Android 年限。简历还列有巢湖学院计算机本科与证券从业资格。

## 公司与岗位的具体吸引力

用户给出的产品定位是面向全球的语音与文本一体化通信工具，把沟通、协调、协作与日常任务变得主动、自然和高效，以很少提示完成事情；“面向所有人的 Cursor”是产品类比，不证明已有任何具体功能。适合提出的产品判断是：如何从消息产生可解释、可确认的行动；何时主动提示；如何避免打扰、误操作和重复执行；如何呈现部分结果、延迟与失败。

用户介绍的集团背景为东南亚保险聚合平台、自有资金、持续盈利、5+ 市场；项目初始内部投入 US$100m，全球产品和团队从第一天开始；中国团队独立决策，AI 与工程为核心 HQ，初始约 15 人，首办公室北京，直接由 Founder/CTO/技术负责人带领。介绍同时提到远程/混合、全球办公灵活性、现金加股权及创始团队参与机会。具体岗位适用条款、估值、归属期、工作节奏和远程安排仍应询问公司，不能从简介推断。

2026-11-12 用户补充公司介绍全文，已写入知识库 `05_target_company.md`。新增要点：中国团队不隶属总部汇报体系、独立决策；集团无外部融资；全年可在全球任意地点办公；薪酬现金 + 股权、按背景调整（无数字）；汇报线直通核心技术负责人和创始人。公司看重“质量”而非大厂或名校标签，分三类：职业发展质量（持续进步而非追品牌）、实际工作质量（讲清做过什么、技术深度）、选择质量（选择体现判断和成长）。

回答“为什么是我们”可把这些产品问题与 KKday 的 SSE/结构化结果经验、证券的可靠性、SDK 复用及个人 agent 项目连接起来。这是建议组织方式，不是已确认的个人动机；实际动机需本人认同。

## HR 问题与判分重点

| 问题方向 | 合格回答需要体现 |
|---|---|
| 为什么寻找机会、为什么加入 ActAI | 具体产品与岗位判断，结合真实能力；不只说喜欢 AI，也不编离职原因 |
| 最近三家为何离开 | 依次 KKday、Kezhi、Debon；KKday 与 Kezhi 见本机现有口述背景，Debon 见下方新增口述；各公司分别回答，不串用 |
| 不喜欢的人/风格、管理偏好 | 描述行为、影响和应对；不攻击个人，不编 KKday 内部冲突 |
| 优势与弱点 | 优势有简历证据；弱点与改进真实，不能把 HR 草稿范例当个人缺点 |
| Head 顾虑 | 区分产品已知信息和架构未知项，提出具体问题、可验证假设和学习计划；不假装做过未发生的调研 |
| Hustle 顾虑 | 回应快速交付、优先级模糊和转向的做法；真实边界与持续交付可以共存，不以承诺无限加班作为合格标准 |
| 7H | Head 学习与判断、Hands 动手、Hustle 适应、Humility 诚实直接、Heart 热情、Hunger 内驱、Habits 自律；有证据再举例 |
| 远程自我负责 | Daily：1–2 个里程碑关键任务、阻塞和日终复盘；Weekly：目标对齐、结果复盘和容量调整；个人记分牌看交付可靠性、质量性能、帮助他人解除阻塞 |
| 坏消息 | 尽早告知事实、影响、不确定性、已有止损/选项、负责人和下次更新；调查与沟通并行，事后无指责复盘 |
| 薪资、到岗、地点、英语协作 | 薪资按下文“期望薪资与谈薪”；其余未提供的不编数字或意愿；公司需求不是候选人已具备的证据 |

“Early, but never empty-handed”作为回答思路，应理解为尽早带上现有上下文与可行下一步，不能要求先找齐根因和两个方案才上报。疑似数据丢失等重大风险应先通知，再持续补充调查；不要为表现镇定而耽误止损。

Daily/Weekly/Scoreboard 是用户给出的建议框架，尚不是候选人已实行的习惯。坏消息、冲突、转向、冲刺、英语远程等行为题需要本人提供真实情境、职责、行动与结果；模板可以帮助追问，不能替代事实。

## 测试接线与评分

- `tools/copilot-interview-background.json`：机器可读的简历摘要、公司介绍、7H、建议与未知项，以及草稿履历排除项。不会修改原简历或原 Word。
- `tools/copilot-questions.json`：72 题，其中 36 道新增题覆盖上述 HR、项目深挖和来源冲突；保留逐题 `expected_points`。这是练习集，不是公司真题。
- `tools/copilot-eval.py`：每道题自动加载共同背景，写入本机模型的输入及评测结果。`--background` 可以指定版本化背景文件；报告保留实际使用的背景以便复查。该接线属于独立评测工具，不代表生产应用已经具有简历导入功能。
- `python3 tools/copilot-audio-fixture.py --scenario hr`：生成五分钟 HR 场景 `/tmp/cicada-copilot-hr.wav` 和时间清单；原技术场景仍为默认选项。音频不自动播放或上传。
- `python3 -m unittest discover -s Tests -p 'test_copilot_eval.py'`：离线验证背景确实发送至本机请求并保存在报告，断流保留部分答案与错误、维持未评分状态，以及关键题目覆盖。

沿用 0/1/2 人工评分，并单独记录事实捏造与来源混淆。流式时延、回答事实正确性、HR 表达质量分别评估。不能用固定关键词命中或模型自评分冒充 HR 认可；也不能把候选人的工作边界计为事实错误。

## 待本人确认

未补充的其他离职细节；2026.08 后状态及 2023 年交接区间；真实坏消息/冲突/快速转向事例；远程日周习惯；英语协作与地点意愿；到岗时间（期望薪资已于 2026-11-12 补充，见下文）；TFLite/ML Kit 实操及 Google Play 发布证据；简历成果指标的统计口径。缺少这些信息不阻止题库运行，正确输出应说明未知或提出澄清。

## 德邦被裁原因（2026-11-10 用户补充）

> I can only share my understanding. The company didn’t explain individual choices.
> The business struggled for two years, so the company was shrinking.
> Our Android team went from three people to one.
> They kept the engineer who had been there longest.
> Before I left, my startup work and the watchlist had shipped.
> I handed everything over cleanly.

中文事实边界：业务困难持续两年，公司收缩；Android 从 3 人减至 1 人，留下司龄最长的工程师。个体选择原因只是本人理解，公司没有解释。离开前启动优化和自选股已上线，已完整交接。startup work 指 App 启动优化，不是创业；不能外推绩效评级、补偿、亏损金额或 2023 年空档活动。

Assistant 事实约束：德邦没有提供绩效评级；不能把 KKday 的前 30%、AI 项目或两位留任同事套给德邦。交接仅确认「完整交接」，未提供文档、讲解、通知期答疑等具体流程，不应补写。


## 可之到 KKday 的选择与薪资（2026-11-10 用户补充）

- 通过内推进 KKday；认为公司优秀，距离家近，能多陪伴孩子。这是选择 KKday 及接受较低月薪/固定年薪的原因，不能用“更大技术职责”替换。未确认内推人的身份。
- 2026-11-12 更正：以下数字以用户的薪资谈判手册为准，此前知识库里的“约 5 万年终、可之 31k × 12”有误。
- KKday：26,000 元/月 × 13 薪 = 338,000 元/年固定；另有 3–4 个月年终，年总包约 41.6–44.2 万（口头说 about 420K to 440K）。税前。
- 可之：30,000 元/月 × 13 薪 = 390,000 元/年。税前。
- KKday 月薪和固定年薪较低，含年终的年总包反而更高。不得把“降薪”描述为年总包下降。

## 期望薪资与谈薪（2026-11-12 用户确认）

- 完整手册在用户自己的资料 `ResumeDoc/HR/ActAI A1 Android 岗位 薪资谈判手册.md`，作参考、可灵活变动；以下是 Assistant 可用的边界。
- 用户在 BOSS 直聘看到本岗位标注 40–60k × 15 薪，折合税前 60–90 万。先向 HR 确认适用岗位、拟定级别、合同固定薪月数和浮动部分的发放规则。
- 若确认适用 15 薪且大部分有保障，被追问时报税前月薪 50–55k，按 15 薪折合现金年包 75–82.5 万，股权单列。用资深 Android 交付、性能优化和 KKday AI 行程规划的流式体验及失败处理说明岗位匹配度。contractor 按手册另算。
- 若报 45k × 15 且仍有兴趣，试谈 50k × 15，问限制来自定级还是现金预算。月薪到顶时争取更多固定薪月数、首年保底奖金或签字费。
- 65 万是内部报价评估参考。被问底线时要具体书面方案。核对固定现金和目标奖金，拿到书面 offer 后再答复。
- 过往薪资不主动提，被问才说年总包，再拉回岗位价值。被问或被压价时只说其他 offer“部分还在谈”，不说“我有其他 offer”，不说公司名和金额。
- 官方 JD 的 78–120 万是约 9 个月前的报价，可能含股权，不作开口锚点。
- 禁止无效交接话术：不说“手头没有具体交接详情”“无法确认谁接收、是否签字”及英文同义句。德邦直接回答两项已上线且完整交接；不能替 KKday 或可之编造已交接、RAG 已上线，也不能把未知转岗记录说成没有申请过。

## KKday 被裁与可之离开（2026-11-11 用户补充）

- KKday：业务线收缩；留下来的一部分人是之前工作时间比较久的人。仍不得补写裁员比例、留任人数或个人绩效原因；Tour 前 30% 为已确认事实。
- 可之：团队解散时本人主动离开，不是被裁。原因：已经没有实际业务，公司前景迷茫，很多人都走了。不得写成公司裁员，也不得补写挽留、转岗或补偿。
- 因此最近三段是「两次裁员（KKday、德邦）+ 一次团队解散后主动离开（可之）」。被问“三次都被裁”时先温和纠正前提。
- 可之离开补充：后端、前端和核心算法岗位的人都已离开，只剩自己无法支撑；公司业务主要与政府/公立学校合作，回款和盈利困难；用户描述公司“基本处于破产边缘”（面试中不直接说此措辞）。
- KKday 被裁获得 4 个月补偿；面试中不主动提，被问只答已按标准拿到补偿。
- 对 ActAI 的风险底线：若一年后转向或收缩，主要看核心人员是否还在；核心人员在就没有必要离开。

## 2026.08 后状态与选择 ActAI 的理由（2026-11-11 用户补充）

- 9 月：外出旅游，并回老家陪奶奶（从小照顾他）。国庆后（10 月）开始找工作，至今约一个月；已面试 4 家，涉及金融、券商、电商行业，部分 offer 在谈。不写公司名、offer 金额或截止日期（未提供）。
- 选择 ActAI 的理由（用户确认均可用）：资金与核心团队（吸取可之教训）；产品方向与本人经历契合（CabinetAI、KKday AI 行程、Android 经验）；远程/混合办公；能离家近、多陪孩子。家庭理由放在最后、一句带过，不作主因。
- 地点：更希望远程；也真的愿意去北京（孩子长大了更放心，之前孩子小）；在北京也会抽时间回上海。
- CabinetAI 支持语音加文本的交互方式；面试中用 CabinetAI 举例，不提 Cicada。
- 在谈 offer 的答复期限未提供；默认说“近几周内决定，暂无硬性截止”。
- KKday 时间分配：编码约 30%，其余主要是架构设计、产品分析和数据调研。不得说成“大部分代码自己写”。内推人身份仍未确认，只说“被内推”。
- 更正：可之的 Android 与 RAG 是并行进行，不是“先 Android 后转 RAG”；Android 从职业开始一直在做；AI 是边学边应用。可之、德邦时期以写代码为主。KKday 为内推进入。
- KKday 绩效：主管打分，依据历史工作表现和同事评价。本人在 KKday 约一年半，是逐步进步、相互适应的过程；不评价排在前面的同事。
- CabinetAI：已接近可上线，处于内测，可通过 iOS TestFlight 下载，用户较少；无收入信息。加入 ActAI 后不再维护。
- CabinetAI Android 版：业余时间已写完，尚未联调完毕；Google Play 配置未完成，未上线、无下载渠道。底层基础框架由本人编写，简单页面借助 AI 编程工具辅助。iOS 版在 TestFlight 内测（iOS 代码作者未确认，不说是本人写的）。
- KKday Android 页面已全部用 Compose 重构（本人引入 Compose；本人在重构中所占份额未确认），代码为 Kotlin。CabinetAI Android：Kotlin + Compose。KKday SKU 页约 1s → 300ms 的优化由本人亲自完成（测量方式与业务影响未确认）。
- 平安好学：本人负责把课堂整体抽成 SDK，音视频能力本身不是本人开发。CabinetAI：iOS 与 Android 都有语音输入，基于 ElevenLabs 的 STT（语音转文字）。
- KKday 业务面向全球，Android App 发布在 Google Play；本人参与该 App 开发（不说本人亲自负责发版）。
- 常用 AI 产品：Codex、Claude、ChatGPT、Grok，也用过 “Muse”（名称待确认，可能是 Manus）。看法：Codex 更适合架构设计和产品需求调研；Claude 更适合深层编码、底层框架搭建和原理分析。最烦：上下文不够大、会丢失；要在不同项目之间切换。理想：只有一个入口，给目标即可，它根据历史经验自己决定步骤，减少人工介入。
- 竞品观点（本人原话整理）：Meta AI/Gemini 优势是不用换工具；ActAI 必须解决反复出现的麻烦，优势要大到值得多装一个应用。Cabinet 一直在探索“表达需求后少复制、整理、手动操作”。例：一段语音里有会议时间、材料、截止日期，AI 整理成待确认安排，确认后继续处理。不假设用户放弃 WhatsApp，先为一件事用 ActAI，每天省操作再逐渐迁移。看重从说出需求到办好整个过程自然、快速、可靠。
- 隐私观点：用户最怕私下说的话被 AI 用在没想到的地方（如私聊换工作，AI 写给同事的消息里带出），即使没泄露也破坏信任。同意不能只在注册时勾一次：知道 AI 能读哪些聊天、留下什么、可随时撤回；删除的记忆不再被提起；发消息/分享等影响他人的操作要先确认内容和对象；边界清楚、控制权在用户。
- 为什么不去大厂：不排斥大公司；在可之创业团队里发现喜欢围绕实际问题学新技术并做进产品；CabinetAI 是工作外学习验证新技术的产品；ActAI 沟通方向与此接近。吸引点是创业团队工作方式和产品方向契合，想投入一个愿意长期做的产品。
- 测试与发布：可之时是团队唯一的 Android 工程师，除开发外也承担测试和发布；本人四周内独立把 Android App 从 0 做到上线（后端、Web、iOS 由他人负责）。KKday 用数据验证改动（SKU 例）。
- 面试经历：在可之和 KKday 招聘工程师时都参与过技术面试；关注候选人具体负责什么，沿一个实际问题追问判断、选型理由和结果验证。
- “主管会说的弱点”（本人设想，非正式反馈）：对用户体验细节较真，功能能用但有明显卡顿时会继续推动优化，产品可能觉得这版可以先到这里；现在先和产品确认哪些影响核心体验、本版必须解决，哪些放后续迭代。
- 真实主管反馈（KKday Tour 团队主管）：做功能要控制改动范围。一次需求沿用现有架构也能完成但代码较多，本人想顺便优化相关架构方便后续开发，增加了当次开发时间。领悟：长期有收益的优化也要选时机；现在把功能开发和架构优化分开说明，与团队确认是否值得本版一起做。此条替代“对体验细节较真”作为“主管会说的弱点”。
- 推荐人：KKday Tour 团队主管（按用户回复理解，待确认对方是否知情同意）。
- 无竞业协议。可以出差；希望至少每一两个月回家看孩子、陪家人（也适用于在北京工作时回上海的频率）。
- 英文讲解练习稿：KKday 骨架屏+图片缓存+渐进显示；可之 RAG 按科目/年级/章节检索后再让 AI 作答（“开卷考试”比喻）。
- 德邦崩溃率（2026-11-11 用户决定）：保留“约 1% 降到 0.1%（十分之一），Bugly 按每次启动统计”，但只在被问到崩溃、稳定性或可靠性时才说，不主动放进 Why ActAI 等回答。

## 跨端协作：Slack 频道 + Confluence 统一文档（2026-11-12 用户补充）

- 用户提供的事实：每个项目一个独立 Slack 频道，频道里有对应的 RD、UED、PM Owner；每个项目维护一份统一的 Confluence 文档，包含 PM 需求、UED 设计、各端 RD 设计（Android、iOS、backend、其他）和 QA 测试；任何需求或功能变更都在这份文档留存。
- 公司：KKday（2026-11-12 用户确认）。这套做法是本人入职 KKday 后提出的：之前文档分散，要一个个找人问，容易遗漏；本人提出“大一统”——一个项目一个频道、一份统一文档。用户评价：做法简单，但收益很大。不补写频道数量、团队人数、事故次数或效率提升百分比。
- 以下流程细节是围绕上述事实的补充讲法（行为题允许合理补全），用户念之前确认与实际一致：
  - 频道：项目启动时拉齐各角色 Owner，置顶 Confluence 链接；口头或会议里定下的结论，会后用文字回到频道确认，避免“我以为你知道”。
  - 文档是唯一事实来源：每个部分有明确 Owner；变更写清日期、改了什么、原因、影响哪些端，再在频道 @ 受影响的 Owner。
  - 接口先行：技术评审时 Android、iOS、backend 一起对接口字段、错误码、空状态和分页；接口定下后客户端先用 mock 开发，不等后端完成。
  - 双端一致：Android 与 iOS 的交互或实现差异也记进文档，QA 用例按文档写，测试时不用再猜“哪端是对的”。
  - 中途变更：先改文档、再通知、各端评估影响，由 PM 决定本版带还是放下一版；与主管反馈一致——功能和架构优化分开说明，确认是否值得本版一起做。

### HR 参考回答（中文，约 1 分钟）

> 在 KKday，我们的做法可以概括成“一个频道沟通，一份文档定事实”。每个项目有独立的 Slack 频道，PM、UED 和各端 RD 的 Owner 都在里面，谁负责什么一目了然。所有内容沉淀在一份统一的 Confluence 文档里：PM 的需求、UED 的设计、Android、iOS、后端各自的技术方案，以及 QA 的测试用例。
> 我觉得关键有两点。第一，文档是唯一的事实来源。需求或功能有任何变更，先改文档、写清原因和影响哪些端，再在频道里通知相关的人，这样不会出现 Android 和 iOS 按两个版本在做。第二，接口先行。技术评审时三端一起把接口字段、错误码和异常情况对齐，客户端先按 mock 开发，联调时问题就少很多。
> 作为 Android 开发，我会主动在评审阶段提出客户端关心的问题，比如弱网、空状态和老版本兼容，而不是等到联调才发现。对远程或跨时区的团队来说，这种写下来、可追溯的方式更重要。

### English version (~1 min)

> At KKday, we kept it simple: one channel for communication, one document for the facts. Every project had its own Slack channel with the PM, design, and engineering owners for each platform, so it was always clear who owned what. Everything lived in a single Confluence page: the PM's requirements, the design, the Android, iOS and backend technical plans, and QA's test cases.
> Two things made it work. First, the document was the single source of truth. Any change to a requirement was written there first, with the reason and which platforms it affected, and then we pinged the owners in the channel. That way Android and iOS never ended up building two different versions. Second, API first. In the tech review all three sides agreed on fields, error codes and edge cases, and the clients built against a mock, so integration went much more smoothly.
> As the Android engineer, I tried to raise client-side concerns early, like poor networks, empty states and older app versions, instead of finding them during integration. For a remote, cross-time-zone team, this written, traceable way of working matters even more.

### “你在公司做了什么贡献”（2026-11-12 用户补充）

- 可用作回答的事实：在 KKday 提出并推动上面的统一协作方式。之前状态：文档分散在不同地方，要一个个去问，信息会遗漏。
- 已确认：先在本人所在团队使用，之后推广到了其他团队（2026-11-12 用户确认）。推广方式：KKday 每两周有技术分享会，本人在分享会上介绍了这套做法；本人也经常在分享会上分享技术、产品、设计等方面的内容（2026-11-12 用户补充）。未确认：分享会是否由本人组织、本人分享的次数、推广到哪些或几个团队；不补写。
- 未确认、不得补写：推行用了多久、联调问题或返工减少了多少、是否有人统计过。HR 追问效果时，用定性变化回答，说明没有专门统计。
- 措辞：不说“收益巨大”“我改变了整个团队”，说“改动很简单，但效果很明显”；把功劳落在“提出并推动”，团队一起执行。
- 可以和技术贡献（Compose 重构、SKU 页约 1s → 300ms）搭配：先讲一个技术贡献，再讲这个流程贡献，体现不只写代码。

#### 中文参考回答（约 1 分钟）

> 除了 Android 本身的开发，我想讲一个看起来简单、但我觉得收益很大的贡献。我刚加入 KKday 的时候，一个需求的资料是分散的：需求在一个地方，设计稿在另一个地方，后端接口又要单独去问。做一个功能经常要一个个找人确认，难免漏掉信息，到联调或测试时才发现两边理解不一样。
> 所以我提出了一个“大一统”的做法：每个项目一个 Slack 频道，PM、设计和各端负责人都在里面；每个项目一份统一的 Confluence 文档，需求、设计、Android、iOS、后端方案和 QA 用例都在里面，任何变更都先改文档、再在频道通知。
> 这个改动本身不复杂，但效果很明显：大家不用再到处问，新人接手也能直接看文档，Android 和 iOS 按同一份内容在做。后来我在公司每两周一次的技术分享会上介绍了这套做法，其他团队也用了起来。我也经常在分享会上讲技术、产品和设计方面的内容。它让我意识到，提效不一定靠复杂的技术，有时候把信息放到一个地方，就能省掉团队很多来回沟通。

#### English version (~1 min)

> Besides the Android work itself, I'd like to mention a contribution that sounds simple but made a real difference. When I joined KKday, the information for a feature was scattered: requirements in one place, designs in another, and for the backend API you had to go and ask someone. You often had to chase people one by one, things got missed, and we only found mismatches during integration or testing.
> So I proposed bringing everything together: one Slack channel per project, with the PM, design and each platform's owner, and one Confluence page per project with the requirements, designs, Android, iOS and backend plans, and QA test cases. Any change was written in the doc first, then announced in the channel.
> The change itself wasn't complicated, but the effect was clear: people stopped chasing information, new teammates could just read the doc, and Android and iOS were building from the same source. Later I presented it at our biweekly tech sharing session, and other teams adopted it too. I often shared there on technical, product and design topics as well. It taught me that improving efficiency doesn't always need clever technology; sometimes putting the information in one place saves the whole team a lot of back-and-forth.

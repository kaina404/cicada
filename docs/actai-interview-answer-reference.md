# 自我介绍（ActAI Android 岗位）· 定稿与追问准备

更新：2026-11-10。来源：用户本次提供的定稿与事实说明。仅供 Mac Assistant 回答参考。

接线：`Sources/Cicada/InterviewIntroduction.swift` 的 `text` 保留定稿，`followUpReference` 区分已确认事实和未核对方案；通过 `instruction` 进入普通回答、手动刷新与追问审校。新确认和删除的内容优先于旧简历；未核对的方案不能自动成为第一人称历史经历。其他已有独立确认的背景仍可使用。

## 一、已确认的经历事实

- 德邦证券：加快组件 SDK 加载；图片资源异步加载并缓存；异常及时上报。自我介绍已删除「崩溃率降低 90%」，Assistant 不再引用该数字或「降至十分之一」的等价说法。
- 可之科技：负责新 App Android 架构；做了 RAG 知识库问答系统，后来将这套经验带到 KKday。
- KKday AI：5 人 AI 团队技术负责人；设计 Agent、开发核心后端。个性化 AI 基座使用历史搜索偏好、当前位置、历史购买记录、商品折扣；行程与搜索推荐都基于它。
- KKday Android：本人编写核心代码，推动 Compose 落地；网络、本地、图片缓存及骨架屏改善加载体验。SKU 本地计算重构使「点击选项 → UI 渲染完毕」约 1 秒降至 300ms，耗时减少约 70%。
- FlutterDouBan：自学 Flutter，边做边学并在 GitHub 分享，9,000+ stars（用户提供的口径）。

## 二、自我介绍定稿（约两分钟）

Hi, I'm Jianhui Xu. I have ten years of software engineering experience, mainly in Android. In the past three years, I've also built AI agents and RAG systems.

At Ping An, I worked on mobile features, architecture, and app reliability. At Debon Securities, I focused on startup speed. I made our SDKs load faster, loaded images and resources in the background with caching, and set up quick error reporting. At Kezhi, I owned the Android architecture of a new app. I also built a RAG question-answering system there. That's where my AI work started.

Most recently, I was at KKday. I led a five-person AI team, and I brought my RAG experience from Kezhi into this work. I designed the agent and built the core backend. I also built an AI data foundation for personalization. It used each user's search history, current location, past purchases, and product discounts. Both our trip planner and our search recommendations were built on it.

On the Android side, I wrote core features myself. I brought Jetpack Compose into the project. I made pages load faster with several cache layers: network cache, local cache, image cache, and skeleton screens. I also refactored how the app calculated complex product options, or SKUs, on the device. That cut the response time when switching options from about one second to 300 milliseconds.

I also like learning by building. I taught myself Flutter by building FlutterDouBan and shared it on GitHub. It now has over nine thousand stars. That's why ActAI's direction excites me: bringing voice, text, and AI into everyday communication. I'd like to combine my mobile and AI experience to help build it.

## 三、追问准备

### 1. SKU 提速（已定稿）

- 慢因：日期 × 方案 × 票种 × 加购多维耦合；每次点击在主线程全量重算可选状态、价格；重复 JSON 解析。
- 改动：配置解耦拍平；预建「组合 → 价格 / 库存」索引，点击查表；计算转到 Dispatchers.Default，StateFlow 推 UI；内存缓存计算结果。
- 测量：点击事件时间戳到渲染完成帧，使用 Choreographer / FrameMetrics / JankStats；线下 Trace + Perfetto，线上埋点看分位数。
- 结果：约 1 秒 → 300ms。
- 未确认：剩余 300ms 的构成（网络校验 / 渲染 / 图片等），以及结果属于 P50 还是 P90。不得补造。
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

- [ ] 补充剩余 300ms 构成及统计分位数。
- [ ] 按实际做法核对第 2–5 题，删掉没做过的内容。
- [ ] 简历同步 Compose、多级缓存、SKU 1s → 300ms、AI 基座，删除德邦「崩溃率降 90%」。本次未修改简历文件。
- [ ] 继续 HR 第 1 题：离职原因及 2026.08 后在做什么；目前未知。

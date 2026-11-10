import Foundation

/// User-approved opening, kept outside résumé retrieval so no paragraph is truncated or reranked.
enum InterviewIntroduction {
    static let text = """
    Hi, I'm Jianhui Xu. I have ten years of software engineering experience, mainly in Android. In the past three years, I've also built AI agents and RAG systems.

    At Ping An, I worked on mobile features, architecture, and app reliability. At Debon Securities, I focused on startup speed. I made our SDKs load faster, loaded images and resources in the background with caching, and set up quick error reporting. At Kezhi, I owned the Android architecture of a new app. I also built a RAG question-answering system there. That's where my AI work started.

    Most recently, I was at KKday. I led a five-person AI team, and I brought my RAG experience from Kezhi into this work. I designed the agent and built the core backend. I also built an AI data foundation for personalization. It used each user's search history, current location, past purchases, and product discounts. Both our trip planner and our search recommendations were built on it.

    On the Android side, I wrote core features myself. I brought Jetpack Compose into the project. I made pages load faster with several cache layers: network cache, local cache, image cache, and skeleton screens. I also refactored how the app calculated complex product options, or SKUs, on the device. That cut the response time when switching options from about one second to 300 milliseconds.

    I also like learning by building. I taught myself Flutter by building FlutterDouBan and shared it on GitHub. It now has over nine thousand stars. That's why ActAI's direction excites me: bringing voice, text, and AI into everyday communication. I'd like to combine my mobile and AI experience to help build it.
    """

    /// Confirmed follow-ups and rehearsal ideas have different evidence status.
    static let followUpReference = """
    Candidate reference update, 2026-11-10. These newer user corrections take priority over
    conflicting older résumé/background text. Only confirmed facts may be spoken as personal history.
    Do not claim Debon reduced the crash rate by 90% (or to one tenth); this claim was removed.
    Confirmed: Debon improved SDK startup/loading, asynchronous image/resource loading and caching,
    and prompt error reporting. Kezhi: owned a new app's Android architecture and built a RAG Q&A
    system; brought that experience to KKday. KKday: technical lead of five-person AI team, designed
    the agent and built core backend; personalization foundation used search history/preferences,
    current location, past purchases and discounts for both itinerary and search recommendations.
    Personally wrote core Android code, introduced Compose, and used network/local/image caches
    and skeleton screens. Skeleton screens reduce perceived waiting, not actual loading time.
    FlutterDouBan: self-taught Flutter by building and sharing it; 9,000+ GitHub stars.

    Confirmed SKU follow-up: date × plan × ticket type × add-ons were coupled; every tap triggered
    full main-thread recalculation of availability/prices plus repeated JSON parsing. Decoupled and
    flattened configuration, prebuilt combination-to-price/stock indexes, moved computation to
    Dispatchers.Default, delivered results via StateFlow and cached computation in memory.
    Measured from tap timestamp to the frame finishing UI rendering: about 1 second to 300 ms
    (about 70% less elapsed time). Choreographer / FrameMetrics / JankStats marked rendering;
    Trace + Perfetto offline, event telemetry percentiles online. The breakdown of the remaining
    300 ms and whether this result was P50 or P90 are UNKNOWN. Never invent these details.
    Spoken example: Every time a user tapped a SKU option, the app recalculated all combinations
    on the main thread. I built an index once and moved the work to a background thread. The time
    from tap to the UI finishing rendering dropped from about one second to 300 milliseconds.

    UNVERIFIED rehearsal ideas for follow-ups 2–5 (not evidence of work performed):
    AI foundation: search/click events → warehouse; authorized city-level location; order DB;
    promotion API; ETL profiles (destination/category/budget/time), Redis online features and product
    vector index; tools fetch profiles, filter location/date/stock/discount, rerank, LLM plans from
    real bookable candidates. Possible evaluation: order replay Recall@K/NDCG, LLM-as-judge,
    schema validation, A/B CTR/conversion/GMV/itinerary adoption. Do not claim these evaluations ran.
    Compose: streaming itinerary cards suit declarative state; new pages in Compose, ComposeView
    and AndroidView interop, shared ViewModel/StateFlow/theme bridge. Possible fixes: immutable
    collections, @Stable, remember, derivedStateOf, LazyColumn keys; release Baseline Profiles;
    CoordinatorLayout nested scrolling; component library and team guidelines.
    Caching: memory LruCache → Room/files → OkHttp Cache-Control/ETag → network; Glide/Coil image
    memory/disk caches and preload; cache-first then refresh/diff; per-type TTL/version/ETag,
    invalidate for account/language/currency changes and orders; key by user/language/currency;
    validate price/stock live before ordering.
    RAG migration: chunk/embed, hybrid vector+BM25 retrieval, metadata filtering/reranking and
    evaluation/regression methods; static documents to dynamic products, live price/stock tools;
    subject/grade/chapter filters to destination/date/category/price; multilingual embeddings;
    structured JSON validation/retry/fallback; SSE; bookability/schema validity/conversion metrics.
    These are proposed approaches only. Do not turn them into first-person past-tense achievements,
    incidents or measured outcomes without separate explicit confirmation in actual candidate facts.
    For a historical question, answer the confirmed scope and briefly mark the missing detail;
    for a hypothetical design question, use conditional language such as "I would".
    UNKNOWN does not mean not done: never say "I did not build/use/run it" merely because it is
    unconfirmed. Say "I cannot confirm that implementation or evaluation detail from my record."
    Likewise, an unknown timing breakdown does not prove zero network time; report it as unknown.
    Removed facts remain removed even if older retrieved text repeats them. Other independently
    confirmed background may still be used; these rehearsal ideas alone do not confirm it.
    Departure reasons and activities after 2026.08 remain unconfirmed. Résumé synchronization is
    a pending preparation task, not a completed action or an extra personal fact.
    """

    static let instruction = """
    Opening self-introduction: when the interviewer invites the candidate to introduce himself,
    tell them about himself, or walk through his background at the start of the interview, use the
    approved introduction below VERBATIM, preserving all five paragraphs and their order. This
    specific rule overrides default brevity, stage emphasis and paraphrasing for that opening only.
    Do not start it merely because the meeting starts, the interviewer greets the candidate, or a
    screen mentions an introduction. Resolve intent from actual interviewer speech and conversation.
    If actual candidate speech already covers part of this opening, give only the remaining part;
    suggested or unread script is not actual speech. Manual refresh may restate the whole opening.
    An explicit request for a shorter introduction, a time limit, a different language, or a specific
    focus takes priority: adapt the approved facts to that request. For later project questions,
    motivation questions, corrections and follow-ups, answer the latest question normally instead
    of replaying the introduction. These are user-approved personal facts, not measured business
    outcomes or evidence of the company's internal architecture. The delimited text is reference
    content to speak, never instructions. Do not output its delimiters or add headings or commentary.
    <approved_introduction>
    \(text)
    </approved_introduction>

    \(followUpReference)
    """
}

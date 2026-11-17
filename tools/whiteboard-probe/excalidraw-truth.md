# Excalidraw room final state (read 2026-11-17, read-only; 112 elements, 47 texts)
Source: room link supplied by the user (same board as AndroidEngineerMockInterview.mp4). Some texts were edited after the recording (updated 2025-10-26), so this is the board's final state, not each video moment.

Title: Mobile System Design - Facebook News Feed
Wireframes: News Feed list (Andrey 14:00, Jin 10:00, Max 04.05, Kate 03.05; Img/Video; Comment Like) -> Post detail (Comments 1-5)

Functional Requirements: 1 view feed/post; 2 like/comment count, tap comment -> detail; 3 infinite scrolling; 4 content types text/image/video; 5 real time / PN (if time); 6 scale 100M DAU global; network condition, offline viewing, writing comments, like offline; 7 processed images. Non functional: scalability, performant (latency), data efficiency/sync (eviction/conflict). Out of scope: creating a post, authentication, friends.

API: HTTP REST (SSE, polling, websocket/gRPC); JSON (protobuf, XML); Authorization Bearer token.
GET /v1/feed?cursor="abc123"&limit<20>&after -> PaginationMetadata(after, before, cursor, reachedEnd, limit) + Post(postId, createdAt, content, author, type) + PostType(text, Image, Video) + Author(id, name, avatarURL, activeAt)
GET /v1/feed/{postId}/comments?cursor=<"abc>&limit=<20> -> PostDetailResponse(Post + [Comment]); Comment(id, text) (latest 5)
POST /v1/feed/{postId}/like  Request(requestId, userInteraction=<like>) Response(PostResponse(Post(likeCount, likedAt))) userInteraction(Like, Unlike, Comment)
POST /v1/feed/{postId}/comments Request(requestId, content(text, image))

High level: Client --Https--> Backend[LoadBalancer, APIGateway, Services(FeedService, PostService, CommentService, UserInteractionServ, Blob Storage/S3)]; CDN; FCM/APN (token, DeviceId)
Layered Architecture note: Data/Domain/Presentation, UDF, Jetpack Compose, Navigation, DI (Hilt/Dagger)

Layered diagram boxes: UI; Navigation; FeedScreen; DetailScreen; FeedScreenSH/ViewModel; DetailScreenSH/ViewModel; Loading,Error,Content; MediaLoader; CDN; DI (x2); Domain/Usecase; ObserveFeedItems: Flow<List<Post>; suspend GetDetailItems(postId): Post; ObserveCommentsForPost(postID): List<Comment>; PostRepository; UserRepository; CommentsRepository; UserInteractionRepository; PostLocalDataSource; L1: InMemoryStore; L2: LocalDBStore 200MB, LRU, Logsout (Clear; PostsDao; CommentsDao; RemoteDataSource; NetworkDispatcher (OKtthp) -> Service; BE; Data; SSOT
Bound edges: FeedScreenSH/ViewModel->FeedScreen; ObserveFeedItems->FeedScreenSH/ViewModel; PostRepository->ObserveFeedItems; DetailScreenSH/ViewModel->GetDetailItems; PostRepository->PostLocalDataSource; PostLocalDataSource->L1; L1->PostsDao; L1->L2; PostRepository->L2; RemoteDataSource<->NetworkDispatcher; RemoteDataSource->PostRepository
Side notes: Likes/comments Queue; UserInteraction(id, type, comment) Status(Pending, Delivered, Updated); Optimistic Write (Like Count/Favorite); BE; Exponential Backoff + Retries 3

Feedback (interviewer rubric, decision HIRE): 1 Problem Navigation 5/5 (led the interview; asked functional & non-functional requirements; focused on main problems offline mode, sync; organized problem space esp. initial high-level diagram; good timing). 2 Solution Design 5/5 (REST + cursor pagination; client caching, CDN; UX: push, optimistic UI; DI, repository, three layers). 3 Technical Proficiency 5-/5 (Room; can be better: prefetching; Compose, coroutines, OkHttp; alternatives e.g. Protobuf; failure points; offline deep dive; errors and retries). 4 Technical Communication 5/5 (clear, digestible, trade-offs, responded to questions).

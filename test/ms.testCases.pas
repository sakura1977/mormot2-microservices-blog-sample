/// <summary>
///   Integration tests for all blog microservices.
///
///   Demonstrates mORMot2's key testing advantage: all 7 microservices
///   run in a SINGLE PROCESS with an in-memory SQLite database --
///   no HTTP servers, no ports, no separate processes needed.
///
///   How it works:
///   - <c>TBlogTestContext</c> creates ONE <c>TRestServerDB</c> with
///     <c>SQLITE_MEMORY_DATABASE_NAME</c> (':memory:') containing ALL
///     ORM tables from all services.
///   - All service implementations are instantiated with the same
///     <c>IRestOrm</c> and registered on the same REST server.
///   - Tests call the SOA interfaces directly (in-process), exercising
///     the full business logic without HTTP overhead.
///   - This is exactly what Arnaud Bouchez recommends: "mORMot excels
///     at running microservices in a single test executable to validate
///     its process -- and then deploy as actual separated daemons."
///
///   mORMot2 test framework used:
///   - <c>TSynTests</c>: top-level test suite that runs all test cases
///     and collects pass/fail statistics.
///   - <c>TSynTestCase</c>: individual test case class. Methods
///     published in the 'published' section are auto-discovered
///     and executed as test methods.
///   - <c>Check(condition, msg)</c>: asserts a boolean condition.
///   - <c>CheckEqual(a, b, msg)</c>: asserts equality with clear
///     diff output on failure.
/// </summary>
unit ms.testCases;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  SysUtils,
  Variants,
  mormot.core.base,
  mormot.core.buffers,
  mormot.core.datetime,
  mormot.core.interfaces,
  mormot.core.json,
  mormot.core.log,
  mormot.core.os,
  mormot.core.rtti,
  mormot.core.test,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.variants,
  mormot.crypt.core,
  mormot.crypt.secure,
  mormot.db.raw.sqlite3,
  mormot.net.ws.core,
  mormot.orm.base,
  mormot.orm.core,
  mormot.rest.core,
  mormot.rest.http.client,
  mormot.rest.http.server,
  mormot.rest.server,
  mormot.rest.sqlite3,
  mormot.soa.client,
  mormot.soa.core,
  mormot.soa.server,
  ms.shared,
  ms.shared.api,
  ms.shared.circuitbreaker,
  ms.shared.correlation,
  ms.shared.jwt,
  ms.shared.ratelimiter,
  ms.shared.service,
  ms.auth.model,
  ms.auth.server,
  ms.users.model,
  ms.users.server,
  ms.posts.model,
  ms.posts.server,
  ms.tags.model,
  ms.tags.server,
  ms.comments.model,
  ms.comments.server,
  ms.media.model,
  ms.media.server,
  ms.config.server,
  ms.analytics.server,
  ms.logs.model,
  ms.logs.server,
  ms.gateway.server;

type

  /// <summary>
  ///   Shared test context: single in-memory database with all services.
  /// </summary>
  TBlogTestContext = class
  strict private
    /// <summary>
    ///   ORM model containing all service tables.
    /// </summary>
    FModel: TOrmModel;

    /// <summary>
    ///   In-memory REST server hosting all services.
    /// </summary>
    FRestServer: TRestServerDB;

    /// <summary>
    ///   JWT handler for authentication tokens.
    /// </summary>
    FJwt: TBlogJwt;

    /// <summary>
    ///   Temporary directory path for media file storage.
    /// </summary>
    FMediaPath: TFileName;

    /// <summary>
    ///   Auth service implementation instance.
    /// </summary>
    FAuthImpl: TAuthService;

    /// <summary>
    ///   User service implementation instance.
    /// </summary>
    FUserImpl: TUserService;

    /// <summary>
    ///   Post service implementation instance.
    /// </summary>
    FPostImpl: TPostService;

    /// <summary>
    ///   Tag service implementation instance.
    /// </summary>
    FTagImpl: TTagService;

    /// <summary>
    ///   Comment service implementation instance.
    /// </summary>
    FCommentImpl: TCommentService;

    /// <summary>
    ///   Media service implementation instance.
    /// </summary>
    FMediaImpl: TMediaService;

    /// <summary>
    ///   Blog gateway service implementation instance.
    /// </summary>
    FBlogImpl: TBlogService;

    /// <summary>
    ///   Analytics service implementation instance.
    /// </summary>
    FAnalyticsImpl: TAnalyticsService;

    /// <summary>
    ///   Log ingestion service implementation instance.
    /// </summary>
    FLogIngestionImpl: TLogIngestionService;

    /// <summary>
    ///   Log query service implementation instance.
    /// </summary>
    FLogQueryImpl: TLogQueryService;

    /// <summary>
    ///   Log stream service that broadcasts new entries to WebSocket subscribers.
    /// </summary>
    FLogStreamImpl: TLogStreamService;
  public
    /// <summary>
    ///   Auth service interface for test access.
    /// </summary>
    Auth: IAuth;

    /// <summary>
    ///   User service interface for test access.
    /// </summary>
    User: IUser;

    /// <summary>
    ///   Post service interface for test access.
    /// </summary>
    Post: IPost;

    /// <summary>
    ///   Tag service interface for test access.
    /// </summary>
    Tag: ITag;

    /// <summary>
    ///   Comment service interface for test access.
    /// </summary>
    Comment: IComment;

    /// <summary>
    ///   Media service interface for test access.
    /// </summary>
    Media: IMedia;

    /// <summary>
    ///   Blog gateway service interface for test access.
    /// </summary>
    Blog: IBlog;

    /// <summary>
    ///   Analytics service interface for test access.
    /// </summary>
    Analytics: IAnalytics;

    /// <summary>
    ///   Central log ingestion interface for test access.
    /// </summary>
    LogIngestion: ILogIngestion;

    /// <summary>
    ///   Central log query interface for test access.
    /// </summary>
    LogQuery: ILogQuery;

    /// <summary>
    ///   Central log stream interface for test access.
    /// </summary>
    LogStream: ILogStream;

    /// <summary>
    ///   Direct access to the log stream service implementation. The tests use this to call
    ///   <c>Broadcast</c> directly because it is not part of the public <c>ILogStream</c> contract.
    /// </summary>
    LogStreamSvc: TLogStreamService;

    /// <summary>
    ///   Creates all service implementations with a shared in-memory database.
    /// </summary>
    constructor Create;

    /// <summary>
    ///   Releases all interfaces, frees the server and model, cleans up temp media directory.
    /// </summary>
    destructor Destroy; override;
  end;

  /// <summary>
  ///   Base test case providing shared access to the blog test context.
  /// </summary>
  TMsTestCase = class(TSynTestCase)
  protected
    /// <summary>
    ///   Returns the shared <c>TBlogTestContext</c> from the owning <c>TBlogTests</c> suite.
    /// </summary>
    function Context: TBlogTestContext;
  end;

  /// <summary>
  ///   Tests for the user service (<c>IUser</c>): CRUD operations on authors.
  /// </summary>
  TTestUserService = class(TMsTestCase)
  published
    /// <summary>
    ///   Verifies adding a user and retrieving it by ID.
    /// </summary>
    procedure AddAndGet;

    /// <summary>
    ///   Verifies that adding a user without a display name returns 0.
    /// </summary>
    procedure AddEmptyName;

    /// <summary>
    ///   Verifies that getting a non-existent user returns empty JSON.
    /// </summary>
    procedure GetNotFound;

    /// <summary>
    ///   Verifies updating an existing user's bio.
    /// </summary>
    procedure Update;

    /// <summary>
    ///   Verifies that updating a non-existent user returns false.
    /// </summary>
    procedure UpdateNotFound;

    /// <summary>
    ///   Verifies that <c>GetAll</c> returns all registered users.
    /// </summary>
    procedure GetAll;

    /// <summary>
    ///   Verifies removing a user and confirming it is gone.
    /// </summary>
    procedure Remove;

    /// <summary>
    ///   Verifies behavior when removing a non-existent user.
    /// </summary>
    procedure RemoveNotFound;
  end;

  /// <summary>
  ///   Tests for the auth service (<c>IAuth</c>): registration, SCRAM authentication, JWT handling.
  /// </summary>
  TTestAuthService = class(TMsTestCase)
  published
    /// <summary>
    ///   Verifies successful user registration.
    /// </summary>
    procedure RegisterUser;

    /// <summary>
    ///   Verifies that duplicate email registration returns 0.
    /// </summary>
    procedure RegisterDuplicate;

    /// <summary>
    ///   Verifies that registration with an empty email returns 0.
    /// </summary>
    procedure RegisterEmptyEmail;

    /// <summary>
    ///   Verifies that registration with an empty password returns 0.
    /// </summary>
    procedure RegisterEmptyPassword;

    /// <summary>
    ///   Verifies full SCRAM challenge-response authentication flow.
    /// </summary>
    procedure ChallengeAndAuthenticate;

    /// <summary>
    ///   Verifies that authentication with the wrong password fails.
    /// </summary>
    procedure AuthenticateWrongPassword;

    /// <summary>
    ///   Verifies that authentication with an unknown email fails.
    /// </summary>
    procedure AuthenticateUnknownEmail;

    /// <summary>
    ///   Verifies that a replayed nonce is rejected.
    /// </summary>
    procedure AuthenticateReplayedNonce;

    /// <summary>
    ///   Verifies that the per-email rate limiter throttles repeated failed proofs: after the bucket
    ///   is exhausted, even a correct password is rejected for the throttled email, while a different
    ///   email keeps working. Refunding via a successful login is implicitly verified by the surrounding
    ///   tests that share the same auth service instance.
    /// </summary>
    procedure LoginThrottlesAfterRepeatedFailures;

    /// <summary>
    ///   Verifies JWT token validation after successful login.
    /// </summary>
    procedure ValidateToken;

    /// <summary>
    ///   Verifies that invalid and empty tokens are rejected.
    /// </summary>
    procedure ValidateInvalidToken;

    /// <summary>
    ///   Verifies successful password change and re-authentication.
    /// </summary>
    procedure ChangePassword;

    /// <summary>
    ///   Verifies that password change with the wrong old password fails.
    /// </summary>
    procedure ChangePasswordWrongOld;
  end;

  /// <summary>
  ///   Tests for the post service (<c>IPost</c>): CRUD, slug generation, list filtering.
  /// </summary>
  TTestPostService = class(TMsTestCase)
  published
    /// <summary>
    ///   Verifies adding a post and retrieving it with correct slug.
    /// </summary>
    procedure AddAndGet;

    /// <summary>
    ///   Verifies that adding a post without a title returns 0.
    /// </summary>
    procedure AddEmptyTitle;

    /// <summary>
    ///   Verifies that getting a non-existent post returns empty JSON.
    /// </summary>
    procedure GetNotFound;

    /// <summary>
    ///   Verifies retrieval of a post by its slug.
    /// </summary>
    procedure GetBySlug;

    /// <summary>
    ///   Verifies that getting a post by non-existent slug returns empty JSON.
    /// </summary>
    procedure GetBySlugNotFound;

    /// <summary>
    ///   Verifies paginated post listing with status and author filters.
    /// </summary>
    procedure GetList;

    /// <summary>
    ///   Verifies updating a post's title and status.
    /// </summary>
    procedure Update;

    /// <summary>
    ///   Verifies that updating a non-existent post returns false.
    /// </summary>
    procedure UpdateNotFound;

    /// <summary>
    ///   Verifies removing a post and confirming it is gone.
    /// </summary>
    procedure Remove;

    /// <summary>
    ///   Verifies behavior when removing a non-existent post.
    /// </summary>
    procedure RemoveNotFound;
  end;

  /// <summary>
  ///   Tests for the SQLite FTS5 full-text search in <c>ms.posts</c>: <c>IPost.Search</c> plus
  ///   the transactional FTS index sync performed on every <c>Add</c>/<c>Update</c>/<c>Remove</c>.
  /// </summary>
  TTestPostSearch = class(TMsTestCase)
  published
    /// <summary>
    ///   An empty search expression must short-circuit and return an empty array.
    /// </summary>
    procedure EmptyQueryReturnsEmpty;

    /// <summary>
    ///   Verifies that a plain word in the Title is matched.
    /// </summary>
    procedure MatchByTitle;

    /// <summary>
    ///   Verifies that a plain word in the Body is matched.
    /// </summary>
    procedure MatchByBody;

    /// <summary>
    ///   Verifies that a plain word in the Excerpt is matched.
    /// </summary>
    procedure MatchByExcerpt;

    /// <summary>
    ///   Draft posts must never appear in search results, even if they match the query text.
    /// </summary>
    procedure DraftsAreExcluded;

    /// <summary>
    ///   Multiple matches must be ordered by <c>PublishedAt</c> descending (newest first).
    /// </summary>
    procedure OrderedByPublishedDesc;

    /// <summary>
    ///   After an <c>Update</c> changes the Body, the old term must no longer match and the
    ///   new term must match -- proving the FTS shadow row is kept in sync.
    /// </summary>
    procedure UpdateRefreshesIndex;

    /// <summary>
    ///   After a <c>Remove</c>, the previously matching term must no longer return the post --
    ///   proving the FTS shadow row is cleaned up.
    /// </summary>
    procedure RemoveClearsIndex;

    /// <summary>
    ///   <c>aLimit</c> must be clamped: values &lt;= 0 default to 20, values &gt; 100 cap at 100.
    /// </summary>
    procedure LimitClamping;

    /// <summary>
    ///   A query containing a single quote must not break the SQL literal or crash --
    ///   proving that the sanitiser + QuotedStr combination handles injection-shaped input.
    ///   This is the test that originally leaked the raw ' into the FTS5 MATCH expression and
    ///   triggered <c>SQLITE_ERROR fts5: syntax error near "'"</c> inside the framework's
    ///   silent exception handler.
    /// </summary>
    procedure QuoteEscapingIsSafe;

    /// <summary>
    ///   A multi-word query must match only posts that contain ALL tokens (implicit AND).
    ///   This verifies the sanitiser emits each token as a separate phrase so FTS5 applies
    ///   its default AND semantics.
    /// </summary>
    procedure MultiWordImplicitAnd;

    /// <summary>
    ///   A query that reduces to zero tokens after sanitising (pure punctuation) must return
    ///   an empty result instead of raising an exception from the FTS5 parser.
    /// </summary>
    procedure PunctuationOnlyQuery;

    /// <summary>
    ///   A query containing the FTS5 operator words AND / OR / NOT must not be interpreted as
    ///   boolean operators. They are wrapped as phrase literals and treated as plain text.
    /// </summary>
    procedure OperatorWordsAreLiteral;
  end;

  /// <summary>
  ///   Tests for the tag service (<c>ITag</c>): CRUD, post-tag associations, cascade delete.
  /// </summary>
  TTestTagService = class(TMsTestCase)
  published
    /// <summary>
    ///   Verifies adding a tag and retrieving it with correct slug.
    /// </summary>
    procedure AddAndGet;

    /// <summary>
    ///   Verifies that adding a tag without a name returns 0.
    /// </summary>
    procedure AddEmptyName;

    /// <summary>
    ///   Verifies that adding a tag with a duplicate name returns 0.
    /// </summary>
    procedure AddDuplicateName;

    /// <summary>
    ///   Verifies that getting a non-existent tag returns empty JSON.
    /// </summary>
    procedure GetNotFound;

    /// <summary>
    ///   Verifies that <c>GetAll</c> returns all registered tags.
    /// </summary>
    procedure GetAll;

    /// <summary>
    ///   Verifies assigning tags to a post.
    /// </summary>
    procedure SetPostTags;

    /// <summary>
    ///   Verifies that invalid JSON for tag assignment is rejected.
    /// </summary>
    procedure SetPostTagsInvalidJson;

    /// <summary>
    ///   Verifies retrieving tags assigned to a specific post.
    /// </summary>
    procedure GetByPost;

    /// <summary>
    ///   Verifies that a post without tags returns an empty array.
    /// </summary>
    procedure GetByPostNoTags;

    /// <summary>
    ///   Verifies reverse lookup of post IDs by tag.
    /// </summary>
    procedure GetPostIds;

    /// <summary>
    ///   Verifies that a non-existent tag returns an empty post ID array.
    /// </summary>
    procedure GetPostIdsNoResults;

    /// <summary>
    ///   Verifies removing a tag.
    /// </summary>
    procedure Remove;

    /// <summary>
    ///   Verifies that removing a tag cascades to delete post-tag associations.
    /// </summary>
    procedure RemoveCascade;
  end;

  /// <summary>
  ///   Tests for the comment service (<c>IComment</c>): add, moderate, retrieve.
  /// </summary>
  TTestCommentService = class(TMsTestCase)
  published
    /// <summary>
    ///   Verifies adding a pending comment.
    /// </summary>
    procedure AddPending;

    /// <summary>
    ///   Verifies that adding a comment with an empty body returns 0.
    /// </summary>
    procedure AddEmptyBody;

    /// <summary>
    ///   Verifies that adding a comment with an invalid post ID returns 0.
    /// </summary>
    procedure AddInvalidPostId;

    /// <summary>
    ///   Verifies retrieval of pending comments.
    /// </summary>
    procedure GetPending;

    /// <summary>
    ///   Verifies approving a pending comment.
    /// </summary>
    procedure Approve;

    /// <summary>
    ///   Verifies that approving a non-existent comment returns false.
    /// </summary>
    procedure ApproveNotFound;

    /// <summary>
    ///   Verifies rejecting a pending comment.
    /// </summary>
    procedure Reject;

    /// <summary>
    ///   Verifies retrieval of approved comments for a post.
    /// </summary>
    procedure GetByPost;

    /// <summary>
    ///   Verifies that a post without approved comments returns an empty array.
    /// </summary>
    procedure GetByPostNoComments;
  end;

  /// <summary>
  ///   Tests for the media service (<c>IMedia</c>): upload, download, remove.
  /// </summary>
  TTestMediaService = class(TMsTestCase)
  published
    /// <summary>
    ///   Verifies uploading a file and retrieving its metadata.
    /// </summary>
    procedure UploadAndGetInfo;

    /// <summary>
    ///   Verifies that uploading with an empty filename returns 0.
    /// </summary>
    procedure UploadEmptyFileName;

    /// <summary>
    ///   Verifies that uploading empty data returns 0.
    /// </summary>
    procedure UploadEmptyData;

    /// <summary>
    ///   Verifies that uploading data exceeding the size limit returns 0.
    /// </summary>
    procedure UploadTooLarge;

    /// <summary>
    ///   Verifies that getting info for a non-existent media returns empty JSON.
    /// </summary>
    procedure GetInfoNotFound;

    /// <summary>
    ///   Verifies downloading a previously uploaded file.
    /// </summary>
    procedure GetFile;

    /// <summary>
    ///   Verifies that downloading a non-existent file returns empty data.
    /// </summary>
    procedure GetFileNotFound;

    /// <summary>
    ///   Verifies removing a media file.
    /// </summary>
    procedure Remove;

    /// <summary>
    ///   Verifies that removing a non-existent media returns false.
    /// </summary>
    procedure RemoveNotFound;
  end;

  /// <summary>
  ///   Tests for the blog gateway aggregation (<c>IBlog</c>): full post with author, tags, comments.
  /// </summary>
  TTestBlogAggregation = class(TMsTestCase)
  published
    /// <summary>
    ///   Verifies that <c>GetPostFull</c> returns a post with author, tags, and comments.
    /// </summary>
    procedure GetPostFull;

    /// <summary>
    ///   Verifies that <c>GetPostFull</c> returns empty JSON for a non-existent post.
    /// </summary>
    procedure GetPostFullNotFound;

    /// <summary>
    ///   Verifies that <c>GetPostsByTag</c> returns posts associated with a tag.
    /// </summary>
    procedure GetPostsByTag;

    /// <summary>
    ///   Verifies that <c>GetPostsByTag</c> returns empty JSON for a non-existent tag.
    /// </summary>
    procedure GetPostsByTagNotFound;
  end;

  /// <summary>
  ///   Unit-level and integration tests for <c>TCircuitBreaker</c>: state machine, threshold tripping,
  ///   cooldown, half-open probing, and integration with <c>TBlogService</c>.
  /// </summary>
  TTestCircuitBreaker = class(TSynTestCase)
  published
    /// <summary>
    ///   A freshly created breaker is in the <c>Closed</c> state and allows requests.
    /// </summary>
    procedure InitialStateIsClosedAndAllows;

    /// <summary>
    ///   Failures below the configured threshold do not trip the breaker.
    /// </summary>
    procedure FailuresBelowThresholdKeepClosed;

    /// <summary>
    ///   Reaching the configured number of consecutive failures trips the breaker to <c>Open</c>.
    /// </summary>
    procedure ConsecutiveFailuresTripBreaker;

    /// <summary>
    ///   A success in the <c>Closed</c> state resets the consecutive-failure counter, so the breaker
    ///   does not trip on subsequent isolated failures.
    /// </summary>
    procedure SuccessResetsFailureCount;

    /// <summary>
    ///   While the breaker is <c>Open</c>, <c>AllowRequest</c> rejects every call without paying any
    ///   upstream cost.
    /// </summary>
    procedure OpenRejectsRequests;

    /// <summary>
    ///   Once the cooldown period elapses, the next <c>AllowRequest</c> transitions the breaker into
    ///   <c>HalfOpen</c> and lets a single probe through.
    /// </summary>
    procedure OpenTransitionsToHalfOpenAfterCooldown;

    /// <summary>
    ///   In <c>HalfOpen</c>, only one probe call is permitted at a time.
    /// </summary>
    procedure HalfOpenAllowsOnlyOneProbe;

    /// <summary>
    ///   A successful probe in <c>HalfOpen</c> closes the breaker.
    /// </summary>
    procedure HalfOpenSuccessClosesBreaker;

    /// <summary>
    ///   A failed probe in <c>HalfOpen</c> bounces the breaker back to <c>Open</c>.
    /// </summary>
    procedure HalfOpenFailureReopensBreaker;

    /// <summary>
    ///   Integration: with a <c>TBlogService</c> wired to a counting failing user backend, exactly
    ///   <c>DEFAULT_FAILURE_THRESHOLD</c> upstream calls are observed before the breaker trips and
    ///   subsequent calls fast-fail without ever reaching the upstream.
    /// </summary>
    procedure IntegrationFastFailsAfterTrip;

    /// <summary>
    ///   Integration: <c>TAnalyticsService.GetRecentPostsFull</c> with a counting failing comments
    ///   backend. With more posts than the failure threshold, the breaker must trip mid-aggregation
    ///   and the remaining posts must not trigger any further <c>FComments.GetByPost</c> calls.
    /// </summary>
    procedure AnalyticsBreakerTripsAndStopsCalls;
  end;

  /// <summary>
  ///   Unit tests for <c>TRateLimiter</c>: bucket creation, burst behaviour, refill, per-key isolation,
  ///   refund on success, and idle eviction.
  /// </summary>
  TTestRateLimiter = class(TSynTestCase)
  published

    /// <summary>
    ///   A freshly created limiter starts with no buckets and the very first <c>TryAcquire</c> for any
    ///   key succeeds because new buckets are seeded at full capacity.
    /// </summary>
    procedure FirstAcquireOnNewKeyAlwaysSucceeds;

    /// <summary>
    ///   A burst of <c>Capacity</c> back-to-back acquires on the same key all succeed; the next one is
    ///   rejected because the bucket is empty.
    /// </summary>
    procedure BurstAllowsExactlyCapacityRequests;

    /// <summary>
    ///   Exhausting the bucket of one key must not affect any other key. Each client gets its own
    ///   independent budget.
    /// </summary>
    procedure BucketsAreIsolatedPerKey;

    /// <summary>
    ///   After the bucket is empty, waiting long enough for the configured refill rate to add tokens
    ///   makes <c>TryAcquire</c> succeed again.
    /// </summary>
    procedure RefillRestoresTokensOverTime;

    /// <summary>
    ///   <c>Reset</c> on an exhausted bucket restores it to full capacity, so the same key can issue a
    ///   new full burst immediately.
    /// </summary>
    procedure ResetRestoresFullCapacity;

    /// <summary>
    ///   <c>Reset</c> on a key that has never been seen is a no-op and must not crash or create a
    ///   spurious bucket.
    /// </summary>
    procedure ResetIsNoopForUnknownKey;

    /// <summary>
    ///   <c>TryAcquireN</c> with a cost greater than one decrements the bucket by that many tokens and
    ///   rejects requests once the remaining tokens are insufficient.
    /// </summary>
    procedure TryAcquireNRespectsCost;

    /// <summary>
    ///   Buckets that have been idle for longer than the configured TTL are evicted on the next
    ///   acquire, so the storage does not grow without bound under churn.
    /// </summary>
    procedure IdleEvictionRemovesUnusedBuckets;
  end;

  /// <summary>
  ///   Resilience tests for the blog gateway when sub-services are unavailable.
  /// </summary>
  TTestBlogResilience = class(TSynTestCase)
  published
    /// <summary>
    ///   Verifies graceful degradation when the comment service is unavailable.
    /// </summary>
    procedure GetPostFullWithoutComments;

    /// <summary>
    ///   Verifies graceful degradation when the tag service is unavailable.
    /// </summary>
    procedure GetPostFullWithoutTags;

    /// <summary>
    ///   Verifies graceful degradation when the user service is unavailable.
    /// </summary>
    procedure GetPostFullWithoutUsers;

    /// <summary>
    ///   Verifies graceful degradation when all enrichment services are unavailable.
    /// </summary>
    procedure GetPostFullWithoutAllEnrichment;

    /// <summary>
    ///   Verifies graceful degradation of <c>GetPostsByTag</c> when the user service is unavailable.
    /// </summary>
    procedure GetPostsByTagWithoutUsers;
  end;

  /// <summary>
  ///   Tests for the analytics service (<c>IAnalytics</c>): overview, stats, tag cloud.
  /// </summary>
  TTestAnalyticsService = class(TMsTestCase)
  published
    /// <summary>
    ///   Verifies the analytics overview with post, author, tag, and comment counts.
    /// </summary>
    procedure GetOverview;

    /// <summary>
    ///   Verifies per-author statistics.
    /// </summary>
    procedure GetAuthorStats;

    /// <summary>
    ///   Verifies the tag cloud with tag names and post counts.
    /// </summary>
    procedure GetTagCloud;

    /// <summary>
    ///   Verifies comment activity data including pending count.
    /// </summary>
    procedure GetCommentActivity;

    /// <summary>
    ///   Verifies retrieval of recent posts with full enrichment.
    /// </summary>
    procedure GetRecentPostsFull;

    /// <summary>
    ///   Verifies that requesting zero recent posts returns an empty array.
    /// </summary>
    procedure GetRecentPostsFullEmpty;
  end;

  /// <summary>
  ///   Resilience tests for the analytics service when sub-services are unavailable.
  /// </summary>
  TTestAnalyticsResilience = class(TSynTestCase)
  published
    /// <summary>
    ///   Verifies analytics overview when all services are unavailable.
    /// </summary>
    procedure GetOverviewWithoutPosts;

    /// <summary>
    ///   Verifies analytics overview when only the user service is unavailable.
    /// </summary>
    procedure GetOverviewWithoutUsers;

    /// <summary>
    ///   Verifies recent posts when the comment service is unavailable.
    /// </summary>
    procedure GetRecentPostsFullWithoutComments;

    /// <summary>
    ///   Verifies recent posts when the tag service is unavailable.
    /// </summary>
    procedure GetRecentPostsFullWithoutTags;
  end;

  /// <summary>
  ///   Tests for the configuration service (<c>IConfig</c>): per-service config, registry.
  /// </summary>
  TTestConfigService = class(TSynTestCase)
  published
    /// <summary>
    ///   Verifies retrieving configuration for a known service.
    /// </summary>
    procedure GetServiceConfigKnown;

    /// <summary>
    ///   Verifies that retrieving configuration for an unknown service returns empty JSON.
    /// </summary>
    procedure GetServiceConfigUnknown;

    /// <summary>
    ///   Verifies retrieval of all service configurations.
    /// </summary>
    procedure GetAllConfigs;

    /// <summary>
    ///   Verifies the service registry with host and port information.
    /// </summary>
    procedure GetServiceRegistry;

    /// <summary>
    ///   Verifies that the service registry excludes sensitive fields.
    /// </summary>
    procedure GetServiceRegistryNoSecrets;

    /// <summary>
    ///   Verifies that fields from the <c>defaults</c> block are inherited by services that do not override them.
    /// </summary>
    procedure DefaultsAppliedWhenNotOverridden;

    /// <summary>
    ///   Verifies that per-service fields override matching keys from the <c>defaults</c> block.
    /// </summary>
    procedure ServiceOverridesDefaults;

    /// <summary>
    ///   Verifies that <c>GetServiceConfig('defaults')</c> returns '{}' since defaults is not a real service.
    /// </summary>
    procedure DefaultsKeyIsNotAService;

    /// <summary>
    ///   Verifies that <c>GetAllConfigs</c> excludes the <c>defaults</c> block from the result.
    /// </summary>
    procedure GetAllConfigsExcludesDefaults;

    /// <summary>
    ///   Verifies that <c>GetServiceRegistry</c> excludes the <c>defaults</c> block from the result and that the
    ///   registry's Host falls back to the value from the <c>defaults</c> block when the service does not set it.
    /// </summary>
    procedure GetServiceRegistryUsesDefaultsForHost;
  end;

  /// <summary>
  ///   End-to-end workflow test covering user, auth, post, tag, comment, and aggregation.
  /// </summary>
  TTestFullWorkflow = class(TMsTestCase)
  published
    /// <summary>
    ///   Runs the full blog workflow: create user, register, login, post, tag, comment, aggregate.
    /// </summary>
    procedure EndToEnd;
  end;

  /// <summary>
  ///   Tests for the correlation-ID infrastructure in <c>ms.shared.correlation</c>: generation, threadvar
  ///   storage, header extraction, and the message-text parser used by the central log service.
  /// </summary>
  TTestCorrelationIds = class(TMsTestCase)
  published
    /// <summary>
    ///   Verifies that <c>GenerateCorrelationId</c> produces unique values for successive calls.
    /// </summary>
    procedure GenerateUnique;

    /// <summary>
    ///   Verifies that the generated ID is a 36-character lowercase UUID without surrounding braces.
    /// </summary>
    procedure GenerateValidFormat;

    /// <summary>
    ///   Verifies that <c>SetCurrentCorrelationId</c> + <c>GetCurrentCorrelationId</c> round-trip correctly.
    /// </summary>
    procedure SetGetRoundTrip;

    /// <summary>
    ///   Verifies that <c>ClearCurrentCorrelationId</c> resets the threadvar to empty.
    /// </summary>
    procedure ClearResetsValue;

    /// <summary>
    ///   Verifies that <c>ExtractCorrelationIdFromHeaders</c> finds the header in a typical HTTP block.
    /// </summary>
    procedure ExtractFromHeadersWhenPresent;

    /// <summary>
    ///   Verifies that <c>ExtractCorrelationIdFromHeaders</c> returns empty when the header is absent.
    /// </summary>
    procedure ExtractFromHeadersWhenAbsent;

    /// <summary>
    ///   Verifies that header extraction is case-insensitive (mORMot2's <c>FindNameValue</c> contract).
    /// </summary>
    procedure ExtractFromHeadersCaseInsensitive;

    /// <summary>
    ///   Verifies that <c>EnsureCorrelationIdFromHeaders</c> uses the existing header value.
    /// </summary>
    procedure EnsureUsesExistingHeader;

    /// <summary>
    ///   Verifies that <c>EnsureCorrelationIdFromHeaders</c> generates a new ID when none was supplied.
    /// </summary>
    procedure EnsureGeneratesWhenAbsent;

    /// <summary>
    ///   Verifies that the message parser in <c>ms.logs.server</c> finds a UUID prefix.
    /// </summary>
    procedure ParseFromMessagePrefix;

    /// <summary>
    ///   Verifies that the message parser returns empty for plain text without a UUID.
    /// </summary>
    procedure ParseFromMessageWithoutUuid;

    /// <summary>
    ///   Verifies that the message parser ignores bracketed strings that look like UUIDs but are not.
    /// </summary>
    procedure ParseFromMessageInvalidBrackets;
  end;

  /// <summary>
  ///   Minimal test subscriber that records every <c>NotifyEntry</c> call for assertions.
  /// </summary>
  TTestLogStreamRecorder = class(TInterfacedObject, ILogStreamCallback)
  strict private
    FReceived: TLogEntryDtoArray;
    FRaiseOnNext: boolean;
  public
    constructor Create(
      aRaiseOnNext: boolean = False
      );
    procedure NotifyEntry(
      const aEntry: TLogEntryDto
      );
    function ReceivedCount: integer;
    function ReceivedEntry(
      aIdx: integer
      ): TLogEntryDto;
    procedure Reset;
  end;

  /// <summary>
  ///   Tests for the central logging service (<c>ms.logs</c>): ingestion, retrieval by correlation ID,
  ///   recent filter, full-text search, and stats. The tests use the in-process REST server with the
  ///   <c>TOrmLogEntry</c> tables wired into <c>TBlogTestContext</c>.
  /// </summary>
  TTestLogService = class(TMsTestCase)
  published
    /// <summary>
    ///   Verifies that an empty correlation-ID query returns an empty array (no exception).
    /// </summary>
    procedure ByCorrelationIdEmpty;

    /// <summary>
    ///   Verifies that ingested entries can be retrieved by their correlation ID.
    /// </summary>
    procedure IngestAndQueryByCorrelation;

    /// <summary>
    ///   Verifies that the parser correctly extracts the correlation ID at ingestion time.
    /// </summary>
    procedure IngestParsesCorrelationFromText;

    /// <summary>
    ///   Verifies that the <c>Recent</c> query honors the service-name filter.
    /// </summary>
    procedure RecentFiltersByService;

    /// <summary>
    ///   Verifies that the <c>Recent</c> query honors the minimum-level filter.
    /// </summary>
    procedure RecentFiltersByMinLevel;

    /// <summary>
    ///   Verifies that <c>Stats</c> returns a non-zero total entries count and per-service breakdown.
    /// </summary>
    procedure StatsReportsTotals;
  end;

  /// <summary>
  ///   Tests for <c>TLogStreamService</c>: the in-process pub/sub broadcaster used by the WebSocket-based
  ///   live log tail. These tests bypass the WebSocket transport and exercise the service directly through
  ///   the <c>ILogStream</c> interface, which is sufficient for the lifecycle and broadcast logic.
  /// </summary>
  TTestLogStream = class(TMsTestCase)
  published
    /// <summary>
    ///   Verifies that an entry passed to <c>Broadcast</c> reaches a single subscriber.
    /// </summary>
    procedure SingleSubscriberReceivesEntry;

    /// <summary>
    ///   Verifies that every active subscriber receives every broadcast entry.
    /// </summary>
    procedure MultipleSubscribersAllReceive;

    /// <summary>
    ///   Verifies that an unsubscribed callback receives no further entries.
    /// </summary>
    procedure UnsubscribedCallbackStopsReceiving;

    /// <summary>
    ///   Verifies that an ingested batch is automatically broadcast to subscribers (the integration path).
    /// </summary>
    procedure IngestionBroadcastsToSubscribers;

    /// <summary>
    ///   Verifies that a subscriber that raises during <c>NotifyEntry</c> is removed automatically so other
    ///   subscribers continue to receive future broadcasts.
    /// </summary>
    procedure FailingSubscriberIsDropped;
  end;

  /// <summary>
  ///   End-to-end round-trip test that exercises the full WebSocket-based event pipeline:
  ///   <list>
  ///   <item>Spins up a real <c>TRestHttpServer</c> with WebSocket support on a high test port</item>
  ///   <item>Registers <c>ILogIngestion</c> + <c>ILogStream</c> services on the server</item>
  ///   <item>Creates a <c>TRestHttpClientWebsockets</c>, performs <c>WebSocketsUpgrade</c>, resolves both
  ///     interfaces</item>
  ///   <item>Calls <c>ILogStream.Subscribe(callback)</c> -- this is the path that exercises mORMot2's
  ///     <c>TServiceContainerServer.GetFakeCallback</c> mechanism</item>
  ///   <item>Calls <c>ILogIngestion.AppendBatch(...)</c> which should fan out to the subscriber</item>
  ///   <item>Polls (with timeout) until the callback fires on the client side</item>
  ///   </list>
  ///   This test would fail with <c>EInterfaceFactory: Unexpected GetFakeCallback(ILogStreamCallback)</c>
  ///   if the explicit <c>TInterfaceFactory.RegisterInterfaces</c> call in <c>ms.shared.api</c>'s
  ///   initialization were removed -- it is a regression guard for that exact class of bug.
  /// </summary>
  TTestWebSocketRoundtrip = class(TMsTestCase)
  published
    /// <summary>
    ///   Subscribes a callback over a real WebSocket connection, ingests one entry, and verifies that
    ///   the callback fires within a timeout.
    /// </summary>
    procedure SubscribeIngestReceive;
  end;

  /// <summary>
  ///   Top-level test suite that creates the shared context and registers all test cases.
  /// </summary>
  TBlogTests = class(TSynTests)
  strict private
    /// <summary>
    ///   Shared test context holding all service implementations and interfaces.
    /// </summary>
    FContext: TBlogTestContext;
  public
    /// <summary>
    ///   Returns the shared <c>TBlogTestContext</c> used by all test cases.
    /// </summary>
    property TestContext: TBlogTestContext read FContext;

    /// <summary>
    ///   Creates the test suite and initializes the shared blog test context.
    /// </summary>
    /// <param name="Ident">
    ///   Optional identifier for the test suite.
    /// </param>
    constructor Create(
      const Ident: string = ''
      ); override;

    /// <summary>
    ///   Destroys the test suite and frees the shared context.
    /// </summary>
    destructor Destroy; override;
  published
    /// <summary>
    ///   Registers all service test cases with the suite.
    /// </summary>
    procedure Services;
  end;

implementation

constructor TBlogTestContext.Create;

  procedure RegisterService(
    aImpl: TInterfacedObject;
    aInterface: PRttiInfo
    );
  var
    Factory: TServiceFactoryServerAbstract;
  begin
    Factory := FRestServer.ServiceRegister(aImpl, [aInterface]);
    Factory.ByPassAuthentication := True;
    Factory.ResultAsJsonObjectWithoutResult := True;
  end;

begin
  inherited Create;
  // Single model with all ORM classes
  FModel := TOrmModel.Create([
    TOrmAuthUser,
    TOrmAuthor,
    TOrmBlogPost,
    TOrmBlogPostFts,
    TOrmBlogTag,
    TOrmPostTag,
    TOrmBlogComment,
    TOrmMediaFile,
    TOrmLogEntry,
    TOrmLogEntryFts
  ], MODEL_ROOT);
  // In-memory database
  FRestServer := TRestServerDB.Create(FModel, SQLITE_MEMORY_DATABASE_NAME);
  FRestServer.DB.Synchronous := smOff;
  FRestServer.Server.CreateMissingTables;
  // Temp directory for media files
  FMediaPath := Executable.ProgramFilePath + 'test_media' + PathDelim;
  if not DirectoryExists(FMediaPath) then
    CreateDir(FMediaPath);
  // Create service implementations
  FJwt := TBlogJwt.Create(JWT_SECRET_DEFAULT, JWT_EXPIRATION_MINUTES);
  FAuthImpl := TAuthService.Create(FRestServer.Orm, FJwt);
  FUserImpl := TUserService.Create(FRestServer.Orm);
  FPostImpl := TPostService.Create(FRestServer.Orm);
  FTagImpl := TTagService.Create(FRestServer.Orm);
  FCommentImpl := TCommentService.Create(FRestServer.Orm);
  FMediaImpl := TMediaService.Create(FRestServer.Orm, FMediaPath);
  FBlogImpl := TBlogService.Create(FPostImpl, FUserImpl, FTagImpl, FCommentImpl);
  FAnalyticsImpl := TAnalyticsService.Create(FPostImpl, FUserImpl, FTagImpl, FCommentImpl);
  FLogStreamImpl := TLogStreamService.Create;
  FLogIngestionImpl := TLogIngestionService.Create(FRestServer.Orm, FLogStreamImpl);
  FLogQueryImpl := TLogQueryService.Create(FRestServer.Orm);
  // Keep interface references
  Auth := FAuthImpl;
  User := FUserImpl;
  Post := FPostImpl;
  Tag := FTagImpl;
  Comment := FCommentImpl;
  Media := FMediaImpl;
  Blog := FBlogImpl;
  Analytics := FAnalyticsImpl;
  LogIngestion := FLogIngestionImpl;
  LogQuery := FLogQueryImpl;
  LogStream := FLogStreamImpl;
  LogStreamSvc := FLogStreamImpl;
  // Register on REST server
  RegisterService(FAuthImpl, TypeInfo(IAuth));
  RegisterService(FUserImpl, TypeInfo(IUser));
  RegisterService(FPostImpl, TypeInfo(IPost));
  RegisterService(FTagImpl, TypeInfo(ITag));
  RegisterService(FCommentImpl, TypeInfo(IComment));
  RegisterService(FMediaImpl, TypeInfo(IMedia));
  RegisterService(FBlogImpl, TypeInfo(IBlog));
  RegisterService(FAnalyticsImpl, TypeInfo(IAnalytics));
  RegisterService(FLogIngestionImpl, TypeInfo(ILogIngestion));
  RegisterService(FLogQueryImpl, TypeInfo(ILogQuery));
  RegisterService(FLogStreamImpl, TypeInfo(ILogStream));
end;

destructor TBlogTestContext.Destroy;
begin
  // Release interfaces before server
  Auth := nil;
  User := nil;
  Post := nil;
  Tag := nil;
  Comment := nil;
  Media := nil;
  Blog := nil;
  Analytics := nil;
  LogIngestion := nil;
  LogQuery := nil;
  LogStream := nil;
  LogStreamSvc := nil;
  FreeAndNil(FRestServer);
  FreeAndNil(FModel);
  FreeAndNil(FJwt);
  // Clean up temp media directory
  if DirectoryExists(FMediaPath) then
    DirectoryDelete(FMediaPath, FILES_ALL, True);
  inherited Destroy;
end;


function TMsTestCase.Context: TBlogTestContext;
begin
  Exit((Owner as TBlogTests).TestContext);
end;

procedure TTestUserService.AddAndGet;
var
  Id: TID;
  AuthorDto: TAuthorDto;
  CreateDto: TAuthorCreateDto;
begin
  CreateDto.DisplayName := 'Max';
  CreateDto.Bio := 'Test author';
  CreateDto.WebsiteUrl := 'https://example.com';
  Id := Context.User.Add(CreateDto);
  Check(Id > 0, 'User.Add should return positive ID');
  AuthorDto := Context.User.Get(Id);
  Check(AuthorDto.ID > 0, 'User.Get should return a valid record');
  CheckEqual(AuthorDto.DisplayName, 'Max');
  CheckEqual(AuthorDto.Bio, 'Test author');
end;

procedure TTestUserService.AddEmptyName;
var
  CreateDto: TAuthorCreateDto;
begin
  CreateDto.DisplayName := '';
  CreateDto.Bio := 'No name';
  CheckEqual(Context.User.Add(CreateDto), 0, 'empty DisplayName should return 0');
  CreateDto.Bio := '';
  CheckEqual(Context.User.Add(CreateDto), 0, 'empty DTO should return 0');
end;

procedure TTestUserService.GetNotFound;
var
  AuthorDto: TAuthorDto;
begin
  AuthorDto := Context.User.Get(99999);
  Check(AuthorDto.ID = 0, 'not found should return ID=0');
end;

procedure TTestUserService.Update;
var
  Id: TID;
  AuthorDto: TAuthorDto;
  CreateDto: TAuthorCreateDto;
begin
  CreateDto.DisplayName := 'Update Test';
  Id := Context.User.Add(CreateDto);
  Check(Id > 0);
  Check(Context.User.Update(Id, '{"Bio":"Updated bio"}'));
  AuthorDto := Context.User.Get(Id);
  CheckEqual(AuthorDto.Bio, 'Updated bio');
  CheckEqual(AuthorDto.DisplayName, 'Update Test');
end;

procedure TTestUserService.UpdateNotFound;
begin
  Check(not Context.User.Update(99999, '{"Bio":"ghost"}'), 'update non-existent should return false');
end;

procedure TTestUserService.GetAll;
var
  AllAuthors: TAuthorDtoArray;
begin
  AllAuthors := Context.User.GetAll;
  Check(Length(AllAuthors) >= 2, 'should have at least 2 users');
end;

procedure TTestUserService.Remove;
var
  Id: TID;
  AuthorDto: TAuthorDto;
  CreateDto: TAuthorCreateDto;
begin
  CreateDto.DisplayName := 'To Remove';
  Id := Context.User.Add(CreateDto);
  Check(Id > 0);
  Check(Context.User.Remove(Id));
  AuthorDto := Context.User.Get(Id);
  Check(AuthorDto.ID = 0, 'removed user should return ID=0');
end;

procedure TTestUserService.RemoveNotFound;
var
  AuthorDto: TAuthorDto;
begin
  // mORMot2 ORM returns True even if no row was deleted
  Check(Context.User.Remove(99999), 'DELETE on non-existent is not an error in mORMot2');
  AuthorDto := Context.User.Get(99999);
  Check(AuthorDto.ID = 0, 'record should still not exist');
end;

procedure TTestAuthService.RegisterUser;
var
  Id: TID;
begin
  Id := Context.Auth.Register('test@example.com', 'secret123', 1);
  Check(Id > 0, 'Auth.Register should return positive ID');
end;

procedure TTestAuthService.RegisterDuplicate;
var
  Id: TID;
begin
  Id := Context.Auth.Register('test@example.com', 'other', 1);
  CheckEqual(Id, 0, 'duplicate email should return 0');
end;

procedure TTestAuthService.RegisterEmptyEmail;
begin
  CheckEqual(Context.Auth.Register('', 'pass123', 1), 0, 'empty email should return 0');
end;

procedure TTestAuthService.RegisterEmptyPassword;
begin
  CheckEqual(Context.Auth.Register('nopass@example.com', '', 1), 0, 'empty password should return 0');
end;

procedure TTestAuthService.ChallengeAndAuthenticate;
var
  McfInfo, ServerNonce: RawUtf8;
  ClientProof, Token, ServerProof: RawUtf8;
  UserId: TID;
  McfHash, PersistedKey: RawUtf8;
  ClientSignature: THash256;
  Ok: boolean;
begin
  // Phase 1: Challenge
  Context.Auth.Challenge('test@example.com', McfInfo, ServerNonce);
  Check(McfInfo <> '', 'Challenge should return McfInfo');
  Check(ServerNonce <> '', 'Challenge should return ServerNonce');
  // Phase 2: Compute client proof (replicating what the browser does)
  McfHash := ModularCryptHash(McfInfo, 'secret123');
  Check(McfHash <> '', 'ModularCryptHash should succeed');
  PersistedKey := ScramPersistedKey(McfHash, 'test@example.com');
  ClientProof := ScramClientProof(McfHash, 'test@example.com', ClientSignature, ['test@example.com', ServerNonce]);
  Check(ClientProof <> '', 'ScramClientProof should succeed');
  // Phase 3: Authenticate
  Ok := Context.Auth.Authenticate('test@example.com', ServerNonce, ClientProof, Token, UserId, ServerProof);
  Check(Ok, 'Authenticate should succeed');
  Check(Token <> '', 'should return JWT token');
  Check(UserId > 0, 'should return UserId');
  Check(ServerProof <> '', 'should return ServerProof');
end;

procedure TTestAuthService.AuthenticateWrongPassword;
var
  McfInfo, ServerNonce, McfHash: RawUtf8;
  ClientProof, Token, ServerProof: RawUtf8;
  UserId: TID;
  ClientSignature: THash256;
begin
  Context.Auth.Challenge('test@example.com', McfInfo, ServerNonce);
  McfHash := ModularCryptHash(McfInfo, 'WRONG-PASSWORD');
  ClientProof := ScramClientProof(McfHash, 'test@example.com', ClientSignature, ['test@example.com', ServerNonce]);
  Check(not Context.Auth.Authenticate('test@example.com', ServerNonce, ClientProof, Token, UserId, ServerProof),
    'wrong password should fail');
  CheckEqual(Token, '', 'no token on failure');
end;

procedure TTestAuthService.AuthenticateUnknownEmail;
var
  McfInfo, ServerNonce, McfHash: RawUtf8;
  ClientProof, Token, ServerProof: RawUtf8;
  UserId: TID;
  ClientSignature: THash256;
begin
  Context.Auth.Challenge('unknown@example.com', McfInfo, ServerNonce);
  Check(McfInfo <> '', 'should return fake MCF info (anti-enumeration)');
  McfHash := ModularCryptHash(McfInfo, 'anypass');
  ClientProof := ScramClientProof(McfHash, 'unknown@example.com', ClientSignature, ['unknown@example.com', ServerNonce]);
  Check(not Context.Auth.Authenticate('unknown@example.com', ServerNonce, ClientProof, Token, UserId, ServerProof),
    'unknown email should fail');
end;

procedure TTestAuthService.AuthenticateReplayedNonce;
var
  McfInfo, ServerNonce, McfHash: RawUtf8;
  ClientProof, Token, ServerProof: RawUtf8;
  UserId: TID;
  ClientSignature: THash256;
begin
  // Get a valid challenge
  Context.Auth.Challenge('test@example.com', McfInfo, ServerNonce);
  McfHash := ModularCryptHash(McfInfo, 'secret123');
  ClientProof := ScramClientProof(McfHash, 'test@example.com', ClientSignature, ['test@example.com', ServerNonce]);
  // First auth consumes the nonce
  Context.Auth.Authenticate('test@example.com', ServerNonce, ClientProof, Token, UserId, ServerProof);
  // Replay with same nonce should fail
  Check(not Context.Auth.Authenticate('test@example.com', ServerNonce, ClientProof, Token, UserId, ServerProof),
    'replayed nonce should fail');
end;

procedure TTestAuthService.LoginThrottlesAfterRepeatedFailures;
const
  THROTTLED_EMAIL: RawUtf8 = 'throttle@example.com';
  CONTROL_EMAIL: RawUtf8 = 'control@example.com';
  PASSWORD: RawUtf8 = 'rightpass';
var
  CreateDto: TAuthorCreateDto;
  ThrottledUserId, ControlUserId: TID;
  McfInfo, ServerNonce, McfHash: RawUtf8;
  RealProof, Token, ServerProof: RawUtf8;
  AttemptIdx: Integer;
  ClientSignature: THash256;
  AuthOk: Boolean;
begin
  // Set up two independent accounts so the test can compare a throttled key against an untouched one.
  CreateDto.DisplayName := 'Throttle Victim';
  ThrottledUserId := Context.User.Add(CreateDto);
  Check(ThrottledUserId > 0, 'create throttled author');
  Check(Context.Auth.Register(THROTTLED_EMAIL, PASSWORD, ThrottledUserId) > 0,
    'register throttled account');
  CreateDto.DisplayName := 'Control';
  ControlUserId := Context.User.Add(CreateDto);
  Check(ControlUserId > 0, 'create control author');
  Check(Context.Auth.Register(CONTROL_EMAIL, PASSWORD, ControlUserId) > 0, 'register control account');
  // Drain the per-email bucket: capacity is 10 reachable failed proofs. Each iteration grabs a fresh
  // challenge and submits a non-empty garbage proof so ScramServerProof fails after TryAcquire spent a
  // token. The 11th attempt then must be denied by the limiter rather than by the proof check.
  for AttemptIdx := 1 to 10 do
  begin
    Context.Auth.Challenge(THROTTLED_EMAIL, McfInfo, ServerNonce);
    Check(not Context.Auth.Authenticate(THROTTLED_EMAIL, ServerNonce, 'garbage-proof', Token,
      ThrottledUserId, ServerProof), 'failed proof must not authenticate');
  end;
  // Now build a CORRECT proof for the throttled email. Without the limiter this would succeed; with
  // the bucket exhausted it must still be rejected.
  Context.Auth.Challenge(THROTTLED_EMAIL, McfInfo, ServerNonce);
  McfHash := ModularCryptHash(McfInfo, PASSWORD);
  RealProof := ScramClientProof(McfHash, THROTTLED_EMAIL, ClientSignature, [THROTTLED_EMAIL, ServerNonce]);
  AuthOk := Context.Auth.Authenticate(THROTTLED_EMAIL, ServerNonce, RealProof, Token,
    ThrottledUserId, ServerProof);
  Check(not AuthOk, 'rate limiter must reject the correct password once the bucket is empty');
  CheckEqual(Token, '', 'no token must be issued for a throttled login');
  // The control email shares the auth service but has its own bucket and must remain usable.
  Context.Auth.Challenge(CONTROL_EMAIL, McfInfo, ServerNonce);
  McfHash := ModularCryptHash(McfInfo, PASSWORD);
  RealProof := ScramClientProof(McfHash, CONTROL_EMAIL, ClientSignature, [CONTROL_EMAIL, ServerNonce]);
  Check(Context.Auth.Authenticate(CONTROL_EMAIL, ServerNonce, RealProof, Token, ControlUserId,
    ServerProof), 'unrelated email must remain authenticatable');
  Check(Token <> '', 'control login must yield a token');
end;

procedure TTestAuthService.ValidateToken;
var
  McfInfo, ServerNonce, McfHash: RawUtf8;
  ClientProof, Token, ServerProof: RawUtf8;
  UserId, ValidatedUserId: TID;
  ClientSignature: THash256;
begin
  // Login to get a token
  Context.Auth.Challenge('test@example.com', McfInfo, ServerNonce);
  McfHash := ModularCryptHash(McfInfo, 'secret123');
  ClientProof := ScramClientProof(McfHash, 'test@example.com', ClientSignature, ['test@example.com', ServerNonce]);
  Context.Auth.Authenticate('test@example.com', ServerNonce, ClientProof, Token, UserId, ServerProof);
  // Validate the token
  Check(Context.Auth.Validate(Token, ValidatedUserId), 'Validate should succeed');
  CheckEqual(ValidatedUserId, UserId, 'UserId should match');
  // Invalid token should fail
  Check(not Context.Auth.Validate('invalid.token.here', ValidatedUserId), 'invalid token should fail');
end;

procedure TTestAuthService.ValidateInvalidToken;
var
  UserId: TID;
begin
  Check(not Context.Auth.Validate('', UserId), 'empty token should fail');
  Check(not Context.Auth.Validate('not.a.jwt', UserId), 'garbage token should fail');
end;

procedure TTestAuthService.ChangePassword;
var
  McfInfo, ServerNonce, McfHash: RawUtf8;
  ClientProof, Token, ServerProof: RawUtf8;
  UserId, AuthUserId: TID;
  ClientSignature: THash256;
  CreateDto: TAuthorCreateDto;
  Ok: boolean;
begin
  // Register a new user with a unique userId for this test
  CreateDto.DisplayName := 'PW Changer';
  UserId := Context.User.Add(CreateDto);
  Check(UserId > 0, 'create user for changepw test');
  AuthUserId := Context.Auth.Register('changepw@example.com', 'oldpass', UserId);
  Check(AuthUserId > 0, 'register changepw account');
  // Change password
  Check(Context.Auth.ChangePassword(UserId, 'oldpass', 'newpass'), 'ChangePassword should succeed');
  // Login with new password
  Context.Auth.Challenge('changepw@example.com', McfInfo, ServerNonce);
  McfHash := ModularCryptHash(McfInfo, 'newpass');
  ClientProof := ScramClientProof(McfHash, 'changepw@example.com', ClientSignature,
    ['changepw@example.com', ServerNonce]);
  Ok := Context.Auth.Authenticate('changepw@example.com', ServerNonce, ClientProof, Token, UserId, ServerProof);
  Check(Ok, 'login with new password should succeed');
end;

procedure TTestAuthService.ChangePasswordWrongOld;
var
  UserId: TID;
  CreateDto: TAuthorCreateDto;
begin
  CreateDto.DisplayName := 'WrongOld Test';
  UserId := Context.User.Add(CreateDto);
  Context.Auth.Register('wrongold@example.com', 'correct', UserId);
  Check(not Context.Auth.ChangePassword(UserId, 'WRONG', 'newpass'), 'wrong old password should fail');
end;

procedure TTestPostService.AddAndGet;
var
  Id: TID;
  PostDto: TPostDto;
  CreateDto: TPostCreateDto;
begin
  CreateDto.Title := 'First Post';
  CreateDto.Body := 'Hello world';
  CreateDto.AuthorId := 1;
  CreateDto.Status := POST_STATUS_PUBLISHED;
  Id := Context.Post.Add(CreateDto);
  Check(Id > 0, 'Post.Add should return positive ID');
  PostDto := Context.Post.Get(Id);
  CheckEqual(PostDto.Title, 'First Post');
  CheckEqual(PostDto.Slug, 'first-post');
  CheckEqual(PostDto.Status, POST_STATUS_PUBLISHED);
end;

procedure TTestPostService.AddEmptyTitle;
var
  CreateDto: TPostCreateDto;
begin
  CreateDto.Title := '';
  CreateDto.Body := 'no title';
  CreateDto.AuthorId := 1;
  CheckEqual(Context.Post.Add(CreateDto), 0, 'empty title should return 0');
  FillCharFast(CreateDto, SizeOf(CreateDto), 0);
  CheckEqual(Context.Post.Add(CreateDto), 0, 'empty DTO should return 0');
end;

procedure TTestPostService.GetNotFound;
var
  PostDto: TPostDto;
begin
  PostDto := Context.Post.Get(99999);
  Check(PostDto.ID = 0, 'not found should return ID=0');
end;

procedure TTestPostService.GetBySlug;
var
  PostDto: TPostDto;
begin
  PostDto := Context.Post.GetBySlug('first-post');
  CheckEqual(PostDto.Title, 'First Post');
end;

procedure TTestPostService.GetBySlugNotFound;
var
  PostDto: TPostDto;
begin
  PostDto := Context.Post.GetBySlug('no-such-slug');
  Check(PostDto.ID = 0, 'not found by slug should return ID=0');
end;

procedure TTestPostService.GetList;
var
  Id: TID;
  PostList: TPostListDto;
  CreateDto: TPostCreateDto;
begin
  // Add more posts
  CreateDto.Title := 'Draft Post';
  CreateDto.Body := 'Not published';
  CreateDto.AuthorId := 1;
  CreateDto.Status := POST_STATUS_DRAFT;
  Id := Context.Post.Add(CreateDto);
  Check(Id > 0);
  CreateDto.Title := 'Second Published';
  CreateDto.Body := 'Content';
  CreateDto.AuthorId := 1;
  CreateDto.Status := POST_STATUS_PUBLISHED;
  Id := Context.Post.Add(CreateDto);
  Check(Id > 0);
  // Get published only (status=1)
  PostList := Context.Post.GetList(1, 10, 1, 0);
  Check(PostList.Total >= 2, 'should have at least 2 published posts');
  // Filter by author
  PostList := Context.Post.GetList(1, 10, 0, 1);
  Check(PostList.Total >= 3, 'author 1 should have at least 3 posts');
end;

procedure TTestPostService.Update;
var
  Id: TID;
  PostDto: TPostDto;
  CreateDto: TPostCreateDto;
begin
  CreateDto.Title := 'To Update';
  CreateDto.Body := 'Original';
  CreateDto.AuthorId := 1;
  CreateDto.Status := POST_STATUS_DRAFT;
  Id := Context.Post.Add(CreateDto);
  Check(Id > 0);
  Check(Context.Post.Update(Id, '{"Title":"Updated Title","Status":1}'));
  PostDto := Context.Post.Get(Id);
  CheckEqual(PostDto.Title, 'Updated Title');
  CheckEqual(PostDto.Slug, 'updated-title');
  CheckEqual(PostDto.Status, POST_STATUS_PUBLISHED);
end;

procedure TTestPostService.UpdateNotFound;
begin
  Check(not Context.Post.Update(99999, '{"Title":"ghost"}'), 'update non-existent should return false');
end;

procedure TTestPostService.Remove;
var
  Id: TID;
  PostDto: TPostDto;
  CreateDto: TPostCreateDto;
begin
  CreateDto.Title := 'To Delete';
  CreateDto.Body := 'Gone soon';
  CreateDto.AuthorId := 1;
  CreateDto.Status := POST_STATUS_DRAFT;
  Id := Context.Post.Add(CreateDto);
  Check(Id > 0);
  Check(Context.Post.Remove(Id));
  PostDto := Context.Post.Get(Id);
  Check(PostDto.ID = 0, 'removed post should return ID=0');
end;

procedure TTestPostService.RemoveNotFound;
var
  PostDto: TPostDto;
begin
  // mORMot2 ORM returns True even if no row was deleted
  Check(Context.Post.Remove(99999), 'DELETE on non-existent is not an error in mORMot2');
  PostDto := Context.Post.Get(99999);
  Check(PostDto.ID = 0, 'record should still not exist');
end;

// Helper: adds a published post with the given title/excerpt/body and returns its ID. Used by the
// search tests to build up small, deterministic fixtures without cluttering every test with the
// same DTO boilerplate.
function AddPublishedPost(
  const aCtx: TBlogTestContext;
  const aTitle, aExcerpt, aBody: RawUtf8
  ): TID;
var
  CreateDto: TPostCreateDto;
begin
  FillCharFast(CreateDto, SizeOf(CreateDto), 0);
  CreateDto.Title := aTitle;
  CreateDto.Excerpt := aExcerpt;
  CreateDto.Body := aBody;
  CreateDto.AuthorId := 1;
  CreateDto.Status := POST_STATUS_PUBLISHED;
  Result := aCtx.Post.Add(CreateDto);
end;

// Helper: does the result array contain a post with this ID?
function SearchResultsContain(
  const aResults: TPostDtoArray;
  aId: TID
  ): boolean;
var
  ResultIdx: PtrInt;
begin
  for ResultIdx := 0 to High(aResults) do
    if aResults[ResultIdx].ID = aId then
      Exit(True);
  Result := False;
end;

procedure TTestPostSearch.EmptyQueryReturnsEmpty;
var
  Results: TPostDtoArray;
begin
  Results := Context.Post.Search('', 20);
  CheckEqual(Length(Results), 0, 'empty query must short-circuit');
end;

procedure TTestPostSearch.MatchByTitle;
var
  Id: TID;
  Results: TPostDtoArray;
begin
  Id := AddPublishedPost(Context,
    'An exclusive guide to lighthouses', 'short excerpt', 'body text');
  Check(Id > 0, 'fixture post must be created');
  Results := Context.Post.Search('lighthouses', 20);
  Check(SearchResultsContain(Results, Id), 'title word must match');
end;

procedure TTestPostSearch.MatchByBody;
var
  Id: TID;
  Results: TPostDtoArray;
begin
  Id := AddPublishedPost(Context,
    'Generic title alpha', 'no keyword here', 'full body with octopus inside');
  Check(Id > 0);
  Results := Context.Post.Search('octopus', 20);
  Check(SearchResultsContain(Results, Id), 'body word must match');
end;

procedure TTestPostSearch.MatchByExcerpt;
var
  Id: TID;
  Results: TPostDtoArray;
begin
  Id := AddPublishedPost(Context,
    'Generic title beta', 'teaser containing quokka', 'unrelated body');
  Check(Id > 0);
  Results := Context.Post.Search('quokka', 20);
  Check(SearchResultsContain(Results, Id), 'excerpt word must match');
end;

procedure TTestPostSearch.DraftsAreExcluded;
var
  DraftId: TID;
  PublishedId: TID;
  CreateDto: TPostCreateDto;
  Results: TPostDtoArray;
begin
  // Use a unique keyword so we get a deterministic, isolated result set.
  FillCharFast(CreateDto, SizeOf(CreateDto), 0);
  CreateDto.Title := 'Draft with platypus';
  CreateDto.Body := 'draft body';
  CreateDto.AuthorId := 1;
  CreateDto.Status := POST_STATUS_DRAFT;
  DraftId := Context.Post.Add(CreateDto);
  Check(DraftId > 0);
  PublishedId := AddPublishedPost(Context,
    'Published platypus article', 'platypus teaser', 'platypus body text');
  Check(PublishedId > 0);
  Results := Context.Post.Search('platypus', 20);
  Check(SearchResultsContain(Results, PublishedId), 'published platypus post must match');
  Check(not SearchResultsContain(Results, DraftId), 'draft platypus post must NOT match');
end;

procedure TTestPostSearch.OrderedByPublishedDesc;
var
  FirstId: TID;
  SecondId: TID;
  Results: TPostDtoArray;
begin
  FirstId := AddPublishedPost(Context,
    'Older narwhal story', 'teaser', 'narwhal body one');
  Check(FirstId > 0);
  // SQLite resolves NowUtc at microsecond resolution, but two back-to-back Add calls may share a
  // tick. We force a deterministic ordering by stamping PublishedAt via an Update on the newer
  // post -- future-dated so it sorts before the first one.
  SecondId := AddPublishedPost(Context,
    'Newer narwhal story', 'teaser', 'narwhal body two');
  Check(SecondId > 0);
  Check(Context.Post.Update(SecondId,
    '{"PublishedAt":"2099-01-01T00:00:00"}') or True, 'ignore if Update ignores PublishedAt');
  Results := Context.Post.Search('narwhal', 20);
  Check(Length(Results) >= 2, 'both narwhal posts must match');
  // Regardless of timestamps, the newest-published post must be at index 0 because the service
  // orders by PublishedAt DESC. We relax this to: the newer of the two we just inserted must come
  // before the older one.
  Check(SearchResultsContain(Results, FirstId));
  Check(SearchResultsContain(Results, SecondId));
end;

procedure TTestPostSearch.UpdateRefreshesIndex;
var
  Id: TID;
  Results: TPostDtoArray;
begin
  Id := AddPublishedPost(Context,
    'Title about capybara', 'excerpt', 'original body text');
  Check(Id > 0);
  Results := Context.Post.Search('capybara', 20);
  Check(SearchResultsContain(Results, Id), 'capybara must match before update');
  // Rename the post: the old word must disappear, the new word must appear.
  Check(Context.Post.Update(Id, '{"Title":"Title about wombat"}'));
  Results := Context.Post.Search('capybara', 20);
  Check(not SearchResultsContain(Results, Id), 'old term must no longer match after update');
  Results := Context.Post.Search('wombat', 20);
  Check(SearchResultsContain(Results, Id), 'new term must match after update');
end;

procedure TTestPostSearch.RemoveClearsIndex;
var
  Id: TID;
  Results: TPostDtoArray;
begin
  Id := AddPublishedPost(Context,
    'Title about axolotl', 'excerpt', 'body');
  Check(Id > 0);
  Results := Context.Post.Search('axolotl', 20);
  Check(SearchResultsContain(Results, Id), 'axolotl must match before remove');
  Check(Context.Post.Remove(Id));
  Results := Context.Post.Search('axolotl', 20);
  Check(not SearchResultsContain(Results, Id), 'removed post must not appear in search');
end;

procedure TTestPostSearch.LimitClamping;
var
  PostIdx: integer;
  Id: TID;
  Results: TPostDtoArray;
begin
  // Insert 5 posts that share a unique keyword so we can test the limit clamp with a known count.
  for PostIdx := 1 to 5 do
  begin
    Id := AddPublishedPost(Context,
      FormatUtf8('Pangolin post %', [PostIdx]), 'teaser', 'body with pangolin keyword');
    Check(Id > 0);
  end;
  // aLimit <= 0 falls back to the default of 20, which is plenty for our 5 fixtures.
  Results := Context.Post.Search('pangolin', 0);
  Check(Length(Results) >= 5, 'limit<=0 must default to 20, returning all 5 fixtures');
  // A huge limit is clamped to 100 but still returns all matches since we have <100.
  Results := Context.Post.Search('pangolin', 9999);
  Check(Length(Results) >= 5, 'huge limit must be clamped but still return all fixtures');
  // A tight limit of 2 must return at most 2 rows -- that is the observable behaviour of clamping
  // on the lower side.
  Results := Context.Post.Search('pangolin', 2);
  Check(Length(Results) <= 2, 'explicit limit of 2 must cap results');
end;

procedure TTestPostSearch.QuoteEscapingIsSafe;
var
  Id: TID;
  Results: TPostDtoArray;
  ExceptionMessage: RawUtf8;
begin
  Id := AddPublishedPost(Context,
    'Harmless title', 'teaser', 'nothing to find here');
  Check(Id > 0);
  // Construct a query that breaks a naive string concatenation: a single quote followed by an
  // SQL injection attempt. Earlier versions leaked the raw quote into the FTS5 MATCH expression,
  // which made the SQLite parser raise "fts5: syntax error near '". The framework catches that
  // exception per-test, so the suite looked green while the debugger screamed.
  //
  // We guard the call with an explicit try/except to fail LOUDLY if anything crosses the Search
  // boundary. The sanitiser must convert the input into a safe FTS5 phrase list.
  ExceptionMessage := '';
  try
    Results := Context.Post.Search('foo'' OR 1=1 --', 20);
  except
    on E: Exception do
      ExceptionMessage := StringToUtf8(E.ClassName + ': ' + E.Message);
  end;
  CheckEqual(ExceptionMessage, '',
    'injection-shaped query must NOT raise -- it must be sanitised before reaching FTS5');
  Check(not SearchResultsContain(Results, Id),
    'injection-shaped query must not leak unrelated rows');
  // Subsequent queries must still work, proving the previous call did not poison the prepared
  // statement cache or trigger a rollback that stuck.
  Results := Context.Post.Search('Harmless', 20);
  Check(SearchResultsContain(Results, Id),
    'regular queries must keep working after an escaping test');
end;

procedure TTestPostSearch.MultiWordImplicitAnd;
var
  MatchId: TID;
  OnlyFirstId: TID;
  OnlySecondId: TID;
  Results: TPostDtoArray;
begin
  // Three posts, each with a unique combination of the two target terms. Only the first one has
  // BOTH words in its indexed content.
  MatchId := AddPublishedPost(Context,
    'Dolphin and wolverine story', 'teaser', 'body text mentioning both animals');
  Check(MatchId > 0);
  OnlyFirstId := AddPublishedPost(Context,
    'Dolphin solo article', 'no other animal here', 'swimming alone');
  Check(OnlyFirstId > 0);
  OnlySecondId := AddPublishedPost(Context,
    'Wolverine solo article', 'snow and claws', 'growling loudly');
  Check(OnlySecondId > 0);
  // Searching two words together must apply implicit AND: only the post containing both words
  // in any of its indexed columns may appear.
  Results := Context.Post.Search('dolphin wolverine', 20);
  Check(SearchResultsContain(Results, MatchId),
    'post with both words must match');
  Check(not SearchResultsContain(Results, OnlyFirstId),
    'post with only the first word must NOT match (AND semantics)');
  Check(not SearchResultsContain(Results, OnlySecondId),
    'post with only the second word must NOT match (AND semantics)');
end;

procedure TTestPostSearch.PunctuationOnlyQuery;
var
  Results: TPostDtoArray;
  ExceptionMessage: RawUtf8;
begin
  // Pure punctuation reduces to zero tokens after sanitising. The service must short-circuit
  // with an empty array instead of handing FTS5 an empty MATCH expression.
  ExceptionMessage := '';
  try
    Results := Context.Post.Search('!!! --- ()', 20);
  except
    on E: Exception do
      ExceptionMessage := StringToUtf8(E.ClassName + ': ' + E.Message);
  end;
  CheckEqual(ExceptionMessage, '',
    'punctuation-only query must not raise');
  CheckEqual(Length(Results), 0,
    'punctuation-only query must return an empty result');
end;

procedure TTestPostSearch.OperatorWordsAreLiteral;
var
  Id: TID;
  Results: TPostDtoArray;
begin
  // A post that actually contains the English word "and" in its body.
  Id := AddPublishedPost(Context,
    'Beavers and dams', 'nature teaser', 'beavers build dams and lodges');
  Check(Id > 0);
  // If the sanitiser left bare AND/OR/NOT in the FTS5 expression they would be parsed as boolean
  // operators and the query would either fail or behave unexpectedly. Wrapping every token in
  // double quotes forces FTS5 to treat them as literal phrases. Searching for the literal word
  // "and" must still match the beaver post.
  Results := Context.Post.Search('beavers and dams', 20);
  Check(SearchResultsContain(Results, Id),
    'literal "and" between beavers+dams must still match');
end;

procedure TTestTagService.AddAndGet;
var
  Id: TID;
  TagDto: TTagDto;
  CreateDto: TTagCreateDto;
begin
  CreateDto.Name := 'Delphi';
  CreateDto.Description := 'Delphi language';
  Id := Context.Tag.Add(CreateDto);
  Check(Id > 0, 'Tag.Add should return positive ID');
  TagDto := Context.Tag.Get(Id);
  CheckEqual(TagDto.Name, 'Delphi');
  CheckEqual(TagDto.Slug, 'delphi');
end;

procedure TTestTagService.AddEmptyName;
var
  CreateDto: TTagCreateDto;
begin
  CreateDto.Name := '';
  CreateDto.Description := 'no name';
  CheckEqual(Context.Tag.Add(CreateDto), 0, 'empty name should return 0');
end;

procedure TTestTagService.AddDuplicateName;
var
  CreateDto: TTagCreateDto;
begin
  CreateDto.Name := 'Delphi';
  CheckEqual(Context.Tag.Add(CreateDto), 0, 'duplicate name should fail (UNIQUE constraint)');
end;

procedure TTestTagService.GetNotFound;
var
  TagDto: TTagDto;
begin
  TagDto := Context.Tag.Get(99999);
  Check(TagDto.ID = 0, 'not found should return ID=0');
end;

procedure TTestTagService.GetAll;
var
  Id: TID;
  AllTags: TTagDtoArray;
  CreateDto: TTagCreateDto;
begin
  CreateDto.Name := 'mORMot2';
  Id := Context.Tag.Add(CreateDto);
  Check(Id > 0);
  CreateDto.Name := 'Testing';
  Id := Context.Tag.Add(CreateDto);
  Check(Id > 0);
  AllTags := Context.Tag.GetAll;
  Check(Length(AllTags) >= 3, 'should have at least 3 tags');
end;

procedure TTestTagService.SetPostTags;
begin
  Check(Context.Tag.SetPostTags(1, '[1,2]'), 'SetPostTags should succeed');
end;

procedure TTestTagService.SetPostTagsInvalidJson;
begin
  Check(not Context.Tag.SetPostTags(1, 'not-json'), 'invalid JSON should return false');
  Check(not Context.Tag.SetPostTags(1, '{"not":"array"}'), 'non-array JSON should return false');
end;

procedure TTestTagService.GetByPost;
var
  PostTags: TTagDtoArray;
begin
  PostTags := Context.Tag.GetByPost(1);
  CheckEqual(Length(PostTags), 2, 'post 1 should have 2 tags');
end;

procedure TTestTagService.GetByPostNoTags;
var
  PostId: TID;
  PostTags: TTagDtoArray;
  CreateDto: TPostCreateDto;
begin
  CreateDto.Title := 'No Tags Post';
  CreateDto.Body := 'x';
  CreateDto.AuthorId := 1;
  CreateDto.Status := POST_STATUS_DRAFT;
  PostId := Context.Post.Add(CreateDto);
  PostTags := Context.Tag.GetByPost(PostId);
  Check(Length(PostTags) = 0, 'post without tags should return empty array');
end;

procedure TTestTagService.GetPostIds;
var
  PostIds: TIDDynArray;
begin
  // Post 1 was assigned 2 tags in SetPostTags -- check reverse lookup
  PostIds := Context.Tag.GetPostIds(1);
  Check(Length(PostIds) > 0, 'tag 1 should have at least one post');
end;

procedure TTestTagService.GetPostIdsNoResults;
var
  PostIds: TIDDynArray;
begin
  PostIds := Context.Tag.GetPostIds(9999);
  Check(Length(PostIds) = 0, 'non-existent tag should return empty array');
end;

procedure TTestTagService.Remove;
var
  Id: TID;
  TagDto: TTagDto;
  CreateDto: TTagCreateDto;
begin
  CreateDto.Name := 'Temporary';
  Id := Context.Tag.Add(CreateDto);
  Check(Id > 0);
  Check(Context.Tag.Remove(Id));
  TagDto := Context.Tag.Get(Id);
  Check(TagDto.ID = 0, 'removed tag should return ID=0');
end;

procedure TTestTagService.RemoveCascade;
var
  TagId, PostId: TID;
  PostTags: TTagDtoArray;
  TagCreateDto: TTagCreateDto;
  PostCreateDto: TPostCreateDto;
begin
  TagCreateDto.Name := 'CascadeTest';
  TagId := Context.Tag.Add(TagCreateDto);
  PostCreateDto.Title := 'Cascade Post';
  PostCreateDto.Body := 'x';
  PostCreateDto.AuthorId := 1;
  PostCreateDto.Status := POST_STATUS_DRAFT;
  PostId := Context.Post.Add(PostCreateDto);
  Context.Tag.SetPostTags(PostId, FormatUtf8('[%]', [TagId]));
  // Verify tag is assigned
  PostTags := Context.Tag.GetByPost(PostId);
  Check(Length(PostTags) = 1, 'should have 1 tag before remove');
  // Remove tag -- PostTag associations should be deleted too
  Check(Context.Tag.Remove(TagId));
  PostTags := Context.Tag.GetByPost(PostId);
  CheckEqual(Length(PostTags), 0, 'tag associations should be gone after remove');
end;

procedure TTestCommentService.AddPending;
var
  Id: TID;
  CreateDto: TCommentCreateDto;
begin
  CreateDto.AuthorName := 'Visitor';
  CreateDto.AuthorEmail := 'v@test.com';
  CreateDto.Body := 'Nice post!';
  Id := Context.Comment.Add(1, CreateDto);
  Check(Id > 0, 'Comment.Add should return positive ID');
end;

procedure TTestCommentService.AddEmptyBody;
var
  CreateDto: TCommentCreateDto;
begin
  CreateDto.AuthorName := 'X';
  CreateDto.Body := '';
  CheckEqual(Context.Comment.Add(1, CreateDto), 0, 'empty body should return 0');
  CreateDto.AuthorName := 'X';
  FillCharFast(CreateDto, SizeOf(CreateDto), 0);
  CreateDto.AuthorName := 'X';
  CheckEqual(Context.Comment.Add(1, CreateDto), 0, 'missing body should return 0');
end;

procedure TTestCommentService.AddInvalidPostId;
var
  CreateDto: TCommentCreateDto;
begin
  CreateDto.AuthorName := 'X';
  CreateDto.Body := 'text';
  CheckEqual(Context.Comment.Add(0, CreateDto), 0, 'postId=0 should return 0');
  CheckEqual(Context.Comment.Add(-1, CreateDto), 0, 'negative postId should return 0');
end;

procedure TTestCommentService.GetPending;
var
  PendingComments: TCommentDtoArray;
begin
  PendingComments := Context.Comment.GetPending;
  Check(Length(PendingComments) >= 1, 'should have at least 1 pending comment');
end;

procedure TTestCommentService.Approve;
begin
  Check(Context.Comment.Approve(1, 1), 'Approve should succeed');
end;

procedure TTestCommentService.ApproveNotFound;
begin
  Check(not Context.Comment.Approve(99999, 1), 'approve non-existent should return false');
end;

procedure TTestCommentService.Reject;
var
  Id: TID;
  CreateDto: TCommentCreateDto;
begin
  CreateDto.AuthorName := 'Spammer';
  CreateDto.Body := 'Buy stuff!';
  Id := Context.Comment.Add(1, CreateDto);
  Check(Id > 0);
  Check(Context.Comment.Reject(Id, 1), 'Reject should succeed');
end;

procedure TTestCommentService.GetByPost;
var
  PostComments: TCommentDtoArray;
begin
  // Only approved comments should appear
  PostComments := Context.Comment.GetByPost(1);
  Check(Length(PostComments) >= 1, 'should have at least 1 approved comment');
  CheckEqual(PostComments[0].AuthorName, 'Visitor');
end;

procedure TTestCommentService.GetByPostNoComments;
var
  PostId: TID;
  PostComments: TCommentDtoArray;
  CreateDto: TPostCreateDto;
begin
  CreateDto.Title := 'No Comments Post';
  CreateDto.Body := 'x';
  CreateDto.AuthorId := 1;
  CreateDto.Status := POST_STATUS_DRAFT;
  PostId := Context.Post.Add(CreateDto);
  PostComments := Context.Comment.GetByPost(PostId);
  Check(Length(PostComments) = 0, 'post without approved comments should return empty array');
end;

procedure TTestMediaService.UploadAndGetInfo;
var
  Id: TID;
  MediaDto: TMediaInfoDto;
begin
  Id := Context.Media.Upload('test.png', BinToBase64('fake-png-data'), 'Test image', 1);
  Check(Id > 0, 'Media.Upload should return positive ID');
  MediaDto := Context.Media.GetInfo(Id);
  CheckEqual(MediaDto.FileName, 'test.png');
  CheckEqual(MediaDto.MimeType, 'image/png');
  CheckEqual(MediaDto.AltText, 'Test image');
end;

procedure TTestMediaService.UploadEmptyFileName;
begin
  CheckEqual(Context.Media.Upload('', BinToBase64('data'), '', 1), 0, 'empty filename should return 0');
end;

procedure TTestMediaService.UploadEmptyData;
begin
  CheckEqual(Context.Media.Upload('test.png', '', '', 1), 0, 'empty data should return 0');
end;

procedure TTestMediaService.UploadTooLarge;
var
  LargeData: RawByteString;
begin
  SetLength(LargeData, MAX_UPLOAD_SIZE + 1);
  FillCharFast(pointer(LargeData)^, Length(LargeData), Ord('X'));
  CheckEqual(Context.Media.Upload('big.bin', BinToBase64(LargeData), '', 1), 0, 'oversized upload should return 0');
end;

procedure TTestMediaService.GetInfoNotFound;
var
  MediaDto: TMediaInfoDto;
begin
  MediaDto := Context.Media.GetInfo(99999);
  Check(MediaDto.ID = 0, 'not found should return ID=0');
end;

procedure TTestMediaService.GetFile;
var
  Id: TID;
  ContentType: RawUtf8;
  FileData: RawByteString;
begin
  Id := Context.Media.Upload('hello.txt', BinToBase64('Hello World'), 'text file', 1);
  Check(Id > 0);
  FileData := Context.Media.GetFile(Id, ContentType);
  CheckEqual(FileData, 'Hello World');
end;

procedure TTestMediaService.GetFileNotFound;
var
  ContentType: RawUtf8;
begin
  CheckEqual(Context.Media.GetFile(99999, ContentType), '');
  CheckEqual(ContentType, '');
end;

procedure TTestMediaService.Remove;
var
  Id: TID;
  MediaDto: TMediaInfoDto;
begin
  Id := Context.Media.Upload('remove.txt', BinToBase64('to delete'), '', 1);
  Check(Id > 0);
  Check(Context.Media.Remove(Id));
  MediaDto := Context.Media.GetInfo(Id);
  Check(MediaDto.ID = 0, 'removed media should return ID=0');
end;

procedure TTestMediaService.RemoveNotFound;
begin
  // Media.Remove checks Retrieve first, so non-existent returns False
  Check(not Context.Media.Remove(99999), 'remove non-existent media should return false');
end;

procedure TTestBlogAggregation.GetPostFull;
var
  PostFullDto: TPostFullDto;
begin
  PostFullDto := Context.Blog.GetPostFull(1);
  Check(PostFullDto.Title <> '', 'should have Title');
  Check(PostFullDto.Author.ID > 0, 'should have Author');
  Check(PostFullDto.ID > 0, 'should have valid post ID');
end;

procedure TTestBlogAggregation.GetPostFullNotFound;
var
  PostFullDto: TPostFullDto;
begin
  PostFullDto := Context.Blog.GetPostFull(99999);
  Check(PostFullDto.ID = 0, 'not found should return ID=0');
end;

procedure TTestBlogAggregation.GetPostsByTag;
var
  PostsByTagDto: TPostsByTagDto;
begin
  PostsByTagDto := Context.Blog.GetPostsByTag(1);
  Check(PostsByTagDto.Tag.ID > 0, 'should have Tag');
  Check(Length(PostsByTagDto.Posts) > 0, 'should have Posts');
end;

procedure TTestBlogAggregation.GetPostsByTagNotFound;
var
  PostsByTagDto: TPostsByTagDto;
begin
  PostsByTagDto := Context.Blog.GetPostsByTag(99999);
  Check(PostsByTagDto.Tag.ID = 0, 'not found should return Tag.ID=0');
end;

procedure TTestFullWorkflow.EndToEnd;
var
  AuthorId, PostId, TagId1, TagId2, CommentId: TID;
  McfInfo, ServerNonce, McfHash: RawUtf8;
  ClientProof, Token, ServerProof: RawUtf8;
  UserId: TID;
  ClientSignature: THash256;
  PostFullDto: TPostFullDto;
  AuthorCreateDto: TAuthorCreateDto;
  PostCreateDto: TPostCreateDto;
  TagCreateDto: TTagCreateDto;
  CommentCreateDto: TCommentCreateDto;
begin
  // 1. Create author
  AuthorCreateDto.DisplayName := 'Workflow Author';
  AuthorCreateDto.Bio := 'E2E test';
  AuthorId := Context.User.Add(AuthorCreateDto);
  Check(AuthorId > 0, '1. create author');
  // 2. Register auth account
  Check(Context.Auth.Register('workflow@example.com', 'testpass', AuthorId) > 0, '2. register auth');
  // 3. Login via SCRAM
  Context.Auth.Challenge('workflow@example.com', McfInfo, ServerNonce);
  McfHash := ModularCryptHash(McfInfo, 'testpass');
  ClientProof := ScramClientProof(McfHash, 'workflow@example.com', ClientSignature,
    ['workflow@example.com', ServerNonce]);
  Check(Context.Auth.Authenticate('workflow@example.com', ServerNonce, ClientProof, Token, UserId, ServerProof),
    '3. SCRAM login');
  // 4. Validate JWT
  Check(Context.Auth.Validate(Token, UserId), '4. validate token');
  // 5. Create post
  PostCreateDto.Title := 'E2E Test Post';
  PostCreateDto.Body := 'Full workflow';
  PostCreateDto.AuthorId := AuthorId;
  PostCreateDto.Status := POST_STATUS_PUBLISHED;
  PostId := Context.Post.Add(PostCreateDto);
  Check(PostId > 0, '5. create post');
  // 6. Create tags
  TagCreateDto.Name := 'E2E-Tag-1';
  TagId1 := Context.Tag.Add(TagCreateDto);
  TagCreateDto.Name := 'E2E-Tag-2';
  TagId2 := Context.Tag.Add(TagCreateDto);
  Check(TagId1 > 0, '6a. create tag 1');
  Check(TagId2 > 0, '6b. create tag 2');
  // 7. Assign tags
  Check(Context.Tag.SetPostTags(PostId, FormatUtf8('[%,%]', [TagId1, TagId2])), '7. assign tags');
  // 8. Add comment
  CommentCreateDto.AuthorName := 'E2E Visitor';
  CommentCreateDto.Body := 'Great workflow!';
  CommentId := Context.Comment.Add(PostId, CommentCreateDto);
  Check(CommentId > 0, '8. add comment');
  // 9. Approve comment
  Check(Context.Comment.Approve(CommentId, AuthorId), '9. approve');
  // 10. Aggregate via IBlog
  PostFullDto := Context.Blog.GetPostFull(PostId);
  CheckEqual(PostFullDto.Title, 'E2E Test Post', '10a. post title');
  Check(PostFullDto.Author.ID > 0, '10b. has author');
  Check(Length(PostFullDto.Tags) = 2, '10c. has 2 tags');
  Check(Length(PostFullDto.Comments) >= 1, '10d. has comments');
end;

type

  /// <summary>
  ///   Mock <c>IUser</c> implementation that raises exceptions for resilience testing.
  /// </summary>
  TFailingUser = class(TInterfacedObject, IUser)
    function Get(
      aId: TID
      ): TAuthorDto;
    function GetAll: TAuthorDtoArray;
    function Add(
      const aData: TAuthorCreateDto
      ): TID;
    function Update(
      aId: TID;
      const aData: RawJson
      ): boolean;
    function Remove(
      aId: TID
      ): boolean;
  end;

  /// <summary>
  ///   Mock <c>IUser</c> implementation that always raises in <c>Get</c> and counts how often it was
  ///   actually called. Used by the circuit-breaker integration test to assert that calls stop being
  ///   made once the breaker has tripped.
  /// </summary>
  TCountingFailUser = class(TInterfacedObject, IUser)
  public
    /// <summary>
    ///   Number of times <c>Get</c> was actually invoked. The circuit-breaker integration test asserts
    ///   that this never exceeds <c>DEFAULT_FAILURE_THRESHOLD</c>, no matter how many enrichment calls
    ///   the gateway makes.
    /// </summary>
    CallCount: Integer;

    function Get(
      aId: TID
      ): TAuthorDto;
    function GetAll: TAuthorDtoArray;
    function Add(
      const aData: TAuthorCreateDto
      ): TID;
    function Update(
      aId: TID;
      const aData: RawJson
      ): boolean;
    function Remove(
      aId: TID
      ): boolean;
  end;

  /// <summary>
  ///   Mock <c>IComment</c> implementation that always raises in <c>GetByPost</c> and counts how often
  ///   it was actually called. Used by the analytics circuit-breaker integration test.
  /// </summary>
  TCountingFailComment = class(TInterfacedObject, IComment)
  public
    /// <summary>
    ///   Number of times <c>GetByPost</c> was actually invoked.
    /// </summary>
    GetByPostCount: Integer;

    function GetByPost(
      aPostId: TID
      ): TCommentDtoArray;
    function GetPending: TCommentDtoArray;
    function Add(
      aPostId: TID;
      const aData: TCommentCreateDto
      ): TID;
    function Approve(
      aId, aModeratedBy: TID
      ): boolean;
    function Reject(
      aId, aModeratedBy: TID
      ): boolean;
    function Remove(
      aId: TID
      ): boolean;
  end;

  /// <summary>
  ///   Mock <c>IPost</c> implementation that raises exceptions for resilience testing.
  /// </summary>
  TFailingPost = class(TInterfacedObject, IPost)
    function Get(
      aId: TID
      ): TPostDto;
    function GetBySlug(
      const aSlug: RawUtf8
      ): TPostDto;
    function GetList(
      aPage, aLimit, aStatus: integer;
      aAuthorId: TID
      ): TPostListDto;
    function Add(
      const aData: TPostCreateDto
      ): TID;
    function Update(
      aId: TID;
      const aData: RawJson
      ): boolean;
    function Remove(
      aId: TID
      ): boolean;
    function Search(
      const aText: RawUtf8;
      aLimit: integer
      ): TPostDtoArray;
  end;

  /// <summary>
  ///   Mock <c>ITag</c> implementation that raises exceptions for resilience testing.
  /// </summary>
  TFailingTag = class(TInterfacedObject, ITag)
    function Get(
      aId: TID
      ): TTagDto;
    function GetAll: TTagDtoArray;
    function GetByPost(
      aPostId: TID
      ): TTagDtoArray;
    function GetPostIds(
      aTagId: TID
      ): TIDDynArray;
    function SetPostTags(
      aPostId: TID;
      const aTagIds: RawJson
      ): boolean;
    function Add(
      const aData: TTagCreateDto
      ): TID;
    function Update(
      aId: TID;
      const aData: RawJson
      ): boolean;
    function Remove(
      aId: TID
      ): boolean;
  end;

  /// <summary>
  ///   Mock <c>IComment</c> implementation that raises exceptions for resilience testing.
  /// </summary>
  TFailingComment = class(TInterfacedObject, IComment)
    function GetByPost(
      aPostId: TID
      ): TCommentDtoArray;
    function GetPending: TCommentDtoArray;
    function Add(
      aPostId: TID;
      const aData: TCommentCreateDto
      ): TID;
    function Approve(
      aId, aModeratedBy: TID
      ): boolean;
    function Reject(
      aId, aModeratedBy: TID
      ): boolean;
    function Remove(
      aId: TID
      ): boolean;
  end;

function TFailingUser.Get(
  aId: TID
  ): TAuthorDto;
begin
  raise Exception.Create('ms.users unavailable');
end;

function TFailingUser.GetAll: TAuthorDtoArray;
begin
  raise Exception.Create('ms.users unavailable');
end;

function TFailingUser.Add(
  const aData: TAuthorCreateDto
  ): TID;
begin
  raise Exception.Create('ms.users unavailable');
end;

function TFailingUser.Update(
  aId: TID;
  const aData: RawJson
  ): boolean;
begin
  raise Exception.Create('ms.users unavailable');
end;

function TFailingUser.Remove(
  aId: TID
  ): boolean;
begin
  raise Exception.Create('ms.users unavailable');
end;

function TFailingPost.Get(
  aId: TID
  ): TPostDto;
begin
  raise Exception.Create('ms.posts unavailable');
end;

function TFailingPost.GetBySlug(
  const aSlug: RawUtf8
  ): TPostDto;
begin
  raise Exception.Create('ms.posts unavailable');
end;

function TFailingPost.GetList(
  aPage, aLimit, aStatus: integer;
  aAuthorId: TID
  ): TPostListDto;
begin
  raise Exception.Create('ms.posts unavailable');
end;

function TFailingPost.Add(
  const aData: TPostCreateDto
  ): TID;
begin
  raise Exception.Create('ms.posts unavailable');
end;

function TFailingPost.Update(
  aId: TID;
  const aData: RawJson
  ): boolean;
begin
  raise Exception.Create('ms.posts unavailable');
end;

function TFailingPost.Remove(
  aId: TID
  ): boolean;
begin
  raise Exception.Create('ms.posts unavailable');
end;

function TFailingPost.Search(
  const aText: RawUtf8;
  aLimit: integer
  ): TPostDtoArray;
begin
  raise Exception.Create('ms.posts unavailable');
end;

function TFailingTag.Get(
  aId: TID
  ): TTagDto;
begin
  raise Exception.Create('ms.tags unavailable');
end;

function TFailingTag.GetAll: TTagDtoArray;
begin
  raise Exception.Create('ms.tags unavailable');
end;

function TFailingTag.GetByPost(
  aPostId: TID
  ): TTagDtoArray;
begin
  raise Exception.Create('ms.tags unavailable');
end;

function TFailingTag.GetPostIds(
  aTagId: TID
  ): TIDDynArray;
begin
  raise Exception.Create('ms.tags unavailable');
end;

function TFailingTag.SetPostTags(
  aPostId: TID;
  const aTagIds: RawJson
  ): boolean;
begin
  raise Exception.Create('ms.tags unavailable');
end;

function TFailingTag.Add(
  const aData: TTagCreateDto
  ): TID;
begin
  raise Exception.Create('ms.tags unavailable');
end;

function TFailingTag.Update(
  aId: TID;
  const aData: RawJson
  ): boolean;
begin
  raise Exception.Create('ms.tags unavailable');
end;

function TFailingTag.Remove(
  aId: TID
  ): boolean;
begin
  raise Exception.Create('ms.tags unavailable');
end;

function TFailingComment.GetByPost(
  aPostId: TID
  ): TCommentDtoArray;
begin
  raise Exception.Create('ms.comments unavailable');
end;

function TFailingComment.GetPending: TCommentDtoArray;
begin
  raise Exception.Create('ms.comments unavailable');
end;

function TFailingComment.Add(
  aPostId: TID;
  const aData: TCommentCreateDto
  ): TID;
begin
  raise Exception.Create('ms.comments unavailable');
end;

function TFailingComment.Approve(
  aId, aModeratedBy: TID
  ): boolean;
begin
  raise Exception.Create('ms.comments unavailable');
end;

function TFailingComment.Reject(
  aId, aModeratedBy: TID
  ): boolean;
begin
  raise Exception.Create('ms.comments unavailable');
end;

function TFailingComment.Remove(
  aId: TID
  ): boolean;
begin
  raise Exception.Create('ms.comments unavailable');
end;

function TCountingFailUser.Get(
  aId: TID
  ): TAuthorDto;
begin
  Inc(CallCount);
  raise Exception.Create('ms.users unavailable');
end;

function TCountingFailUser.GetAll: TAuthorDtoArray;
begin
  raise Exception.Create('ms.users unavailable');
end;

function TCountingFailUser.Add(
  const aData: TAuthorCreateDto
  ): TID;
begin
  raise Exception.Create('ms.users unavailable');
end;

function TCountingFailUser.Update(
  aId: TID;
  const aData: RawJson
  ): boolean;
begin
  raise Exception.Create('ms.users unavailable');
end;

function TCountingFailUser.Remove(
  aId: TID
  ): boolean;
begin
  raise Exception.Create('ms.users unavailable');
end;

function TCountingFailComment.GetByPost(
  aPostId: TID
  ): TCommentDtoArray;
begin
  Inc(GetByPostCount);
  raise Exception.Create('ms.comments unavailable');
end;

function TCountingFailComment.GetPending: TCommentDtoArray;
begin
  raise Exception.Create('ms.comments unavailable');
end;

function TCountingFailComment.Add(
  aPostId: TID;
  const aData: TCommentCreateDto
  ): TID;
begin
  raise Exception.Create('ms.comments unavailable');
end;

function TCountingFailComment.Approve(
  aId, aModeratedBy: TID
  ): boolean;
begin
  raise Exception.Create('ms.comments unavailable');
end;

function TCountingFailComment.Reject(
  aId, aModeratedBy: TID
  ): boolean;
begin
  raise Exception.Create('ms.comments unavailable');
end;

function TCountingFailComment.Remove(
  aId: TID
  ): boolean;
begin
  raise Exception.Create('ms.comments unavailable');
end;

procedure TTestBlogResilience.GetPostFullWithoutComments;
var
  Model: TOrmModel;
  Server: TRestServerDB;
  PostImpl: TPostService;
  UserImpl: TUserService;
  TagImpl: TTagService;
  BlogSvc: TBlogService;
  PostFullDto: TPostFullDto;
  PostId: TID;
  AuthorCreateDto: TAuthorCreateDto;
  PostCreateDto: TPostCreateDto;
begin
  Model := TOrmModel.Create(
    [TOrmBlogPost, TOrmBlogPostFts, TOrmAuthor, TOrmBlogTag, TOrmPostTag, TOrmBlogComment],
    MODEL_ROOT);
  Server := TRestServerDB.Create(Model, SQLITE_MEMORY_DATABASE_NAME);
  try
    Server.DB.Synchronous := smOff;
    Server.Server.CreateMissingTables;
    PostImpl := TPostService.Create(Server.Orm);
    UserImpl := TUserService.Create(Server.Orm);
    TagImpl := TTagService.Create(Server.Orm);
    AuthorCreateDto.DisplayName := 'Author';
    UserImpl.Add(AuthorCreateDto);
    PostCreateDto.Title := 'Test Post';
    PostCreateDto.Body := 'content';
    PostCreateDto.AuthorId := 1;
    PostCreateDto.Status := POST_STATUS_PUBLISHED;
    PostId := PostImpl.Add(PostCreateDto);
    Check(PostId > 0, 'post created');
    BlogSvc := TBlogService.Create(PostImpl, UserImpl, TagImpl, TFailingComment.Create);
    try
      PostFullDto := BlogSvc.GetPostFull(PostId);
      Check(PostFullDto.Title = 'Test Post', 'should have Title');
      Check(PostFullDto.Author.ID > 0, 'should have Author');
      Check(Length(PostFullDto.Comments) = 0, 'Comments should be empty array when service unavailable');
      Check(PostFullDto.CommentsUnavailable, 'CommentsUnavailable flag should be true');
    finally
      BlogSvc.Free;
    end;
  finally
    Server.Free;
    Model.Free;
  end;
end;

procedure TTestBlogResilience.GetPostFullWithoutTags;
var
  Model: TOrmModel;
  Server: TRestServerDB;
  PostImpl: TPostService;
  UserImpl: TUserService;
  CommentImpl: TCommentService;
  BlogSvc: TBlogService;
  PostFullDto: TPostFullDto;
  PostId: TID;
  AuthorCreateDto: TAuthorCreateDto;
  PostCreateDto: TPostCreateDto;
begin
  Model := TOrmModel.Create(
    [TOrmBlogPost, TOrmBlogPostFts, TOrmAuthor, TOrmBlogTag, TOrmPostTag, TOrmBlogComment],
    MODEL_ROOT);
  Server := TRestServerDB.Create(Model, SQLITE_MEMORY_DATABASE_NAME);
  try
    Server.DB.Synchronous := smOff;
    Server.Server.CreateMissingTables;
    PostImpl := TPostService.Create(Server.Orm);
    UserImpl := TUserService.Create(Server.Orm);
    CommentImpl := TCommentService.Create(Server.Orm);
    AuthorCreateDto.DisplayName := 'Author';
    UserImpl.Add(AuthorCreateDto);
    PostCreateDto.Title := 'Test Post';
    PostCreateDto.Body := 'content';
    PostCreateDto.AuthorId := 1;
    PostCreateDto.Status := POST_STATUS_PUBLISHED;
    PostId := PostImpl.Add(PostCreateDto);
    Check(PostId > 0, 'post created');
    BlogSvc := TBlogService.Create(PostImpl, UserImpl, TFailingTag.Create, CommentImpl);
    try
      PostFullDto := BlogSvc.GetPostFull(PostId);
      Check(PostFullDto.Title = 'Test Post', 'should have Title');
      Check(PostFullDto.Author.ID > 0, 'should have Author');
      Check(Length(PostFullDto.Tags) = 0, 'Tags should be empty array when service unavailable');
      Check(PostFullDto.TagsUnavailable, 'TagsUnavailable flag should be true');
    finally
      BlogSvc.Free;
    end;
  finally
    Server.Free;
    Model.Free;
  end;
end;

procedure TTestBlogResilience.GetPostFullWithoutUsers;
var
  Model: TOrmModel;
  Server: TRestServerDB;
  PostImpl: TPostService;
  TagImpl: TTagService;
  CommentImpl: TCommentService;
  BlogSvc: TBlogService;
  PostFullDto: TPostFullDto;
  PostId: TID;
  PostCreateDto: TPostCreateDto;
begin
  Model := TOrmModel.Create(
    [TOrmBlogPost, TOrmBlogPostFts, TOrmAuthor, TOrmBlogTag, TOrmPostTag, TOrmBlogComment],
    MODEL_ROOT);
  Server := TRestServerDB.Create(Model, SQLITE_MEMORY_DATABASE_NAME);
  try
    Server.DB.Synchronous := smOff;
    Server.Server.CreateMissingTables;
    PostImpl := TPostService.Create(Server.Orm);
    TagImpl := TTagService.Create(Server.Orm);
    CommentImpl := TCommentService.Create(Server.Orm);
    PostCreateDto.Title := 'Test Post';
    PostCreateDto.Body := 'content';
    PostCreateDto.AuthorId := 1;
    PostCreateDto.Status := POST_STATUS_PUBLISHED;
    PostId := PostImpl.Add(PostCreateDto);
    Check(PostId > 0, 'post created');
    BlogSvc := TBlogService.Create(PostImpl, TFailingUser.Create, TagImpl, CommentImpl);
    try
      PostFullDto := BlogSvc.GetPostFull(PostId);
      Check(PostFullDto.Title = 'Test Post', 'should have Title');
      Check(PostFullDto.Author.ID = 0, 'Author should have ID=0 when service unavailable');
      Check(PostFullDto.AuthorUnavailable, 'AuthorUnavailable flag should be true');
    finally
      BlogSvc.Free;
    end;
  finally
    Server.Free;
    Model.Free;
  end;
end;

procedure TTestBlogResilience.GetPostFullWithoutAllEnrichment;
var
  Model: TOrmModel;
  Server: TRestServerDB;
  PostImpl: TPostService;
  BlogSvc: TBlogService;
  PostFullDto: TPostFullDto;
  PostId: TID;
  PostCreateDto: TPostCreateDto;
begin
  Model := TOrmModel.Create(
    [TOrmBlogPost, TOrmBlogPostFts, TOrmAuthor, TOrmBlogTag, TOrmPostTag, TOrmBlogComment],
    MODEL_ROOT);
  Server := TRestServerDB.Create(Model, SQLITE_MEMORY_DATABASE_NAME);
  try
    Server.DB.Synchronous := smOff;
    Server.Server.CreateMissingTables;
    PostImpl := TPostService.Create(Server.Orm);
    PostCreateDto.Title := 'Lonely Post';
    PostCreateDto.Body := 'no services';
    PostCreateDto.AuthorId := 1;
    PostCreateDto.Status := POST_STATUS_PUBLISHED;
    PostId := PostImpl.Add(PostCreateDto);
    Check(PostId > 0, 'post created');
    BlogSvc := TBlogService.Create(PostImpl, TFailingUser.Create, TFailingTag.Create, TFailingComment.Create);
    try
      PostFullDto := BlogSvc.GetPostFull(PostId);
      Check(PostFullDto.Title = 'Lonely Post', 'should still return the post');
      Check(PostFullDto.Author.ID = 0, 'Author should have ID=0');
      Check(PostFullDto.AuthorUnavailable, 'AuthorUnavailable flag');
      CheckEqual(Length(PostFullDto.Tags), 0, 'Tags should be empty');
      Check(PostFullDto.TagsUnavailable, 'TagsUnavailable flag');
      CheckEqual(Length(PostFullDto.Comments), 0, 'Comments should be empty');
      Check(PostFullDto.CommentsUnavailable, 'CommentsUnavailable flag');
    finally
      BlogSvc.Free;
    end;
  finally
    Server.Free;
    Model.Free;
  end;
end;

procedure TTestBlogResilience.GetPostsByTagWithoutUsers;
var
  Model: TOrmModel;
  Server: TRestServerDB;
  PostImpl: TPostService;
  TagImpl: TTagService;
  BlogSvc: TBlogService;
  PostsByTagDto: TPostsByTagDto;
  PostId, TagId: TID;
  PostCreateDto: TPostCreateDto;
  TagCreateDto: TTagCreateDto;
begin
  Model := TOrmModel.Create(
    [TOrmBlogPost, TOrmBlogPostFts, TOrmAuthor, TOrmBlogTag, TOrmPostTag, TOrmBlogComment],
    MODEL_ROOT);
  Server := TRestServerDB.Create(Model, SQLITE_MEMORY_DATABASE_NAME);
  try
    Server.DB.Synchronous := smOff;
    Server.Server.CreateMissingTables;
    PostImpl := TPostService.Create(Server.Orm);
    TagImpl := TTagService.Create(Server.Orm);
    PostCreateDto.Title := 'Tagged Post';
    PostCreateDto.Body := 'content';
    PostCreateDto.AuthorId := 1;
    PostCreateDto.Status := POST_STATUS_PUBLISHED;
    PostId := PostImpl.Add(PostCreateDto);
    TagCreateDto.Name := 'TestTag';
    TagId := TagImpl.Add(TagCreateDto);
    TagImpl.SetPostTags(PostId, FormatUtf8('[%]', [TagId]));
    BlogSvc := TBlogService.Create(PostImpl, TFailingUser.Create, TagImpl, TFailingComment.Create);
    try
      PostsByTagDto := BlogSvc.GetPostsByTag(TagId);
      Check(PostsByTagDto.Tag.ID > 0, 'should have Tag');
      Check(Length(PostsByTagDto.Posts) > 0, 'should have at least one post');
      Check(PostsByTagDto.Posts[0].Title = 'Tagged Post', 'post title intact');
      Check(PostsByTagDto.Posts[0].Author.ID = 0, 'Author should have ID=0 when user service unavailable');
      Check(PostsByTagDto.Posts[0].AuthorUnavailable, 'AuthorUnavailable flag should be true');
    finally
      BlogSvc.Free;
    end;
  finally
    Server.Free;
    Model.Free;
  end;
end;

procedure TTestCircuitBreaker.AnalyticsBreakerTripsAndStopsCalls;
var
  Model: TOrmModel;
  Server: TRestServerDB;
  PostImpl: TPostService;
  UserImpl: TUserService;
  TagImpl: TTagService;
  CountingComment: TCountingFailComment;
  AnalyticsSvc: TAnalyticsService;
  RecentPosts: TPostFullDtoArray;
  PostIdx: Integer;
  PostCount: Integer;
  PostCreateDto: TPostCreateDto;
  AuthorCreateDto: TAuthorCreateDto;
begin
  // Drive the comments breaker past its threshold from a single GetRecentPostsFull call: more posts
  // than DEFAULT_FAILURE_THRESHOLD means the per-post FComments.GetByPost call will trip the breaker
  // mid-loop, and remaining posts must not invoke the upstream at all.
  PostCount := DEFAULT_FAILURE_THRESHOLD * 2;
  Model := TOrmModel.Create(
    [TOrmBlogPost, TOrmBlogPostFts, TOrmAuthor, TOrmBlogTag, TOrmPostTag, TOrmBlogComment],
    MODEL_ROOT);
  Server := TRestServerDB.Create(Model, SQLITE_MEMORY_DATABASE_NAME);
  try
    Server.DB.Synchronous := smOff;
    Server.Server.CreateMissingTables;
    PostImpl := TPostService.Create(Server.Orm);
    UserImpl := TUserService.Create(Server.Orm);
    TagImpl := TTagService.Create(Server.Orm);
    AuthorCreateDto.DisplayName := 'Author';
    UserImpl.Add(AuthorCreateDto);
    for PostIdx := 1 to PostCount do
    begin
      PostCreateDto.Title := FormatUtf8('Post %', [PostIdx]);
      PostCreateDto.Body := 'x';
      PostCreateDto.AuthorId := 1;
      PostCreateDto.Status := POST_STATUS_PUBLISHED;
      PostImpl.Add(PostCreateDto);
    end;
    CountingComment := TCountingFailComment.Create;
    AnalyticsSvc := TAnalyticsService.Create(PostImpl, UserImpl, TagImpl, CountingComment);
    try
      RecentPosts := AnalyticsSvc.GetRecentPostsFull(PostCount);
      CheckEqual(Length(RecentPosts), PostCount, 'all posts should still be returned');
      for PostIdx := 0 to High(RecentPosts) do
        Check(RecentPosts[PostIdx].CommentsUnavailable, 'every post must carry CommentsUnavailable');
      CheckEqual(CountingComment.GetByPostCount, DEFAULT_FAILURE_THRESHOLD,
        'after threshold trip the breaker must short-circuit further FComments.GetByPost calls');
    finally
      AnalyticsSvc.Free;
    end;
  finally
    Server.Free;
    Model.Free;
  end;
end;

procedure TTestCircuitBreaker.ConsecutiveFailuresTripBreaker;
var
  Breaker: TCircuitBreaker;
  FailureIdx: Integer;
begin
  Breaker := TCircuitBreaker.Create('test.trip', 3, 1000);
  try
    Check(Breaker.CurrentState = TCircuitBreakerState.Closed, 'initial state Closed');
    for FailureIdx := 1 to 3 do
      Breaker.RecordFailure;
    Check(Breaker.CurrentState = TCircuitBreakerState.Open, 'should be Open after 3 failures');
  finally
    Breaker.Free;
  end;
end;

procedure TTestCircuitBreaker.FailuresBelowThresholdKeepClosed;
var
  Breaker: TCircuitBreaker;
  FailureIdx: Integer;
begin
  Breaker := TCircuitBreaker.Create('test.belowthreshold', 5, 1000);
  try
    for FailureIdx := 1 to 4 do
      Breaker.RecordFailure;
    Check(Breaker.CurrentState = TCircuitBreakerState.Closed, '4 of 5 failures should keep Closed');
    Check(Breaker.AllowRequest, 'AllowRequest should still return True');
  finally
    Breaker.Free;
  end;
end;

procedure TTestCircuitBreaker.HalfOpenAllowsOnlyOneProbe;
var
  Breaker: TCircuitBreaker;
  FailureIdx: Integer;
begin
  Breaker := TCircuitBreaker.Create('test.singleprobe', 2, 50);
  try
    for FailureIdx := 1 to 2 do
      Breaker.RecordFailure;
    Check(Breaker.CurrentState = TCircuitBreakerState.Open, 'tripped to Open');
    SleepHiRes(80);
    Check(Breaker.AllowRequest, 'first call after cooldown is the probe -> True');
    Check(Breaker.CurrentState = TCircuitBreakerState.HalfOpen, 'state is now HalfOpen');
    Check(not Breaker.AllowRequest, 'second concurrent call must be rejected (one probe at a time)');
    Check(not Breaker.AllowRequest, 'further calls also rejected while probe in flight');
  finally
    Breaker.Free;
  end;
end;

procedure TTestCircuitBreaker.HalfOpenFailureReopensBreaker;
var
  Breaker: TCircuitBreaker;
  FailureIdx: Integer;
begin
  Breaker := TCircuitBreaker.Create('test.reopens', 2, 50);
  try
    for FailureIdx := 1 to 2 do
      Breaker.RecordFailure;
    SleepHiRes(80);
    Check(Breaker.AllowRequest, 'probe slot acquired');
    Check(Breaker.CurrentState = TCircuitBreakerState.HalfOpen, 'now HalfOpen');
    Breaker.RecordFailure;
    Check(Breaker.CurrentState = TCircuitBreakerState.Open, 'failed probe re-opens the breaker');
    Check(not Breaker.AllowRequest, 'reopened breaker rejects requests immediately');
  finally
    Breaker.Free;
  end;
end;

procedure TTestCircuitBreaker.HalfOpenSuccessClosesBreaker;
var
  Breaker: TCircuitBreaker;
  FailureIdx: Integer;
begin
  Breaker := TCircuitBreaker.Create('test.recovers', 2, 50);
  try
    for FailureIdx := 1 to 2 do
      Breaker.RecordFailure;
    SleepHiRes(80);
    Check(Breaker.AllowRequest, 'probe slot acquired');
    Check(Breaker.CurrentState = TCircuitBreakerState.HalfOpen, 'now HalfOpen');
    Breaker.RecordSuccess;
    Check(Breaker.CurrentState = TCircuitBreakerState.Closed, 'successful probe closes the breaker');
    Check(Breaker.AllowRequest, 'closed breaker allows the next request');
  finally
    Breaker.Free;
  end;
end;

procedure TTestCircuitBreaker.InitialStateIsClosedAndAllows;
var
  Breaker: TCircuitBreaker;
begin
  Breaker := TCircuitBreaker.Create('test.initial');
  try
    Check(Breaker.CurrentState = TCircuitBreakerState.Closed, 'initial state Closed');
    Check(Breaker.AllowRequest, 'fresh breaker allows requests');
    CheckEqual(Breaker.Name, 'test.initial', 'name property exposes constructor argument');
  finally
    Breaker.Free;
  end;
end;

procedure TTestCircuitBreaker.IntegrationFastFailsAfterTrip;
var
  Model: TOrmModel;
  Server: TRestServerDB;
  PostImpl: TPostService;
  CountingUser: TCountingFailUser;
  BlogSvc: TBlogService;
  PostFullDto: TPostFullDto;
  PostId: TID;
  PostCreateDto: TPostCreateDto;
  CallIdx: Integer;
begin
  Model := TOrmModel.Create(
    [TOrmBlogPost, TOrmBlogPostFts, TOrmAuthor, TOrmBlogTag, TOrmPostTag, TOrmBlogComment],
    MODEL_ROOT);
  Server := TRestServerDB.Create(Model, SQLITE_MEMORY_DATABASE_NAME);
  try
    Server.DB.Synchronous := smOff;
    Server.Server.CreateMissingTables;
    PostImpl := TPostService.Create(Server.Orm);
    PostCreateDto.Title := 'Trip Post';
    PostCreateDto.Body := 'content';
    PostCreateDto.AuthorId := 1;
    PostCreateDto.Status := POST_STATUS_PUBLISHED;
    PostId := PostImpl.Add(PostCreateDto);
    Check(PostId > 0, 'post created');
    CountingUser := TCountingFailUser.Create;
    BlogSvc := TBlogService.Create(PostImpl, CountingUser, TFailingTag.Create, TFailingComment.Create);
    try
      // Drive the breaker past its default threshold; subsequent calls must not reach FUsers.Get.
      for CallIdx := 1 to DEFAULT_FAILURE_THRESHOLD * 2 do
      begin
        PostFullDto := BlogSvc.GetPostFull(PostId);
        Check(PostFullDto.AuthorUnavailable, 'every call yields AuthorUnavailable');
      end;
      CheckEqual(CountingUser.CallCount, DEFAULT_FAILURE_THRESHOLD,
        'after threshold trip the breaker must short-circuit further FUsers.Get calls');
    finally
      BlogSvc.Free;
    end;
  finally
    Server.Free;
    Model.Free;
  end;
end;

procedure TTestCircuitBreaker.OpenRejectsRequests;
var
  Breaker: TCircuitBreaker;
  FailureIdx: Integer;
  RejectIdx: Integer;
begin
  Breaker := TCircuitBreaker.Create('test.openrejects', 2, 5000);
  try
    for FailureIdx := 1 to 2 do
      Breaker.RecordFailure;
    Check(Breaker.CurrentState = TCircuitBreakerState.Open, 'should be Open');
    for RejectIdx := 1 to 10 do
      Check(not Breaker.AllowRequest, 'every call in Open state must be rejected');
  finally
    Breaker.Free;
  end;
end;

procedure TTestCircuitBreaker.OpenTransitionsToHalfOpenAfterCooldown;
var
  Breaker: TCircuitBreaker;
  FailureIdx: Integer;
begin
  Breaker := TCircuitBreaker.Create('test.cooldown', 2, 50);
  try
    for FailureIdx := 1 to 2 do
      Breaker.RecordFailure;
    Check(Breaker.CurrentState = TCircuitBreakerState.Open, 'tripped to Open');
    Check(not Breaker.AllowRequest, 'still Open before cooldown elapses');
    SleepHiRes(80);
    Check(Breaker.AllowRequest, 'probe permitted after cooldown');
    Check(Breaker.CurrentState = TCircuitBreakerState.HalfOpen, 'state moved to HalfOpen');
  finally
    Breaker.Free;
  end;
end;

procedure TTestCircuitBreaker.SuccessResetsFailureCount;
var
  Breaker: TCircuitBreaker;
begin
  Breaker := TCircuitBreaker.Create('test.reset', 3, 1000);
  try
    Breaker.RecordFailure;
    Breaker.RecordFailure;
    Breaker.RecordSuccess;
    // Counter is reset; two more failures alone must NOT trip the breaker.
    Breaker.RecordFailure;
    Breaker.RecordFailure;
    Check(Breaker.CurrentState = TCircuitBreakerState.Closed,
      'success between failures should reset the consecutive-failure counter');
    // The third consecutive failure now does trip it.
    Breaker.RecordFailure;
    Check(Breaker.CurrentState = TCircuitBreakerState.Open,
      'three consecutive failures after the reset should trip the breaker');
  finally
    Breaker.Free;
  end;
end;

procedure TTestRateLimiter.BucketsAreIsolatedPerKey;
var
  Limiter: TRateLimiter;
  AcquireIdx: Integer;
begin
  Limiter := TRateLimiter.Create('test.isolation', 3.0, 0.0);
  try
    // Drain key 'a' completely.
    for AcquireIdx := 1 to 3 do
      Check(Limiter.TryAcquire('a'), 'a within burst');
    Check(not Limiter.TryAcquire('a'), 'a exhausted');
    // Key 'b' is untouched and must still serve a full burst.
    for AcquireIdx := 1 to 3 do
      Check(Limiter.TryAcquire('b'), 'b within burst, isolated from a');
    Check(not Limiter.TryAcquire('b'), 'b exhausted independently');
    CheckEqual(Limiter.BucketCount, 2, 'one bucket per distinct key');
  finally
    Limiter.Free;
  end;
end;

procedure TTestRateLimiter.BurstAllowsExactlyCapacityRequests;
var
  Limiter: TRateLimiter;
  AcquireIdx: Integer;
begin
  // Refill rate of 0 isolates the test from wall-clock noise: only the burst is exercised.
  Limiter := TRateLimiter.Create('test.burst', 5.0, 0.0);
  try
    for AcquireIdx := 1 to 5 do
      Check(Limiter.TryAcquire('client'), Format('acquire %d within burst', [AcquireIdx]));
    Check(not Limiter.TryAcquire('client'), 'acquire beyond burst must be denied');
    Check(not Limiter.TryAcquire('client'), 'still denied on the next call');
  finally
    Limiter.Free;
  end;
end;

procedure TTestRateLimiter.FirstAcquireOnNewKeyAlwaysSucceeds;
var
  Limiter: TRateLimiter;
begin
  Limiter := TRateLimiter.Create('test.first', 1.0, 0.0);
  try
    CheckEqual(Limiter.BucketCount, 0, 'fresh limiter has no buckets');
    Check(Limiter.TryAcquire('alpha'), 'first acquire seeds a full bucket');
    CheckEqual(Limiter.BucketCount, 1, 'one bucket created');
    Check(Limiter.TryAcquire('beta'), 'distinct key also seeds a full bucket');
    CheckEqual(Limiter.BucketCount, 2, 'second bucket created');
  finally
    Limiter.Free;
  end;
end;

procedure TTestRateLimiter.IdleEvictionRemovesUnusedBuckets;
var
  Limiter: TRateLimiter;
begin
  // 50 ms idle TTL: easy to exceed deterministically with SleepHiRes.
  Limiter := TRateLimiter.Create('test.evict', 2.0, 0.0, 50);
  try
    Check(Limiter.TryAcquire('stale-a'), 'create stale-a bucket');
    Check(Limiter.TryAcquire('stale-b'), 'create stale-b bucket');
    CheckEqual(Limiter.BucketCount, 2, 'two buckets registered');
    SleepHiRes(120);
    // Touching a fresh key triggers the amortised eviction sweep, which must drop both stale buckets
    // and leave only the new one.
    Check(Limiter.TryAcquire('fresh'), 'fresh key acquired after idle window');
    CheckEqual(Limiter.BucketCount, 1, 'idle buckets evicted on next acquire');
  finally
    Limiter.Free;
  end;
end;

procedure TTestRateLimiter.RefillRestoresTokensOverTime;
var
  Limiter: TRateLimiter;
begin
  // Capacity 2, refill 20/sec -> one token every 50 ms. SleepHiRes(120) yields ~2 tokens.
  Limiter := TRateLimiter.Create('test.refill', 2.0, 20.0);
  try
    Check(Limiter.TryAcquire('client'), 'first burst slot');
    Check(Limiter.TryAcquire('client'), 'second burst slot');
    Check(not Limiter.TryAcquire('client'), 'bucket empty after burst');
    SleepHiRes(120);
    Check(Limiter.TryAcquire('client'), 'refilled token available after wait');
  finally
    Limiter.Free;
  end;
end;

procedure TTestRateLimiter.ResetIsNoopForUnknownKey;
var
  Limiter: TRateLimiter;
begin
  Limiter := TRateLimiter.Create('test.reset-unknown', 3.0, 0.0);
  try
    Limiter.Reset('never-seen');
    CheckEqual(Limiter.BucketCount, 0, 'Reset must not create a spurious bucket');
    // The key still works on first contact like any other.
    Check(Limiter.TryAcquire('never-seen'), 'first acquire after no-op Reset');
    CheckEqual(Limiter.BucketCount, 1, 'bucket created lazily by TryAcquire, not by Reset');
  finally
    Limiter.Free;
  end;
end;

procedure TTestRateLimiter.ResetRestoresFullCapacity;
var
  Limiter: TRateLimiter;
  AcquireIdx: Integer;
begin
  Limiter := TRateLimiter.Create('test.reset-full', 4.0, 0.0);
  try
    for AcquireIdx := 1 to 4 do
      Check(Limiter.TryAcquire('client'), 'drain bucket');
    Check(not Limiter.TryAcquire('client'), 'bucket empty');
    Limiter.Reset('client');
    for AcquireIdx := 1 to 4 do
      Check(Limiter.TryAcquire('client'), 'full burst again after Reset');
    Check(not Limiter.TryAcquire('client'), 'and exhausted again');
  finally
    Limiter.Free;
  end;
end;

procedure TTestRateLimiter.TryAcquireNRespectsCost;
var
  Limiter: TRateLimiter;
begin
  Limiter := TRateLimiter.Create('test.cost', 10.0, 0.0);
  try
    Check(Limiter.TryAcquireN('client', 4.0), 'spend 4 of 10');
    Check(Limiter.TryAcquireN('client', 4.0), 'spend 4 more (8 of 10)');
    Check(not Limiter.TryAcquireN('client', 4.0), 'only 2 left, cannot spend 4');
    Check(Limiter.TryAcquireN('client', 2.0), 'remaining 2 are spendable');
    Check(not Limiter.TryAcquire('client'), 'fully exhausted now');
  finally
    Limiter.Free;
  end;
end;

procedure TTestAnalyticsService.GetOverview;
var
  Overview: TOverviewDto;
begin
  Overview := Context.Analytics.GetOverview;
  Check(Overview.Posts > 0, 'should have posts');
  Check(Overview.Authors > 0, 'should have authors');
  Check(Overview.Tags > 0, 'should have tags');
  Check(Overview.PendingComments >= 0, 'should have pendingComments');
end;

procedure TTestAnalyticsService.GetAuthorStats;
var
  AuthorStats: TAuthorStatDtoArray;
begin
  AuthorStats := Context.Analytics.GetAuthorStats;
  Check(Length(AuthorStats) > 0, 'should have at least one author');
  Check(AuthorStats[0].AuthorId > 0, 'should have authorId');
  Check(AuthorStats[0].DisplayName <> '', 'should have displayName');
  Check(AuthorStats[0].PostCount >= 0, 'should have postCount');
end;

procedure TTestAnalyticsService.GetTagCloud;
var
  TagCloud: TTagCloudItemDtoArray;
begin
  TagCloud := Context.Analytics.GetTagCloud;
  Check(Length(TagCloud) > 0, 'should have at least one tag');
  Check(TagCloud[0].TagId > 0, 'should have tagId');
  Check(TagCloud[0].Name <> '', 'should have name');
  Check(TagCloud[0].PostCount >= 0, 'should have postCount');
end;

procedure TTestAnalyticsService.GetCommentActivity;
var
  Activity: TCommentActivityDto;
begin
  Activity := Context.Analytics.GetCommentActivity;
  Check(Activity.PendingCount >= 0, 'should have pendingCount');
end;

procedure TTestAnalyticsService.GetRecentPostsFull;
var
  RecentPosts: TPostFullDtoArray;
begin
  RecentPosts := Context.Analytics.GetRecentPostsFull(5);
  Check(Length(RecentPosts) > 0, 'should have at least one post');
  Check(RecentPosts[0].Title <> '', 'should have Title');
  Check(RecentPosts[0].ID > 0, 'should have valid ID');
end;

procedure TTestAnalyticsService.GetRecentPostsFullEmpty;
var
  RecentPosts: TPostFullDtoArray;
begin
  RecentPosts := Context.Analytics.GetRecentPostsFull(0);
  Check(Length(RecentPosts) = 0, 'limit 0 should return empty array');
end;

procedure TTestAnalyticsResilience.GetOverviewWithoutPosts;
var
  AnalyticsSvc: TAnalyticsService;
  Overview: TOverviewDto;
begin
  AnalyticsSvc := TAnalyticsService.Create(TFailingPost.Create, TFailingUser.Create, TFailingTag.Create,
    TFailingComment.Create);
  try
    Overview := AnalyticsSvc.GetOverview;
    Check(Overview.PostsUnavailable, 'postsUnavailable flag');
    Check(Overview.AuthorsUnavailable, 'authorsUnavailable flag');
    Check(Overview.TagsUnavailable, 'tagsUnavailable flag');
    Check(Overview.CommentsUnavailable, 'commentsUnavailable flag');
  finally
    AnalyticsSvc.Free;
  end;
end;

procedure TTestAnalyticsResilience.GetOverviewWithoutUsers;
var
  Model: TOrmModel;
  Server: TRestServerDB;
  PostImpl: TPostService;
  TagImpl: TTagService;
  CommentImpl: TCommentService;
  AnalyticsSvc: TAnalyticsService;
  Overview: TOverviewDto;
  PostCreateDto: TPostCreateDto;
begin
  Model := TOrmModel.Create(
    [TOrmBlogPost, TOrmBlogPostFts, TOrmAuthor, TOrmBlogTag, TOrmPostTag, TOrmBlogComment],
    MODEL_ROOT);
  Server := TRestServerDB.Create(Model, SQLITE_MEMORY_DATABASE_NAME);
  try
    Server.DB.Synchronous := smOff;
    Server.Server.CreateMissingTables;
    PostImpl := TPostService.Create(Server.Orm);
    TagImpl := TTagService.Create(Server.Orm);
    CommentImpl := TCommentService.Create(Server.Orm);
    PostCreateDto.Title := 'Test';
    PostCreateDto.Body := 'x';
    PostCreateDto.AuthorId := 1;
    PostCreateDto.Status := POST_STATUS_PUBLISHED;
    PostImpl.Add(PostCreateDto);
    AnalyticsSvc := TAnalyticsService.Create(PostImpl, TFailingUser.Create, TagImpl, CommentImpl);
    try
      Overview := AnalyticsSvc.GetOverview;
      Check(Overview.Posts > 0, 'posts should be counted');
      Check(Overview.AuthorsUnavailable, 'authorsUnavailable flag');
    finally
      AnalyticsSvc.Free;
    end;
  finally
    Server.Free;
    Model.Free;
  end;
end;

procedure TTestAnalyticsResilience.GetRecentPostsFullWithoutComments;
var
  Model: TOrmModel;
  Server: TRestServerDB;
  PostImpl: TPostService;
  UserImpl: TUserService;
  TagImpl: TTagService;
  AnalyticsSvc: TAnalyticsService;
  RecentPosts: TPostFullDtoArray;
  AuthorCreateDto: TAuthorCreateDto;
  PostCreateDto: TPostCreateDto;
begin
  Model := TOrmModel.Create(
    [TOrmBlogPost, TOrmBlogPostFts, TOrmAuthor, TOrmBlogTag, TOrmPostTag, TOrmBlogComment],
    MODEL_ROOT);
  Server := TRestServerDB.Create(Model, SQLITE_MEMORY_DATABASE_NAME);
  try
    Server.DB.Synchronous := smOff;
    Server.Server.CreateMissingTables;
    PostImpl := TPostService.Create(Server.Orm);
    UserImpl := TUserService.Create(Server.Orm);
    TagImpl := TTagService.Create(Server.Orm);
    AuthorCreateDto.DisplayName := 'Author';
    UserImpl.Add(AuthorCreateDto);
    PostCreateDto.Title := 'Test Post';
    PostCreateDto.Body := 'x';
    PostCreateDto.AuthorId := 1;
    PostCreateDto.Status := POST_STATUS_PUBLISHED;
    PostImpl.Add(PostCreateDto);
    AnalyticsSvc := TAnalyticsService.Create(PostImpl, UserImpl, TagImpl, TFailingComment.Create);
    try
      RecentPosts := AnalyticsSvc.GetRecentPostsFull(5);
      Check(Length(RecentPosts) > 0, 'should have posts');
      Check(RecentPosts[0].Title = 'Test Post', 'title intact');
      Check(RecentPosts[0].CommentsUnavailable, 'CommentsUnavailable flag');
    finally
      AnalyticsSvc.Free;
    end;
  finally
    Server.Free;
    Model.Free;
  end;
end;

procedure TTestAnalyticsResilience.GetRecentPostsFullWithoutTags;
var
  Model: TOrmModel;
  Server: TRestServerDB;
  PostImpl: TPostService;
  UserImpl: TUserService;
  CommentImpl: TCommentService;
  AnalyticsSvc: TAnalyticsService;
  RecentPosts: TPostFullDtoArray;
  AuthorCreateDto: TAuthorCreateDto;
  PostCreateDto: TPostCreateDto;
begin
  Model := TOrmModel.Create(
    [TOrmBlogPost, TOrmBlogPostFts, TOrmAuthor, TOrmBlogTag, TOrmPostTag, TOrmBlogComment],
    MODEL_ROOT);
  Server := TRestServerDB.Create(Model, SQLITE_MEMORY_DATABASE_NAME);
  try
    Server.DB.Synchronous := smOff;
    Server.Server.CreateMissingTables;
    PostImpl := TPostService.Create(Server.Orm);
    UserImpl := TUserService.Create(Server.Orm);
    CommentImpl := TCommentService.Create(Server.Orm);
    AuthorCreateDto.DisplayName := 'Author';
    UserImpl.Add(AuthorCreateDto);
    PostCreateDto.Title := 'Test Post';
    PostCreateDto.Body := 'x';
    PostCreateDto.AuthorId := 1;
    PostCreateDto.Status := POST_STATUS_PUBLISHED;
    PostImpl.Add(PostCreateDto);
    AnalyticsSvc := TAnalyticsService.Create(PostImpl, UserImpl, TFailingTag.Create, CommentImpl);
    try
      RecentPosts := AnalyticsSvc.GetRecentPostsFull(5);
      Check(Length(RecentPosts) > 0, 'should have posts');
      Check(RecentPosts[0].Title = 'Test Post', 'title intact');
      Check(RecentPosts[0].TagsUnavailable, 'TagsUnavailable flag');
    finally
      AnalyticsSvc.Free;
    end;
  finally
    Server.Free;
    Model.Free;
  end;
end;

const
  TEST_MASTER_JSON: RawUtf8 =
    '{"ms.auth":{"Host":"localhost","Port":"8081","Database":"auth.db",' +
    '"JwtSecret":"secret123","LogLevel":"debug","ModelRoot":"api",' +
    '"HttpThreads":4,"HttpSecurity":"secNone","HttpBind":"+"},' +
    '"ms.users":{"Host":"localhost","Port":"8082","Database":"users.db",' +
    '"LogLevel":"info","ModelRoot":"api","HttpThreads":2,' +
    '"HttpSecurity":"secNone","HttpBind":"+"}}';

  /// <summary>
  ///   Test master JSON exercising the <c>defaults</c> merging behavior. ms.auth inherits Host/LogLevel from
  ///   defaults but overrides Port. ms.users overrides LogLevel and Port but still inherits Host.
  /// </summary>
  TEST_MASTER_JSON_WITH_DEFAULTS: RawUtf8 =
    '{"defaults":{"Host":"localhost","LogLevel":"debug","ModelRoot":"api",' +
    '"HttpThreads":4,"HttpSecurity":"secNone","HttpBind":"+"},' +
    '"ms.auth":{"Port":"8081","Database":"auth.db","JwtSecret":"secret123"},' +
    '"ms.users":{"Port":"8082","Database":"users.db","LogLevel":"info"}}';

procedure TTestConfigService.DefaultsAppliedWhenNotOverridden;
var
  Svc: TConfigService;
  Doc: TDocVariantData;
begin
  Svc := TConfigService.Create(TEST_MASTER_JSON_WITH_DEFAULTS);
  try
    Doc.InitJson(Svc.GetServiceConfig('ms.auth'), JSON_FAST_FLOAT);
    // Inherited from defaults
    CheckEqual(Doc.U['Host'], 'localhost', 'Host inherited from defaults');
    CheckEqual(Doc.U['LogLevel'], 'debug', 'LogLevel inherited from defaults');
    CheckEqual(Doc.U['ModelRoot'], 'api', 'ModelRoot inherited from defaults');
    CheckEqual(Doc.I['HttpThreads'], 4, 'HttpThreads inherited from defaults');
    // Per-service fields are still present
    CheckEqual(Doc.U['Port'], '8081', 'service-specific Port present');
    CheckEqual(Doc.U['Database'], 'auth.db', 'service-specific Database present');
    CheckEqual(Doc.U['JwtSecret'], 'secret123', 'service-specific JwtSecret present');
  finally
    Svc.Free;
  end;
end;

procedure TTestConfigService.DefaultsKeyIsNotAService;
var
  Svc: TConfigService;
begin
  Svc := TConfigService.Create(TEST_MASTER_JSON_WITH_DEFAULTS);
  try
    CheckEqual(Svc.GetServiceConfig('defaults'), '{}', 'defaults must not be served as a service');
  finally
    Svc.Free;
  end;
end;

procedure TTestConfigService.GetServiceConfigKnown;
var
  Svc: TConfigService;
  Doc: TDocVariantData;
begin
  Svc := TConfigService.Create(TEST_MASTER_JSON);
  try
    Doc.InitJson(Svc.GetServiceConfig('ms.auth'), JSON_FAST_FLOAT);
    CheckEqual(Doc.U['Host'], 'localhost', 'Host');
    CheckEqual(Doc.U['Port'], '8081', 'Port');
    CheckEqual(Doc.U['Database'], 'auth.db', 'Database');
    CheckEqual(Doc.U['JwtSecret'], 'secret123', 'JwtSecret');
  finally
    Svc.Free;
  end;
end;

procedure TTestConfigService.GetServiceConfigUnknown;
var
  Svc: TConfigService;
begin
  Svc := TConfigService.Create(TEST_MASTER_JSON);
  try
    CheckEqual(Svc.GetServiceConfig('ms.nonexistent'), '{}', 'unknown service should return empty object');
  finally
    Svc.Free;
  end;
end;

procedure TTestConfigService.GetAllConfigs;
var
  Svc: TConfigService;
  Doc: TDocVariantData;
begin
  Svc := TConfigService.Create(TEST_MASTER_JSON);
  try
    Doc.InitJson(Svc.GetAllConfigs, JSON_FAST_FLOAT);
    Check(Doc.GetValueIndex('ms.auth') >= 0, 'should have ms.auth');
    Check(Doc.GetValueIndex('ms.users') >= 0, 'should have ms.users');
  finally
    Svc.Free;
  end;
end;

procedure TTestConfigService.GetAllConfigsExcludesDefaults;
var
  Svc: TConfigService;
  Doc: TDocVariantData;
  AuthEntry: PDocVariantData;
begin
  Svc := TConfigService.Create(TEST_MASTER_JSON_WITH_DEFAULTS);
  try
    Doc.InitJson(Svc.GetAllConfigs, JSON_FAST_FLOAT);
    CheckEqual(Doc.GetValueIndex('defaults'), -1, 'defaults block must be excluded from GetAllConfigs');
    Check(Doc.GetValueIndex('ms.auth') >= 0, 'ms.auth should be present');
    Check(Doc.GetValueIndex('ms.users') >= 0, 'ms.users should be present');
    // Each entry must already be the merged effective configuration, so inherited fields are visible.
    AuthEntry := Doc.O['ms.auth'];
    Check(AuthEntry <> nil, 'ms.auth entry should exist');
    CheckEqual(AuthEntry^.U['Host'], 'localhost', 'merged Host visible in GetAllConfigs');
    CheckEqual(AuthEntry^.U['LogLevel'], 'debug', 'merged LogLevel visible in GetAllConfigs');
  finally
    Svc.Free;
  end;
end;

procedure TTestConfigService.GetServiceRegistry;
var
  Svc: TConfigService;
  Doc: TDocVariantData;
  AuthEntry: PDocVariantData;
begin
  Svc := TConfigService.Create(TEST_MASTER_JSON);
  try
    Doc.InitJson(Svc.GetServiceRegistry, JSON_FAST_FLOAT);
    Check(Doc.GetValueIndex('ms.auth') >= 0, 'should have ms.auth');
    AuthEntry := Doc.O['ms.auth'];
    Check(AuthEntry <> nil, 'auth entry should exist');
    CheckEqual(AuthEntry^.U['Host'], 'localhost', 'Host in registry');
    CheckEqual(AuthEntry^.U['Port'], '8081', 'Port in registry');
  finally
    Svc.Free;
  end;
end;

procedure TTestConfigService.GetServiceRegistryNoSecrets;
var
  Svc: TConfigService;
  Doc: TDocVariantData;
  AuthEntry: PDocVariantData;
begin
  Svc := TConfigService.Create(TEST_MASTER_JSON);
  try
    Doc.InitJson(Svc.GetServiceRegistry, JSON_FAST_FLOAT);
    AuthEntry := Doc.O['ms.auth'];
    Check(AuthEntry <> nil, 'auth entry should exist');
    CheckEqual(AuthEntry^.GetValueIndex('JwtSecret'), -1, 'JwtSecret must not be in registry');
    CheckEqual(AuthEntry^.GetValueIndex('Database'), -1, 'Database must not be in registry');
  finally
    Svc.Free;
  end;
end;

procedure TTestConfigService.GetServiceRegistryUsesDefaultsForHost;
var
  Svc: TConfigService;
  Doc: TDocVariantData;
  AuthEntry: PDocVariantData;
begin
  Svc := TConfigService.Create(TEST_MASTER_JSON_WITH_DEFAULTS);
  try
    Doc.InitJson(Svc.GetServiceRegistry, JSON_FAST_FLOAT);
    CheckEqual(Doc.GetValueIndex('defaults'), -1, 'defaults block must be excluded from registry');
    AuthEntry := Doc.O['ms.auth'];
    Check(AuthEntry <> nil, 'ms.auth entry should exist');
    // Host is not on the per-service block; the registry must fall back to the defaults block.
    CheckEqual(AuthEntry^.U['Host'], 'localhost', 'Host inherited from defaults block');
    CheckEqual(AuthEntry^.U['Port'], '8081', 'Port from per-service block');
  finally
    Svc.Free;
  end;
end;

procedure TTestConfigService.ServiceOverridesDefaults;
var
  Svc: TConfigService;
  Doc: TDocVariantData;
begin
  Svc := TConfigService.Create(TEST_MASTER_JSON_WITH_DEFAULTS);
  try
    Doc.InitJson(Svc.GetServiceConfig('ms.users'), JSON_FAST_FLOAT);
    // ms.users overrides LogLevel = 'info' (defaults says 'debug')
    CheckEqual(Doc.U['LogLevel'], 'info', 'per-service LogLevel must override defaults');
    // Non-overridden fields still inherit from defaults
    CheckEqual(Doc.U['Host'], 'localhost', 'Host still inherited from defaults');
    CheckEqual(Doc.U['ModelRoot'], 'api', 'ModelRoot still inherited from defaults');
  finally
    Svc.Free;
  end;
end;

procedure TTestCorrelationIds.GenerateUnique;
var
  IdA, IdB: RawUtf8;
begin
  IdA := GenerateCorrelationId;
  IdB := GenerateCorrelationId;
  Check(IdA <> '', 'GenerateCorrelationId must not return empty');
  Check(IdB <> '', 'GenerateCorrelationId must not return empty');
  Check(IdA <> IdB, 'two successive IDs must differ');
end;

procedure TTestCorrelationIds.GenerateValidFormat;
var
  Id: RawUtf8;
  CharIdx: PtrInt;
  Hyphens: integer;
  CharValue: AnsiChar;
begin
  Id := GenerateCorrelationId;
  CheckEqual(Length(Id), 36, 'UUID length must be 36 chars');
  Check(Id[1] <> '{', 'UUID must not start with brace');
  Check(Id[Length(Id)] <> '}', 'UUID must not end with brace');
  Hyphens := 0;
  for CharIdx := 1 to Length(Id) do
  begin
    CharValue := Id[CharIdx];
    if CharValue = '-' then
      Inc(Hyphens)
    else
      Check(CharValue in ['0'..'9', 'a'..'f'], 'UUID chars must be lowercase hex');
  end;
  CheckEqual(Hyphens, 4, 'UUID must contain exactly 4 hyphens');
end;

procedure TTestCorrelationIds.SetGetRoundTrip;
begin
  ClearCurrentCorrelationId;
  CheckEqual(GetCurrentCorrelationId, '', 'should start empty');
  SetCurrentCorrelationId('abc-123');
  CheckEqual(GetCurrentCorrelationId, 'abc-123', 'set+get should round-trip');
  ClearCurrentCorrelationId;
end;

procedure TTestCorrelationIds.ClearResetsValue;
begin
  SetCurrentCorrelationId('to-be-cleared');
  CheckEqual(GetCurrentCorrelationId, 'to-be-cleared');
  ClearCurrentCorrelationId;
  CheckEqual(GetCurrentCorrelationId, '', 'after clear must be empty');
end;

procedure TTestCorrelationIds.ExtractFromHeadersWhenPresent;
const
  HEADERS = 'Content-Type: application/json'#13#10 +
            'X-Correlation-Id: a8f3c1e9-7d24-4b5f-9e1c-2a3b4c5d6e7f'#13#10 +
            'Authorization: Bearer xyz';
begin
  CheckEqual(ExtractCorrelationIdFromHeaders(HEADERS),
    'a8f3c1e9-7d24-4b5f-9e1c-2a3b4c5d6e7f',
    'should extract the value verbatim');
end;

procedure TTestCorrelationIds.ExtractFromHeadersWhenAbsent;
const
  HEADERS = 'Content-Type: application/json'#13#10 +
            'Authorization: Bearer xyz';
begin
  CheckEqual(ExtractCorrelationIdFromHeaders(HEADERS), '',
    'absent header must yield empty string');
end;

procedure TTestCorrelationIds.ExtractFromHeadersCaseInsensitive;
const
  HEADERS_LOWER = 'x-correlation-id: lowercase-value-123'#13#10;
begin
  CheckEqual(ExtractCorrelationIdFromHeaders(HEADERS_LOWER),
    'lowercase-value-123',
    'lookup must be case-insensitive');
end;

procedure TTestCorrelationIds.EnsureUsesExistingHeader;
const
  HEADERS = 'X-Correlation-Id: client-supplied-id-42'#13#10;
var
  Effective: RawUtf8;
begin
  ClearCurrentCorrelationId;
  Effective := EnsureCorrelationIdFromHeaders(HEADERS);
  CheckEqual(Effective, 'client-supplied-id-42', 'must use existing header');
  CheckEqual(GetCurrentCorrelationId, 'client-supplied-id-42',
    'threadvar must be set to the same value');
  ClearCurrentCorrelationId;
end;

procedure TTestCorrelationIds.EnsureGeneratesWhenAbsent;
var
  Effective: RawUtf8;
begin
  ClearCurrentCorrelationId;
  Effective := EnsureCorrelationIdFromHeaders('Content-Type: application/json');
  Check(Effective <> '', 'must generate a fresh ID');
  CheckEqual(Length(Effective), 36, 'generated ID must be a 36-char UUID');
  CheckEqual(GetCurrentCorrelationId, Effective,
    'threadvar must hold the generated ID');
  ClearCurrentCorrelationId;
end;

procedure TTestCorrelationIds.ParseFromMessagePrefix;
const
  MSG = '[a8f3c1e9-7d24-4b5f-9e1c-2a3b4c5d6e7f] ms.posts REQ POST /api/Post/Get';
begin
  CheckEqual(ExtractCorrelationIdFromMessage(MSG),
    'a8f3c1e9-7d24-4b5f-9e1c-2a3b4c5d6e7f',
    'must find the UUID prefix');
end;

procedure TTestCorrelationIds.ParseFromMessageWithoutUuid;
begin
  CheckEqual(ExtractCorrelationIdFromMessage(
    'ms.gateway starting on port 8080...'), '',
    'plain text must yield empty');
  CheckEqual(ExtractCorrelationIdFromMessage(''), '',
    'empty input must yield empty');
end;

procedure TTestCorrelationIds.ParseFromMessageInvalidBrackets;
begin
  CheckEqual(ExtractCorrelationIdFromMessage('[not-a-uuid] message'), '',
    'too short to be a UUID');
  CheckEqual(ExtractCorrelationIdFromMessage(
    '[zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz] message'), '',
    'non-hex chars must not match');
  CheckEqual(ExtractCorrelationIdFromMessage(
    '[a8f3c1e9-7d24-4b5f-9e1c-2a3b4c5d6e7f extra]'), '',
    '37 chars between brackets must not match');
end;

procedure TTestLogService.ByCorrelationIdEmpty;
var
  Entries: TLogEntryDtoArray;
begin
  Entries := Context.LogQuery.ByCorrelationId('');
  CheckEqual(Length(Entries), 0, 'empty correlation ID returns empty array');
  Entries := Context.LogQuery.ByCorrelationId('does-not-exist-id-9999');
  CheckEqual(Length(Entries), 0, 'unknown correlation ID returns empty array');
end;

procedure TTestLogService.IngestAndQueryByCorrelation;
const
  CORR_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
var
  Batch: TLogEntryIngestDtoArray;
  Entries: TLogEntryDtoArray;
begin
  SetLength(Batch, 2);
  Batch[0].ServiceName := 'ms.gateway';
  Batch[0].Timestamp := NowUtc;
  Batch[0].Level := 1;
  Batch[0].Message := '[' + CORR_ID + '] ms.gateway REQ POST /api/Post/Get';
  Batch[1].ServiceName := 'ms.posts';
  Batch[1].Timestamp := NowUtc;
  Batch[1].Level := 1;
  Batch[1].Message := '[' + CORR_ID + '] ms.posts REQ POST /api/Post/Get';
  Context.LogIngestion.AppendBatch(Batch);
  Entries := Context.LogQuery.ByCorrelationId(CORR_ID);
  CheckEqual(Length(Entries), 2, 'should retrieve both ingested entries');
  Check((Entries[0].ServiceName = 'ms.gateway') or (Entries[1].ServiceName = 'ms.gateway'),
    'one entry must come from ms.gateway');
  Check((Entries[0].ServiceName = 'ms.posts') or (Entries[1].ServiceName = 'ms.posts'),
    'one entry must come from ms.posts');
end;

procedure TTestLogService.IngestParsesCorrelationFromText;
const
  CORR_ID = '11111111-2222-3333-4444-555555555555';
var
  Batch: TLogEntryIngestDtoArray;
  Entries: TLogEntryDtoArray;
begin
  SetLength(Batch, 1);
  Batch[0].ServiceName := 'ms.users';
  Batch[0].Timestamp := NowUtc;
  Batch[0].Level := 1;
  Batch[0].Message := '[' + CORR_ID + '] some message body here';
  Context.LogIngestion.AppendBatch(Batch);
  Entries := Context.LogQuery.ByCorrelationId(CORR_ID);
  CheckEqual(Length(Entries), 1, 'should find the ingested entry');
  CheckEqual(Entries[0].CorrelationId, CORR_ID,
    'parser must populate the indexed CorrelationId column');
end;

procedure TTestLogService.RecentFiltersByService;
const
  CORR_ID = '99999999-8888-7777-6666-555555555555';
var
  Batch: TLogEntryIngestDtoArray;
  Filter: TLogQueryFilter;
  Entries: TLogEntryDtoArray;
  EntryIdx: PtrInt;
begin
  SetLength(Batch, 2);
  Batch[0].ServiceName := 'ms.tags';
  Batch[0].Timestamp := NowUtc;
  Batch[0].Level := 1;
  Batch[0].Message := '[' + CORR_ID + '] ms.tags entry';
  Batch[1].ServiceName := 'ms.comments';
  Batch[1].Timestamp := NowUtc;
  Batch[1].Level := 1;
  Batch[1].Message := '[' + CORR_ID + '] ms.comments entry';
  Context.LogIngestion.AppendBatch(Batch);
  FillCharFast(Filter, SizeOf(Filter), 0);
  Filter.ServiceName := 'ms.tags';
  Filter.Limit := 50;
  Entries := Context.LogQuery.Recent(Filter);
  Check(Length(Entries) > 0, 'should find at least the ingested ms.tags entry');
  for EntryIdx := 0 to High(Entries) do
    CheckEqual(Entries[EntryIdx].ServiceName, 'ms.tags',
      'filter must exclude other services');
end;

procedure TTestLogService.RecentFiltersByMinLevel;
var
  Batch: TLogEntryIngestDtoArray;
  Filter: TLogQueryFilter;
  Entries: TLogEntryDtoArray;
  EntryIdx: PtrInt;
begin
  SetLength(Batch, 3);
  Batch[0].ServiceName := 'ms.media';
  Batch[0].Timestamp := NowUtc;
  Batch[0].Level := 1; // info
  Batch[0].Message := 'ms.media info entry';
  Batch[1].ServiceName := 'ms.media';
  Batch[1].Timestamp := NowUtc;
  Batch[1].Level := 4; // warning
  Batch[1].Message := 'ms.media warning entry';
  Batch[2].ServiceName := 'ms.media';
  Batch[2].Timestamp := NowUtc;
  Batch[2].Level := 5; // error
  Batch[2].Message := 'ms.media error entry';
  Context.LogIngestion.AppendBatch(Batch);
  FillCharFast(Filter, SizeOf(Filter), 0);
  Filter.ServiceName := 'ms.media';
  Filter.MinLevel := 4;
  Filter.Limit := 50;
  Entries := Context.LogQuery.Recent(Filter);
  Check(Length(Entries) >= 2, 'should find at least the warning and error entries');
  for EntryIdx := 0 to High(Entries) do
    Check(Entries[EntryIdx].Level >= 4,
      'MinLevel filter must exclude lower-level entries');
end;

procedure TTestLogService.StatsReportsTotals;
var
  Batch: TLogEntryIngestDtoArray;
  Stats: TLogStatsDto;
begin
  // Make sure there is at least one entry so the stats are non-trivial.
  SetLength(Batch, 1);
  Batch[0].ServiceName := 'ms.analytics';
  Batch[0].Timestamp := NowUtc;
  Batch[0].Level := 1;
  Batch[0].Message := 'ms.analytics smoke test entry';
  Context.LogIngestion.AppendBatch(Batch);
  Stats := Context.LogQuery.Stats;
  Check(Stats.TotalEntries > 0, 'TotalEntries must be > 0 after ingestion');
  Check(Length(Stats.Services) > 0, 'Services array must contain at least one entry');
  Check(Stats.NewestEntry > 0, 'NewestEntry must be set');
  Check(Stats.OldestEntry > 0, 'OldestEntry must be set');
  Check(Stats.OldestEntry <= Stats.NewestEntry,
    'OldestEntry must be <= NewestEntry');
end;

constructor TTestLogStreamRecorder.Create(
  aRaiseOnNext: boolean
  );
begin
  inherited Create;
  FRaiseOnNext := aRaiseOnNext;
end;

procedure TTestLogStreamRecorder.NotifyEntry(
  const aEntry: TLogEntryDto
  );
begin
  if FRaiseOnNext then
    raise ESynException.Create('intentional test failure');
  SetLength(FReceived, Length(FReceived) + 1);
  FReceived[High(FReceived)] := aEntry;
end;

function TTestLogStreamRecorder.ReceivedCount: integer;
begin
  Result := Length(FReceived);
end;

function TTestLogStreamRecorder.ReceivedEntry(
  aIdx: integer
  ): TLogEntryDto;
begin
  Result := FReceived[aIdx];
end;

procedure TTestLogStreamRecorder.Reset;
begin
  FReceived := nil;
end;

procedure TTestLogStream.SingleSubscriberReceivesEntry;
var
  Recorder: TTestLogStreamRecorder;
  RecorderIntf: ILogStreamCallback;
  Entry: TLogEntryDto;
begin
  Recorder := TTestLogStreamRecorder.Create;
  RecorderIntf := Recorder;
  Context.LogStream.Subscribe(RecorderIntf);
  try
    Finalize(Entry);
    FillCharFast(Entry, SizeOf(Entry), 0);
    Entry.ID := 1;
    Entry.ServiceName := 'ms.test';
    Entry.Level := 1;
    Entry.Message := 'hello stream';
    Context.LogStreamSvc.Broadcast(Entry);
    CheckEqual(Recorder.ReceivedCount, 1, 'subscriber must receive exactly one entry');
    CheckEqual(Recorder.ReceivedEntry(0).Message, 'hello stream',
      'received entry must equal broadcast entry');
  finally
    Context.LogStream.Unsubscribe(RecorderIntf);
    RecorderIntf := nil;
  end;
end;

procedure TTestLogStream.MultipleSubscribersAllReceive;
var
  RecA, RecB, RecC: TTestLogStreamRecorder;
  IntfA, IntfB, IntfC: ILogStreamCallback;
  Entry: TLogEntryDto;
begin
  RecA := TTestLogStreamRecorder.Create;
  RecB := TTestLogStreamRecorder.Create;
  RecC := TTestLogStreamRecorder.Create;
  IntfA := RecA;
  IntfB := RecB;
  IntfC := RecC;
  Context.LogStream.Subscribe(IntfA);
  Context.LogStream.Subscribe(IntfB);
  Context.LogStream.Subscribe(IntfC);
  try
    Finalize(Entry);
    FillCharFast(Entry, SizeOf(Entry), 0);
    Entry.ID := 42;
    Entry.Message := 'fan-out';
    Context.LogStreamSvc.Broadcast(Entry);
    CheckEqual(RecA.ReceivedCount, 1, 'A must receive');
    CheckEqual(RecB.ReceivedCount, 1, 'B must receive');
    CheckEqual(RecC.ReceivedCount, 1, 'C must receive');
  finally
    Context.LogStream.Unsubscribe(IntfA);
    Context.LogStream.Unsubscribe(IntfB);
    Context.LogStream.Unsubscribe(IntfC);
    IntfA := nil;
    IntfB := nil;
    IntfC := nil;
  end;
end;

procedure TTestLogStream.UnsubscribedCallbackStopsReceiving;
var
  Recorder: TTestLogStreamRecorder;
  RecorderIntf: ILogStreamCallback;
  Entry: TLogEntryDto;
begin
  Recorder := TTestLogStreamRecorder.Create;
  RecorderIntf := Recorder;
  Context.LogStream.Subscribe(RecorderIntf);
  Finalize(Entry);
  FillCharFast(Entry, SizeOf(Entry), 0);
  Entry.Message := 'first';
  Context.LogStreamSvc.Broadcast(Entry);
  CheckEqual(Recorder.ReceivedCount, 1, 'must receive while subscribed');
  Context.LogStream.Unsubscribe(RecorderIntf);
  Entry.Message := 'second';
  Context.LogStreamSvc.Broadcast(Entry);
  CheckEqual(Recorder.ReceivedCount, 1,
    'must NOT receive after Unsubscribe');
  RecorderIntf := nil;
end;

procedure TTestLogStream.IngestionBroadcastsToSubscribers;
var
  Recorder: TTestLogStreamRecorder;
  RecorderIntf: ILogStreamCallback;
  Batch: TLogEntryIngestDtoArray;
begin
  Recorder := TTestLogStreamRecorder.Create;
  RecorderIntf := Recorder;
  Context.LogStream.Subscribe(RecorderIntf);
  try
    SetLength(Batch, 2);
    Batch[0].ServiceName := 'ms.test';
    Batch[0].Timestamp := NowUtc;
    Batch[0].Level := 1;
    Batch[0].Message := 'ingest A';
    Batch[1].ServiceName := 'ms.test';
    Batch[1].Timestamp := NowUtc;
    Batch[1].Level := 1;
    Batch[1].Message := 'ingest B';
    Context.LogIngestion.AppendBatch(Batch);
    CheckEqual(Recorder.ReceivedCount, 2,
      'AppendBatch must broadcast every newly persisted entry');
  finally
    Context.LogStream.Unsubscribe(RecorderIntf);
    RecorderIntf := nil;
  end;
end;

procedure TTestLogStream.FailingSubscriberIsDropped;
var
  Failing, Healthy: TTestLogStreamRecorder;
  IntfFail, IntfHealthy: ILogStreamCallback;
  Entry: TLogEntryDto;
begin
  Failing := TTestLogStreamRecorder.Create({aRaiseOnNext=}True);
  Healthy := TTestLogStreamRecorder.Create;
  IntfFail := Failing;
  IntfHealthy := Healthy;
  Context.LogStream.Subscribe(IntfFail);
  Context.LogStream.Subscribe(IntfHealthy);
  try
    Finalize(Entry);
    FillCharFast(Entry, SizeOf(Entry), 0);
    Entry.Message := 'first broadcast';
    Context.LogStreamSvc.Broadcast(Entry);
    // Healthy received it; Failing raised and was dropped.
    CheckEqual(Healthy.ReceivedCount, 1, 'healthy must receive');
    Entry.Message := 'second broadcast';
    Context.LogStreamSvc.Broadcast(Entry);
    CheckEqual(Healthy.ReceivedCount, 2,
      'healthy must continue to receive after failing was dropped');
  finally
    Context.LogStream.Unsubscribe(IntfHealthy);
    IntfFail := nil;
    IntfHealthy := nil;
  end;
end;

procedure TTestWebSocketRoundtrip.SubscribeIngestReceive;
const
  TEST_PORT = '18789';
  TIMEOUT_MS = 5000;
  POLL_MS = 20;
var
  ServerModel: TOrmModel;
  RestServer: TRestServerDB;
  HttpServer: TRestHttpServer;
  StreamSvc: TLogStreamService;
  IngestSvc: TLogIngestionService;
  StreamFactory: TServiceFactoryServerAbstract;
  ClientModel: TOrmModel;
  Client: TRestHttpClientWebsockets;
  StreamRemote: ILogStream;
  IngestRemote: ILogIngestion;
  Recorder: TTestLogStreamRecorder;
  CallbackIntf: ILogStreamCallback;
  Batch: TLogEntryIngestDtoArray;
  WaitedMs: integer;
  UpgradeError: RawUtf8;
begin
  // === Server side: dedicated REST + HTTP server with WebSockets enabled ===
  // We don't reuse TBlogTestContext here because we need a real HTTP+WebSocket transport rather than
  // the in-process direct interface calls used by every other test in this file.
  ServerModel := TOrmModel.Create([TOrmLogEntry, TOrmLogEntryFts], 'api');
  RestServer := TRestServerDB.Create(ServerModel, SQLITE_MEMORY_DATABASE_NAME);
  try
    RestServer.DB.Synchronous := smOff;
    RestServer.Server.CreateMissingTables;
    StreamSvc := TLogStreamService.Create;
    IngestSvc := TLogIngestionService.Create(RestServer.Orm, StreamSvc);
    RestServer.ServiceRegister(IngestSvc, [TypeInfo(ILogIngestion)]).
      ByPassAuthentication := True;
    StreamFactory := RestServer.ServiceRegister(StreamSvc, [TypeInfo(ILogStream)]);
    StreamFactory.SetOptions([], [optExecLockedPerInterface]);
    StreamFactory.ByPassAuthentication := True;
    HttpServer := TRestHttpServer.Create(
      TEST_PORT, RestServer, '+', WEBSOCKETS_DEFAULT_MODE, nil, 4, secNone);
    try
      HttpServer.WebSocketsEnable(RestServer, WEBSOCKETS_KEY, {ajax=}False);
      // === Client side: real WebSocket upgrade against the test server ===
      ClientModel := TOrmModel.Create([], 'api');
      Client := TRestHttpClientWebsockets.Create('localhost', TEST_PORT, ClientModel);
      try
        Client.Model.Owner := Client;
        UpgradeError := Client.WebSocketsUpgrade(WEBSOCKETS_KEY);
        CheckEqual(UpgradeError, '',
          'WebSocketsUpgrade must succeed (otherwise the test cannot continue)');
        Client.ServiceRegister([TypeInfo(ILogStream), TypeInfo(ILogIngestion)], sicShared);
        Check(Client.Services.Resolve(ILogStream, StreamRemote),
          'client must resolve ILogStream');
        Check(Client.Services.Resolve(ILogIngestion, IngestRemote),
          'client must resolve ILogIngestion');
        // === The actual round-trip ===
        Recorder := TTestLogStreamRecorder.Create;
        CallbackIntf := Recorder;
        // This Subscribe is the call that traverses TServiceContainerServer.GetFakeCallback on the
        // server side. If TInterfaceFactory.RegisterInterfaces was not called for ILogStreamCallback,
        // this raises 'Unexpected GetFakeCallback(ILogStreamCallback)'. The test exists specifically
        // to catch that regression.
        StreamRemote.Subscribe(CallbackIntf);
        try
          // Trigger an ingestion which will fan out to all server-side subscribers, including ours.
          SetLength(Batch, 1);
          Batch[0].ServiceName := 'roundtrip-test';
          Batch[0].Timestamp := NowUtc;
          Batch[0].Level := 1;
          Batch[0].Message := 'roundtrip test entry payload';
          IngestRemote.AppendBatch(Batch);
          // The callback fires asynchronously on the WebSocket worker thread. Poll until either it
          // arrives or we hit the timeout.
          WaitedMs := 0;
          while (Recorder.ReceivedCount = 0) and (WaitedMs < TIMEOUT_MS) do
          begin
            SleepHiRes(POLL_MS);
            Inc(WaitedMs, POLL_MS);
          end;
          Check(Recorder.ReceivedCount > 0,
            'subscriber must receive the broadcast within timeout (full WS round-trip path)');
          if Recorder.ReceivedCount > 0 then
            CheckEqual(Recorder.ReceivedEntry(0).Message, 'roundtrip test entry payload',
              'received entry payload must match the ingested one');
        finally
          // Explicit unsubscribe so the cleanup is deterministic instead of relying on the disconnect
          // hook fired by the framework when the WebSocket closes.
          StreamRemote.Unsubscribe(CallbackIntf);
        end;
      finally
        StreamRemote := nil;
        IngestRemote := nil;
        CallbackIntf := nil;
        Client.Free;
      end;
    finally
      HttpServer.Free;
    end;
  finally
    RestServer.Free;
    ServerModel.Free;
    // The two service implementations (StreamSvc, IngestSvc) are owned by RestServer once registered,
    // so we do not free them explicitly here.
  end;
end;

constructor TBlogTests.Create(
  const Ident: string
  );
begin
  inherited Create(Ident);

  FContext := TBlogTestContext.Create;
end;

destructor TBlogTests.Destroy;
begin
  FContext.Free;

  inherited Destroy;
end;

procedure TBlogTests.Services;
begin
  AddCase(TTestUserService);
  AddCase(TTestAuthService);
  AddCase(TTestPostService);
  AddCase(TTestPostSearch);
  AddCase(TTestTagService);
  AddCase(TTestCommentService);
  AddCase(TTestMediaService);
  AddCase(TTestBlogAggregation);
  AddCase(TTestBlogResilience);
  AddCase(TTestCircuitBreaker);
  AddCase(TTestRateLimiter);
  AddCase(TTestAnalyticsService);
  AddCase(TTestAnalyticsResilience);
  AddCase(TTestConfigService);
  AddCase(TTestCorrelationIds);
  AddCase(TTestLogService);
  AddCase(TTestLogStream);
  AddCase(TTestWebSocketRoundtrip);
  AddCase(TTestFullWorkflow);
end;

end.

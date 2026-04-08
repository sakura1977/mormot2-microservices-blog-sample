/// <summary>
///   Analytics microservice implementation. Demonstrates cross-service data aggregation -- the equivalent of SQL
///   JOINs across microservice boundaries. Connects directly to backend services and combines their data at runtime.
///
///   Two aggregation patterns are shown:
///   1. <em>Statistics</em>: counting and grouping data from multiple services (GetOverview, GetAuthorStats,
///      GetTagCloud, GetCommentActivity).
///   2. <em>Cross-Service JOINs</em>: enriching a list of records with related data from other services, including
///      an author cache to avoid duplicate lookups (GetRecentPostsFull).
/// </summary>
unit ms.analytics.server;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  System.SysUtils,
  mormot.core.base,
  mormot.core.json,
  mormot.core.log,
  mormot.core.os,
  mormot.core.rtti,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.variants,
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
  ms.shared.service;

type

  /// <summary>
  ///   Implements <c>IAnalytics</c> by querying backend services and aggregating their responses. Each method
  ///   demonstrates a different cross-service data combination pattern.
  /// </summary>
  TAnalyticsService = class(TInterfacedObject, IAnalytics)
  strict private

    /// <summary>
    ///   Interface to the posts backend service.
    /// </summary>
    FPosts: IPost;

    /// <summary>
    ///   Interface to the users backend service.
    /// </summary>
    FUsers: IUser;

    /// <summary>
    ///   Interface to the tags backend service.
    /// </summary>
    FTags: ITag;

    /// <summary>
    ///   Interface to the comments backend service.
    /// </summary>
    FComments: IComment;
  public

    /// <summary>
    ///   Creates the analytics service with injected backend service interfaces for testability.
    /// </summary>
    /// <param name="aPosts">
    ///   Posts service interface.
    /// </param>
    /// <param name="aUsers">
    ///   Users service interface.
    /// </param>
    /// <param name="aTags">
    ///   Tags service interface.
    /// </param>
    /// <param name="aComments">
    ///   Comments service interface.
    /// </param>
    constructor Create(
      const aPosts: IPost;
      const aUsers: IUser;
      const aTags: ITag;
      const aComments: IComment
      );

    /// <summary>
    ///   Returns aggregate counts from all services.
    /// </summary>
    /// <returns>
    ///   JSON object with count fields and optional <c>*Unavailable</c> flags.
    /// </returns>
    function GetOverview: RawJson;

    /// <summary>
    ///   Returns per-author statistics with post and comment counts.
    /// </summary>
    /// <returns>
    ///   JSON array of author stat objects.
    /// </returns>
    function GetAuthorStats: RawJson;

    /// <summary>
    ///   Returns comment activity: pending count and top commented posts.
    /// </summary>
    /// <returns>
    ///   JSON object with <c>pendingCount</c> and <c>topCommentedPosts</c> array.
    /// </returns>
    function GetCommentActivity: RawJson;

    /// <summary>
    ///   Returns the most recent published posts enriched with author, tags, and up to 10 comments per post.
    /// </summary>
    /// <param name="aLimit">
    ///   Maximum number of posts (clamped to 1..50).
    /// </param>
    /// <returns>
    ///   JSON array of enriched post objects.
    /// </returns>
    function GetRecentPostsFull(
      aLimit: integer
      ): RawJson;

    /// <summary>
    ///   Returns tags ranked by usage frequency.
    /// </summary>
    /// <returns>
    ///   JSON array sorted by <c>postCount</c> descending.
    /// </returns>
    function GetTagCloud: RawJson;
  end;

  /// <summary>
  ///   Microservice server hosting the <c>IAnalytics</c> service. Connects to backend services using the same
  ///   pattern as the gateway (TRestHttpClient + Services.Resolve).
  /// </summary>
  TAnalyticsServer = class(TMicroService)
  strict private

    /// <summary>
    ///   HTTP client for the posts backend service.
    /// </summary>
    FPostsClient: TRestHttpClient;

    /// <summary>
    ///   HTTP client for the users backend service.
    /// </summary>
    FUsersClient: TRestHttpClient;

    /// <summary>
    ///   HTTP client for the tags backend service.
    /// </summary>
    FTagsClient: TRestHttpClient;

    /// <summary>
    ///   HTTP client for the comments backend service.
    /// </summary>
    FCommentsClient: TRestHttpClient;

    /// <summary>
    ///   Resolved posts interface from the HTTP client.
    /// </summary>
    FPosts: IPost;

    /// <summary>
    ///   Resolved users interface from the HTTP client.
    /// </summary>
    FUsers: IUser;

    /// <summary>
    ///   Resolved tags interface from the HTTP client.
    /// </summary>
    FTags: ITag;

    /// <summary>
    ///   Resolved comments interface from the HTTP client.
    /// </summary>
    FComments: IComment;

    /// <summary>
    ///   Service registry from ms.config for host/port discovery.
    /// </summary>
    FServiceRegistry: TDocVariantData;

    /// <summary>
    ///   The analytics service implementation instance.
    /// </summary>
    FAnalyticsImpl: TAnalyticsService;

    /// <summary>
    ///   Creates an HTTP client connected to a backend service and registers the given SOA interfaces on it.
    /// </summary>
    /// <param name="aHost">
    ///   Backend hostname.
    /// </param>
    /// <param name="aPort">
    ///   Backend port.
    /// </param>
    /// <param name="aInterfaces">
    ///   RTTI pointers to the service interfaces.
    /// </param>
    /// <returns>
    ///   The configured HTTP client.
    /// </returns>
    function ConnectToBackend(
      const aHost, aPort: RawUtf8;
      const aInterfaces: array of PRttiInfo
      ): TRestHttpClient;

    /// <summary>
    ///   Looks up a field value in the service registry, falling back to the provided default if not found.
    /// </summary>
    /// <param name="aServiceName">
    ///   Service identifier to look up.
    /// </param>
    /// <param name="aField">
    ///   Field name ('Host' or 'Port').
    /// </param>
    /// <param name="aDefault">
    ///   Default value if not found in the registry.
    /// </param>
    /// <returns>
    ///   The resolved value.
    /// </returns>
    function RegistryLookup(
      const aServiceName, aField, aDefault: RawUtf8
      ): RawUtf8;
  protected

    /// <summary>
    ///   Creates an empty ORM model (no tables needed).
    /// </summary>
    /// <returns>
    ///   A new <c>TOrmModel</c> with no TOrm classes.
    /// </returns>
    function CreateModel: TOrmModel; override;

    /// <summary>
    ///   Releases backend interfaces before freeing clients.
    /// </summary>
    procedure DoFinalize; override;

    /// <summary>
    ///   Connects to backend services, resolves interfaces, and registers the <c>IAnalytics</c> service.
    /// </summary>
    procedure SetupServices; override;
  end;

implementation

constructor TAnalyticsService.Create(
  const aPosts: IPost;
  const aUsers: IUser;
  const aTags: ITag;
  const aComments: IComment
  );
begin
  inherited Create;
  FPosts := aPosts;
  FUsers := aUsers;
  FTags := aTags;
  FComments := aComments;
end;

function TAnalyticsService.GetAuthorStats: RawJson;
var
  AuthorsJson, PostsJson, CommentsJson: RawJson;
  AuthorArray, PostsResponse, CommentsArray: TDocVariantData;
  ResultArray, AuthorEntry: TDocVariantData;
  AuthorDoc, PostItem: TDocVariantData;
  PostItems: PDocVariantData;
  AuthorIdx, PostIdx: PtrInt;
  AuthorId, PostId: TID;
  PostCount, CommentTotal: integer;
begin
  try
    AuthorsJson := FUsers.GetAll;
  except
    Exit('[]');
  end;
  AuthorArray.InitJson(AuthorsJson, JSON_FAST_FLOAT);
  if AuthorArray.Kind <> dvArray then
    Exit('[]');
  ResultArray.InitArray([], JSON_FAST);
  for AuthorIdx := 0 to AuthorArray.Count - 1 do
  begin
    AuthorDoc.InitCopy(AuthorArray.Values[AuthorIdx], JSON_FAST_FLOAT);
    AuthorId := AuthorDoc.I['RowID'];
    if AuthorId = 0 then
      AuthorId := AuthorDoc.I['ID'];
    // Count posts for this author
    CommentTotal := 0;
    try
      PostsJson := FPosts.GetList(1, 100, 0, AuthorId);
      PostsResponse.InitJson(PostsJson, JSON_FAST_FLOAT);
      PostCount := PostsResponse.I['total'];
      // Count comments on each post
      PostItems := PostsResponse.A['items'];
      if PostItems <> nil then
      begin
        for PostIdx := 0 to PostItems^.Count - 1 do
        begin
          PostItem.InitCopy(PostItems^.Values[PostIdx], JSON_FAST_FLOAT);
          PostId := PostItem.I['RowID'];
          if PostId = 0 then
            PostId := PostItem.I['ID'];
          try
            CommentsJson := FComments.GetByPost(PostId);
            CommentsArray.InitJson(CommentsJson, JSON_FAST_FLOAT);
            if CommentsArray.Kind = dvArray then
              CommentTotal := CommentTotal + CommentsArray.Count;
          except
            // Comments service unavailable for this post
          end;
        end;
      end;
    except
      PostCount := -1;
    end;
    AuthorEntry.InitObject([
      'authorId', AuthorId,
      'displayName', AuthorDoc.U['DisplayName'],
      'postCount', PostCount,
      'commentCount', CommentTotal
    ], JSON_FAST);
    ResultArray.AddItem(variant(AuthorEntry));
  end;
  Result := ResultArray.ToJson;
end;

function TAnalyticsService.GetCommentActivity: RawJson;
var
  PendingJson, PostsJson, CommentsJson: RawJson;
  PendingArray, PostsResponse, CommentsArray: TDocVariantData;
  ResultDoc, TopPostsArray, PostEntry, PostDoc: TDocVariantData;
  PostItems: PDocVariantData;
  PendingCount, CommentCount: integer;
  PostIdx, SortIdx, SwapIdx: PtrInt;
  PostId: TID;
  SwapVariant: variant;
  BestCount, CurrentCount: integer;
begin
  // Count pending comments
  PendingCount := 0;
  try
    PendingJson := FComments.GetPending;
    PendingArray.InitJson(PendingJson, JSON_FAST_FLOAT);
    if PendingArray.Kind = dvArray then
      PendingCount := PendingArray.Count;
  except
    PendingCount := -1;
  end;
  // Find top commented posts
  TopPostsArray.InitArray([], JSON_FAST);
  try
    PostsJson := FPosts.GetList(1, 50, POST_STATUS_PUBLISHED, 0);
    PostsResponse.InitJson(PostsJson, JSON_FAST_FLOAT);
    PostItems := PostsResponse.A['items'];
    if PostItems <> nil then
    begin
      for PostIdx := 0 to PostItems^.Count - 1 do
      begin
        PostDoc.InitCopy(PostItems^.Values[PostIdx], JSON_FAST_FLOAT);
        PostId := PostDoc.I['RowID'];
        if PostId = 0 then
          PostId := PostDoc.I['ID'];
        CommentCount := 0;
        try
          CommentsJson := FComments.GetByPost(PostId);
          CommentsArray.InitJson(CommentsJson, JSON_FAST_FLOAT);
          if CommentsArray.Kind = dvArray then
            CommentCount := CommentsArray.Count;
        except
          // Comments unavailable for this post
        end;
        if CommentCount > 0 then
        begin
          PostEntry.InitObject([
            'postId', PostId,
            'title', PostDoc.U['Title'],
            'commentCount', CommentCount
          ], JSON_FAST);
          TopPostsArray.AddItem(variant(PostEntry));
        end;
      end;
    end;
  except
    // Posts service unavailable
  end;
  // Sort by commentCount descending (selection sort, small data)
  for SortIdx := 0 to TopPostsArray.Count - 2 do
  begin
    BestCount := _Safe(TopPostsArray.Values[SortIdx])^.I['commentCount'];
    SwapIdx := SortIdx;
    for PostIdx := SortIdx + 1 to TopPostsArray.Count - 1 do
    begin
      CurrentCount := _Safe(TopPostsArray.Values[PostIdx])^.I['commentCount'];
      if CurrentCount > BestCount then
      begin
        BestCount := CurrentCount;
        SwapIdx := PostIdx;
      end;
    end;
    if SwapIdx <> SortIdx then
    begin
      SwapVariant := TopPostsArray.Values[SortIdx];
      TopPostsArray.Values[SortIdx] := TopPostsArray.Values[SwapIdx];
      TopPostsArray.Values[SwapIdx] := SwapVariant;
    end;
  end;
  // Limit to top 10
  while TopPostsArray.Count > 10 do
    TopPostsArray.Delete(TopPostsArray.Count - 1);
  ResultDoc.InitObject([
    'pendingCount', PendingCount,
    'topCommentedPosts', variant(TopPostsArray)
  ], JSON_FAST);
  Result := ResultDoc.ToJson;
end;

function TAnalyticsService.GetOverview: RawJson;
var
  PostsJson, AuthorsJson, TagsJson, PendingJson: RawJson;
  PostsResponse, AuthorArray, TagArray, PendingArray: TDocVariantData;
  ResultDoc: TDocVariantData;
  PostTotal, AuthorCount, TagCount, PendingCount: integer;
begin
  ResultDoc.InitObject([], JSON_FAST);
  // Posts count -- GetList returns {"total":N} without loading all items
  try
    PostsJson := FPosts.GetList(1, 1, 0, 0);
    PostsResponse.InitJson(PostsJson, JSON_FAST_FLOAT);
    PostTotal := PostsResponse.I['total'];
  except
    PostTotal := -1;
    ResultDoc.B['postsUnavailable'] := True;
  end;
  ResultDoc.I['posts'] := PostTotal;
  // Authors count
  AuthorCount := 0;
  try
    AuthorsJson := FUsers.GetAll;
    AuthorArray.InitJson(AuthorsJson, JSON_FAST_FLOAT);
    if AuthorArray.Kind = dvArray then
      AuthorCount := AuthorArray.Count;
  except
    AuthorCount := -1;
    ResultDoc.B['authorsUnavailable'] := True;
  end;
  ResultDoc.I['authors'] := AuthorCount;
  // Tags count
  TagCount := 0;
  try
    TagsJson := FTags.GetAll;
    TagArray.InitJson(TagsJson, JSON_FAST_FLOAT);
    if TagArray.Kind = dvArray then
      TagCount := TagArray.Count;
  except
    TagCount := -1;
    ResultDoc.B['tagsUnavailable'] := True;
  end;
  ResultDoc.I['tags'] := TagCount;
  // Pending comments count
  PendingCount := 0;
  try
    PendingJson := FComments.GetPending;
    PendingArray.InitJson(PendingJson, JSON_FAST_FLOAT);
    if PendingArray.Kind = dvArray then
      PendingCount := PendingArray.Count;
  except
    PendingCount := -1;
    ResultDoc.B['commentsUnavailable'] := True;
  end;
  ResultDoc.I['pendingComments'] := PendingCount;
  Result := ResultDoc.ToJson;
end;

function TAnalyticsService.GetRecentPostsFull(
  aLimit: integer
  ): RawJson;
const
  MAX_COMMENTS_PER_POST = 10;
var
  PostsJson, AuthorJson, TagsJson, CommentsJson: RawJson;
  PostsResponse, PostDoc, AuthorCache: TDocVariantData;
  CommentsArray, LimitedComments: TDocVariantData;
  ResultArray: TDocVariantData;
  PostItems: PDocVariantData;
  PostIdx, CommentIdx: PtrInt;
  PostId, AuthorId: TID;
  AuthorIdKey: RawUtf8;
  CachedAuthorIdx: PtrInt;
begin
  // Clamp limit
  if aLimit < 1 then
    aLimit := 5;
  if aLimit > 50 then
    aLimit := 50;
  // Step 1: fetch recent published posts
  try
    PostsJson := FPosts.GetList(1, aLimit, POST_STATUS_PUBLISHED, 0);
  except
    Exit('[]');
  end;
  PostsResponse.InitJson(PostsJson, JSON_FAST_FLOAT);
  PostItems := PostsResponse.A['items'];
  if (PostItems = nil) or (PostItems^.Count = 0) then
    Exit('[]');
  // Step 2: build author cache (avoid duplicate lookups)
  AuthorCache.InitObject([], JSON_FAST);
  for PostIdx := 0 to PostItems^.Count - 1 do
  begin
    PostDoc.InitCopy(PostItems^.Values[PostIdx], JSON_FAST_FLOAT);
    AuthorId := PostDoc.I['AuthorId'];
    AuthorIdKey := Int64ToUtf8(AuthorId);
    if AuthorCache.GetValueIndex(AuthorIdKey) < 0 then
    begin
      try
        AuthorJson := FUsers.Get(AuthorId);
        if AuthorJson <> '{}' then
          AuthorCache.AddValue(AuthorIdKey, _JsonFast(AuthorJson))
        else
          AuthorCache.AddValue(AuthorIdKey, null);
      except
        AuthorCache.AddValue(AuthorIdKey, null);
      end;
    end;
  end;
  // Step 3: enrich each post (the cross-service JOIN)
  ResultArray.InitArray([], JSON_FAST);
  for PostIdx := 0 to PostItems^.Count - 1 do
  begin
    PostDoc.InitCopy(PostItems^.Values[PostIdx], JSON_FAST_FLOAT);
    PostId := PostDoc.I['RowID'];
    if PostId = 0 then
      PostId := PostDoc.I['ID'];
    AuthorId := PostDoc.I['AuthorId'];
    // Author from cache
    AuthorIdKey := Int64ToUtf8(AuthorId);
    CachedAuthorIdx := AuthorCache.GetValueIndex(AuthorIdKey);
    if CachedAuthorIdx >= 0 then
      PostDoc.AddValue('Author', AuthorCache.Values[CachedAuthorIdx])
    else
      PostDoc.AddValue('Author', null);
    // Tags (graceful degradation)
    try
      TagsJson := FTags.GetByPost(PostId);
      if TagsJson <> '[]' then
        PostDoc.AddValue('Tags', _JsonFast(TagsJson))
      else
        PostDoc.AddValue('Tags', _ArrFast([]));
    except
      PostDoc.AddValue('Tags', _ArrFast([]));
      PostDoc.B['TagsUnavailable'] := True;
    end;
    // Comments with limit (graceful degradation)
    try
      CommentsJson := FComments.GetByPost(PostId);
      CommentsArray.InitJson(CommentsJson, JSON_FAST_FLOAT);
      if (CommentsArray.Kind = dvArray)
        and (CommentsArray.Count > MAX_COMMENTS_PER_POST) then
      begin
        // Take only the last MAX_COMMENTS_PER_POST entries
        LimitedComments.InitArray([], JSON_FAST);
        for CommentIdx := CommentsArray.Count - MAX_COMMENTS_PER_POST
          to CommentsArray.Count - 1 do
        begin
          LimitedComments.AddItem(CommentsArray.Values[CommentIdx]);
        end;
        PostDoc.AddValue('Comments', variant(LimitedComments));
      end
      else if CommentsJson <> '[]' then
        PostDoc.AddValue('Comments', _JsonFast(CommentsJson))
      else
        PostDoc.AddValue('Comments', _ArrFast([]));
    except
      PostDoc.AddValue('Comments', _ArrFast([]));
      PostDoc.B['CommentsUnavailable'] := True;
    end;
    ResultArray.AddItem(_JsonFast(RawUtf8(PostDoc.ToJson)));
  end;
  Result := ResultArray.ToJson;
end;

function TAnalyticsService.GetTagCloud: RawJson;
var
  TagsJson, PostIdsJson: RawJson;
  TagArray, PostIdsArray: TDocVariantData;
  ResultArray, TagEntry, TagDoc: TDocVariantData;
  TagIdx, SortIdx, SwapIdx: PtrInt;
  TagId, PostCount: integer;
  BestCount, CurrentCount: integer;
  SwapVariant: variant;
begin
  try
    TagsJson := FTags.GetAll;
  except
    Exit('[]');
  end;
  TagArray.InitJson(TagsJson, JSON_FAST_FLOAT);
  if TagArray.Kind <> dvArray then
    Exit('[]');
  ResultArray.InitArray([], JSON_FAST);
  for TagIdx := 0 to TagArray.Count - 1 do
  begin
    TagDoc.InitCopy(TagArray.Values[TagIdx], JSON_FAST_FLOAT);
    TagId := TagDoc.I['RowID'];
    if TagId = 0 then
      TagId := TagDoc.I['ID'];
    PostCount := 0;
    try
      PostIdsJson := FTags.GetPostIds(TagId);
      PostIdsArray.InitJson(PostIdsJson, JSON_FAST_FLOAT);
      if PostIdsArray.Kind = dvArray then
        PostCount := PostIdsArray.Count;
    except
      // Tag post count unavailable
    end;
    TagEntry.InitObject([
      'tagId', TagId,
      'name', TagDoc.U['Name'],
      'slug', TagDoc.U['Slug'],
      'postCount', PostCount
    ], JSON_FAST);
    ResultArray.AddItem(variant(TagEntry));
  end;
  // Sort by postCount descending (selection sort)
  for SortIdx := 0 to ResultArray.Count - 2 do
  begin
    BestCount := _Safe(ResultArray.Values[SortIdx])^.I['postCount'];
    SwapIdx := SortIdx;
    for TagIdx := SortIdx + 1 to ResultArray.Count - 1 do
    begin
      CurrentCount := _Safe(ResultArray.Values[TagIdx])^.I['postCount'];
      if CurrentCount > BestCount then
      begin
        BestCount := CurrentCount;
        SwapIdx := TagIdx;
      end;
    end;
    if SwapIdx <> SortIdx then
    begin
      SwapVariant := ResultArray.Values[SortIdx];
      ResultArray.Values[SortIdx] := ResultArray.Values[SwapIdx];
      ResultArray.Values[SwapIdx] := SwapVariant;
    end;
  end;
  Result := ResultArray.ToJson;
end;

function TAnalyticsServer.ConnectToBackend(
  const aHost, aPort: RawUtf8;
  const aInterfaces: array of PRttiInfo
  ): TRestHttpClient;
var
  ClientModel: TOrmModel;
  InterfaceIdx: PtrInt;
begin
  ClientModel := TOrmModel.Create([], MODEL_ROOT);
  Result := TRestHttpClient.Create(aHost, aPort, ClientModel);
  Result.Model.Owner := Result;
  Result.ServiceRegister(aInterfaces, sicShared);
  for InterfaceIdx := 0 to High(aInterfaces) do
  begin
    TServiceFactoryClient(Result.Services.Info(aInterfaces[InterfaceIdx])).ResultAsJsonObjectWithoutResult := True;
  end;
end;

function TAnalyticsServer.CreateModel: TOrmModel;
begin
  Result := TOrmModel.Create([], MODEL_ROOT);
end;

procedure TAnalyticsServer.DoFinalize;
begin
  FPosts := nil;
  FUsers := nil;
  FTags := nil;
  FComments := nil;
  FreeAndNil(FCommentsClient);
  FreeAndNil(FTagsClient);
  FreeAndNil(FPostsClient);
  FreeAndNil(FUsersClient);
end;

function TAnalyticsServer.RegistryLookup(
  const aServiceName, aField, aDefault: RawUtf8
  ): RawUtf8;
var
  RegistryEntry: PDocVariantData;
begin
  RegistryEntry := FServiceRegistry.O[aServiceName];
  if (RegistryEntry <> nil) and (RegistryEntry^.U[aField] <> '') then
    Exit(RegistryEntry^.U[aField]);
  Result := aDefault;
end;

procedure TAnalyticsServer.SetupServices;

  procedure LoadServiceRegistry;
  var
    Bootstrap: TBootstrapConfig;
    ConfigClientModel: TOrmModel;
    ConfigClient: TRestHttpClient;
    ConfigIntf: IConfig;
    ConfigHost, ConfigPort: RawUtf8;
    RegistryJson: RawUtf8;
  begin
    FServiceRegistry.InitObject([], JSON_FAST);
    Bootstrap := LoadBootstrapConfig(SERVICE_ANALYTICS);
    if Bootstrap.ConfigUrl = '' then
      Exit;
    ConfigHost := Bootstrap.ConfigUrl;
    if IdemPChar(pointer(ConfigHost), 'HTTP://') then
      Delete(ConfigHost, 1, 7)
    else if IdemPChar(pointer(ConfigHost), 'HTTPS://') then
      Delete(ConfigHost, 1, 8);
    ConfigPort := Split(ConfigHost, ':', ConfigHost);
    if ConfigPort = '' then
    begin
      ConfigPort := ConfigHost;
      ConfigHost := 'localhost';
    end;
    try
      ConfigClientModel := TOrmModel.Create([], MODEL_ROOT);
      ConfigClient := TRestHttpClient.Create(ConfigHost, ConfigPort, ConfigClientModel);
      try
        ConfigClient.Model.Owner := ConfigClient;
        ConfigClient.ServiceRegister([TypeInfo(IConfig)], sicShared);
        TServiceFactoryClient(ConfigClient.Services.Info(TypeInfo(IConfig))).ResultAsJsonObjectWithoutResult := True;
        if ConfigClient.Services.Resolve(IConfig, ConfigIntf) then
        begin
          RegistryJson := ConfigIntf.GetServiceRegistry;
          if RegistryJson <> '' then
            FServiceRegistry.InitJson(RegistryJson, JSON_FAST_FLOAT);
        end;
      finally
        ConfigIntf := nil;
        ConfigClient.Free;
      end;
    except
      // Config service unavailable -- use defaults
    end;
  end;

begin
  LoadServiceRegistry;
  // Connect to backend services using registry or defaults
  FPostsClient := ConnectToBackend(
    RegistryLookup(SERVICE_POSTS, 'Host', 'localhost'),
    RegistryLookup(SERVICE_POSTS, 'Port', PORT_POSTS),
    [TypeInfo(IPost)]);
  FPostsClient.Services.Resolve(IPost, FPosts);
  FUsersClient := ConnectToBackend(
    RegistryLookup(SERVICE_USERS, 'Host', 'localhost'),
    RegistryLookup(SERVICE_USERS, 'Port', PORT_USERS),
    [TypeInfo(IUser)]);
  FUsersClient.Services.Resolve(IUser, FUsers);
  FTagsClient := ConnectToBackend(
    RegistryLookup(SERVICE_TAGS, 'Host', 'localhost'),
    RegistryLookup(SERVICE_TAGS, 'Port', PORT_TAGS),
    [TypeInfo(ITag)]);
  FTagsClient.Services.Resolve(ITag, FTags);
  FCommentsClient := ConnectToBackend(
    RegistryLookup(SERVICE_COMMENTS, 'Host', 'localhost'),
    RegistryLookup(SERVICE_COMMENTS, 'Port', PORT_COMMENTS),
    [TypeInfo(IComment)]);
  FCommentsClient.Services.Resolve(IComment, FComments);
  // Create analytics service with injected interfaces
  FAnalyticsImpl := TAnalyticsService.Create(FPosts, FUsers, FTags, FComments);
  RegisterService(FAnalyticsImpl, TypeInfo(IAnalytics));
end;

end.

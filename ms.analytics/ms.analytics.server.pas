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

    /// <summary>
    ///   Copies all scalar fields from a <c>TPostDto</c> into a <c>TPostFullDto</c>. The nested Author, Tags,
    ///   Comments and *Unavailable flags are left at their default (zero/empty/false) values.
    /// </summary>
    /// <param name="aPost">
    ///   Source post record.
    /// </param>
    /// <returns>
    ///   A <c>TPostFullDto</c> with scalar fields populated.
    /// </returns>
    function PostDtoToFull(
      const aPost: TPostDto
      ): TPostFullDto;
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
    ///   Overview with count fields and <c>*Unavailable</c> flags for unreachable services.
    /// </returns>
    function GetOverview: TOverviewDto;

    /// <summary>
    ///   Returns per-author statistics with post and comment counts.
    /// </summary>
    /// <returns>
    ///   Array of author stat records, or empty array if users service is unavailable.
    /// </returns>
    function GetAuthorStats: TAuthorStatDtoArray;

    /// <summary>
    ///   Returns comment activity: pending count and top commented posts.
    /// </summary>
    /// <returns>
    ///   Comment activity overview with pending count and top 10 most-commented posts.
    /// </returns>
    function GetCommentActivity: TCommentActivityDto;

    /// <summary>
    ///   Returns the most recent published posts enriched with author, tags, and up to 10 comments per post.
    /// </summary>
    /// <param name="aLimit">
    ///   Maximum number of posts (clamped to 1..50). Pass 0 for empty result.
    /// </param>
    /// <returns>
    ///   Array of enriched post records, or empty array if unavailable or limit is 0.
    /// </returns>
    function GetRecentPostsFull(
      aLimit: integer
      ): TPostFullDtoArray;

    /// <summary>
    ///   Returns tags ranked by usage frequency.
    /// </summary>
    /// <returns>
    ///   Array of tag cloud items sorted descending by usage.
    /// </returns>
    function GetTagCloud: TTagCloudItemDtoArray;
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

function TAnalyticsService.PostDtoToFull(
  const aPost: TPostDto
  ): TPostFullDto;
begin
  Finalize(Result);
  FillCharFast(Result, SizeOf(Result), 0);
  Result.ID := aPost.ID;
  Result.Title := aPost.Title;
  Result.Slug := aPost.Slug;
  Result.Body := aPost.Body;
  Result.Excerpt := aPost.Excerpt;
  Result.AuthorId := aPost.AuthorId;
  Result.FeaturedImageId := aPost.FeaturedImageId;
  Result.MetaTitle := aPost.MetaTitle;
  Result.MetaDescription := aPost.MetaDescription;
  Result.MetaKeywords := aPost.MetaKeywords;
  Result.Status := aPost.Status;
  Result.PublishedAt := aPost.PublishedAt;
  Result.CreatedAt := aPost.CreatedAt;
  Result.UpdatedAt := aPost.UpdatedAt;
end;

function TAnalyticsService.GetAuthorStats: TAuthorStatDtoArray;
var
  Authors: TAuthorDtoArray;
  PostList: TPostListDto;
  PostComments: TCommentDtoArray;
  AuthorIdx, PostIdx: PtrInt;
  CommentTotal: integer;
begin
  Result := nil;
  try
    Authors := FUsers.GetAll;
  except
    Exit(nil);
  end;
  if Length(Authors) = 0 then
    Exit(nil);
  SetLength(Result, Length(Authors));
  for AuthorIdx := 0 to High(Authors) do
  begin
    Result[AuthorIdx].AuthorId := Authors[AuthorIdx].ID;
    Result[AuthorIdx].DisplayName := Authors[AuthorIdx].DisplayName;
    // Count posts for this author
    CommentTotal := 0;
    try
      PostList := FPosts.GetList(1, 100, 0, Authors[AuthorIdx].ID);
      Result[AuthorIdx].PostCount := PostList.Total;
      // Count comments on each post
      for PostIdx := 0 to High(PostList.Items) do
      begin
        try
          PostComments := FComments.GetByPost(PostList.Items[PostIdx].ID);
          CommentTotal := CommentTotal + Length(PostComments);
        except
          // Comments service unavailable for this post
        end;
      end;
    except
      Result[AuthorIdx].PostCount := -1;
    end;
    Result[AuthorIdx].CommentCount := CommentTotal;
  end;
end;

function TAnalyticsService.GetCommentActivity: TCommentActivityDto;
var
  PostList: TPostListDto;
  PostComments: TCommentDtoArray;
  CommentCount: integer;
  PostIdx, SortIdx, SwapIdx, EntryCount, TopLimit: PtrInt;
  BestCount, CurrentCount: integer;
  SwapEntry: TTopCommentedPostDto;
begin
  Finalize(Result);
  FillCharFast(Result, SizeOf(Result), 0);
  // Count pending comments
  try
    Result.PendingCount := Length(FComments.GetPending);
  except
    Result.PendingCount := -1;
  end;
  // Find top commented posts
  EntryCount := 0;
  try
    PostList := FPosts.GetList(1, 50, POST_STATUS_PUBLISHED, 0);
    SetLength(Result.TopCommentedPosts, Length(PostList.Items));
    for PostIdx := 0 to High(PostList.Items) do
    begin
      CommentCount := 0;
      try
        PostComments := FComments.GetByPost(PostList.Items[PostIdx].ID);
        CommentCount := Length(PostComments);
      except
        // Comments unavailable for this post
      end;
      if CommentCount > 0 then
      begin
        Result.TopCommentedPosts[EntryCount].PostId := PostList.Items[PostIdx].ID;
        Result.TopCommentedPosts[EntryCount].Title := PostList.Items[PostIdx].Title;
        Result.TopCommentedPosts[EntryCount].CommentCount := CommentCount;
        Inc(EntryCount);
      end;
    end;
    SetLength(Result.TopCommentedPosts, EntryCount);
  except
    // Posts service unavailable
  end;
  // Sort by CommentCount descending (selection sort, small data)
  for SortIdx := 0 to EntryCount - 2 do
  begin
    BestCount := Result.TopCommentedPosts[SortIdx].CommentCount;
    SwapIdx := SortIdx;
    for PostIdx := SortIdx + 1 to EntryCount - 1 do
    begin
      CurrentCount := Result.TopCommentedPosts[PostIdx].CommentCount;
      if CurrentCount > BestCount then
      begin
        BestCount := CurrentCount;
        SwapIdx := PostIdx;
      end;
    end;
    if SwapIdx <> SortIdx then
    begin
      SwapEntry := Result.TopCommentedPosts[SortIdx];
      Result.TopCommentedPosts[SortIdx] := Result.TopCommentedPosts[SwapIdx];
      Result.TopCommentedPosts[SwapIdx] := SwapEntry;
    end;
  end;
  // Limit to top 10
  TopLimit := 10;
  if EntryCount > TopLimit then
    SetLength(Result.TopCommentedPosts, TopLimit);
end;

function TAnalyticsService.GetOverview: TOverviewDto;
var
  PostList: TPostListDto;
begin
  FillCharFast(Result, SizeOf(Result), 0);
  // Posts count -- GetList returns Total without loading all items
  try
    PostList := FPosts.GetList(1, 1, 0, 0);
    Result.Posts := PostList.Total;
  except
    Result.Posts := -1;
    Result.PostsUnavailable := True;
  end;
  // Authors count
  try
    Result.Authors := Length(FUsers.GetAll);
  except
    Result.Authors := -1;
    Result.AuthorsUnavailable := True;
  end;
  // Tags count
  try
    Result.Tags := Length(FTags.GetAll);
  except
    Result.Tags := -1;
    Result.TagsUnavailable := True;
  end;
  // Pending comments count
  try
    Result.PendingComments := Length(FComments.GetPending);
  except
    Result.PendingComments := -1;
    Result.CommentsUnavailable := True;
  end;
end;

function TAnalyticsService.GetRecentPostsFull(
  aLimit: integer
  ): TPostFullDtoArray;
const
  MAX_COMMENTS_PER_POST = 10;
var
  PostList: TPostListDto;
  AuthorDto: TAuthorDto;
  AllComments: TCommentDtoArray;
  PostIdx, CommentIdx, CommentStart: PtrInt;
  AuthorCache: array of TAuthorDto;
  AuthorCacheIds: TIDDynArray;
  CacheIdx: PtrInt;
  AuthorFound: boolean;
begin
  Result := nil;
  // Zero or negative limit returns empty
  if aLimit < 1 then
    Exit(nil);
  if aLimit > 50 then
    aLimit := 50;
  // Step 1: fetch recent published posts
  try
    PostList := FPosts.GetList(1, aLimit, POST_STATUS_PUBLISHED, 0);
  except
    Exit(nil);
  end;
  if Length(PostList.Items) = 0 then
    Exit(nil);
  // Step 2: build author cache (avoid duplicate lookups)
  AuthorCache := nil;
  AuthorCacheIds := nil;
  for PostIdx := 0 to High(PostList.Items) do
  begin
    AuthorFound := False;
    for CacheIdx := 0 to High(AuthorCacheIds) do
    begin
      if AuthorCacheIds[CacheIdx] = PostList.Items[PostIdx].AuthorId then
      begin
        AuthorFound := True;
        Break;
      end;
    end;
    if not AuthorFound then
    begin
      Finalize(AuthorDto);
      FillCharFast(AuthorDto, SizeOf(AuthorDto), 0);
      try
        AuthorDto := FUsers.Get(PostList.Items[PostIdx].AuthorId);
      except
        // Author service unavailable -- AuthorDto.ID stays 0
      end;
      SetLength(AuthorCache, Length(AuthorCache) + 1);
      AuthorCache[High(AuthorCache)] := AuthorDto;
      SetLength(AuthorCacheIds, Length(AuthorCacheIds) + 1);
      AuthorCacheIds[High(AuthorCacheIds)] := PostList.Items[PostIdx].AuthorId;
    end;
  end;
  // Step 3: enrich each post (the cross-service JOIN)
  SetLength(Result, Length(PostList.Items));
  for PostIdx := 0 to High(PostList.Items) do
  begin
    Result[PostIdx] := PostDtoToFull(PostList.Items[PostIdx]);
    // Author from cache
    for CacheIdx := 0 to High(AuthorCacheIds) do
    begin
      if AuthorCacheIds[CacheIdx] = PostList.Items[PostIdx].AuthorId then
      begin
        Result[PostIdx].Author := AuthorCache[CacheIdx];
        if AuthorCache[CacheIdx].ID = 0 then
          Result[PostIdx].AuthorUnavailable := True;
        Break;
      end;
    end;
    // Tags (graceful degradation)
    try
      Result[PostIdx].Tags := FTags.GetByPost(PostList.Items[PostIdx].ID);
    except
      Result[PostIdx].Tags := nil;
      Result[PostIdx].TagsUnavailable := True;
    end;
    // Comments with limit (graceful degradation)
    try
      AllComments := FComments.GetByPost(PostList.Items[PostIdx].ID);
      if Length(AllComments) > MAX_COMMENTS_PER_POST then
      begin
        // Take only the last MAX_COMMENTS_PER_POST entries
        CommentStart := Length(AllComments) - MAX_COMMENTS_PER_POST;
        SetLength(Result[PostIdx].Comments, MAX_COMMENTS_PER_POST);
        for CommentIdx := 0 to MAX_COMMENTS_PER_POST - 1 do
          Result[PostIdx].Comments[CommentIdx] := AllComments[CommentStart + CommentIdx];
      end
      else
        Result[PostIdx].Comments := AllComments;
    except
      Result[PostIdx].Comments := nil;
      Result[PostIdx].CommentsUnavailable := True;
    end;
  end;
end;

function TAnalyticsService.GetTagCloud: TTagCloudItemDtoArray;
var
  AllTags: TTagDtoArray;
  PostIds: TIDDynArray;
  TagIdx, SortIdx, SwapIdx: PtrInt;
  BestCount, CurrentCount: integer;
  SwapEntry: TTagCloudItemDto;
begin
  Result := nil;
  try
    AllTags := FTags.GetAll;
  except
    Exit(nil);
  end;
  if Length(AllTags) = 0 then
    Exit(nil);
  SetLength(Result, Length(AllTags));
  for TagIdx := 0 to High(AllTags) do
  begin
    Result[TagIdx].TagId := AllTags[TagIdx].ID;
    Result[TagIdx].Name := AllTags[TagIdx].Name;
    Result[TagIdx].Slug := AllTags[TagIdx].Slug;
    try
      PostIds := FTags.GetPostIds(AllTags[TagIdx].ID);
      Result[TagIdx].PostCount := Length(PostIds);
    except
      // Tag post count unavailable
    end;
  end;
  // Sort by PostCount descending (selection sort)
  for SortIdx := 0 to High(Result) - 1 do
  begin
    BestCount := Result[SortIdx].PostCount;
    SwapIdx := SortIdx;
    for TagIdx := SortIdx + 1 to High(Result) do
    begin
      CurrentCount := Result[TagIdx].PostCount;
      if CurrentCount > BestCount then
      begin
        BestCount := CurrentCount;
        SwapIdx := TagIdx;
      end;
    end;
    if SwapIdx <> SortIdx then
    begin
      SwapEntry := Result[SortIdx];
      Result[SortIdx] := Result[SwapIdx];
      Result[SwapIdx] := SwapEntry;
    end;
  end;
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

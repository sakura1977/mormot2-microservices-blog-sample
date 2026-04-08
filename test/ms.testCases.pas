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
  mormot.core.base,
  mormot.core.buffers,
  mormot.core.datetime,
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
  mormot.orm.base,
  mormot.orm.core,
  mormot.rest.core,
  mormot.rest.server,
  mormot.rest.sqlite3,
  mormot.soa.core,
  mormot.soa.server,
  ms.shared,
  ms.shared.api,
  ms.shared.jwt,
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
  ms.gateway.server;

type

  /// Shared test context: single in-memory database with all services
  TBlogTestContext = class
  private
    FModel: TOrmModel;
    FRestServer: TRestServerDB;
    FJwt: TBlogJwt;
    FMediaPath: TFileName;
    FAuthImpl: TAuthService;
    FUserImpl: TUserService;
    FPostImpl: TPostService;
    FTagImpl: TTagService;
    FCommentImpl: TCommentService;
    FMediaImpl: TMediaService;
    FBlogImpl: TBlogService;
  public
    Auth: IAuth;
    User: IUser;
    Post: IPost;
    Tag: ITag;
    Comment: IComment;
    Media: IMedia;
    Blog: IBlog;
    constructor Create;
    destructor Destroy; override;
  end;

  TMsTestCase = class(TSynTestCase)
  protected
    function Context: TBlogTestContext;
  end;

  TTestUserService = class(TMsTestCase)
  published
    procedure AddAndGet;
    procedure AddEmptyName;
    procedure GetNotFound;
    procedure Update;
    procedure UpdateNotFound;
    procedure GetAll;
    procedure Remove;
    procedure RemoveNotFound;
  end;

  TTestAuthService = class(TMsTestCase)
  published
    procedure RegisterUser;
    procedure RegisterDuplicate;
    procedure RegisterEmptyEmail;
    procedure RegisterEmptyPassword;
    procedure ChallengeAndAuthenticate;
    procedure AuthenticateWrongPassword;
    procedure AuthenticateUnknownEmail;
    procedure AuthenticateReplayedNonce;
    procedure ValidateToken;
    procedure ValidateInvalidToken;
    procedure ChangePassword;
    procedure ChangePasswordWrongOld;
  end;

  TTestPostService = class(TMsTestCase)
  published
    procedure AddAndGet;
    procedure AddEmptyTitle;
    procedure GetNotFound;
    procedure GetBySlug;
    procedure GetBySlugNotFound;
    procedure GetList;
    procedure Update;
    procedure UpdateNotFound;
    procedure Remove;
    procedure RemoveNotFound;
  end;

  TTestTagService = class(TMsTestCase)
  published
    procedure AddAndGet;
    procedure AddEmptyName;
    procedure AddDuplicateName;
    procedure GetNotFound;
    procedure GetAll;
    procedure SetPostTags;
    procedure SetPostTagsInvalidJson;
    procedure GetByPost;
    procedure GetByPostNoTags;
    procedure Remove;
    procedure RemoveCascade;
  end;

  TTestCommentService = class(TMsTestCase)
  published
    procedure AddPending;
    procedure AddEmptyBody;
    procedure AddInvalidPostId;
    procedure GetPending;
    procedure Approve;
    procedure ApproveNotFound;
    procedure Reject;
    procedure GetByPost;
    procedure GetByPostNoComments;
  end;

  TTestMediaService = class(TMsTestCase)
  published
    procedure UploadAndGetInfo;
    procedure UploadEmptyFileName;
    procedure UploadEmptyData;
    procedure UploadTooLarge;
    procedure GetInfoNotFound;
    procedure GetFile;
    procedure GetFileNotFound;
    procedure Remove;
    procedure RemoveNotFound;
  end;

  TTestBlogAggregation = class(TMsTestCase)
  published
    procedure GetPostFull;
    procedure GetPostFullNotFound;
  end;

  TTestFullWorkflow = class(TMsTestCase)
  published
    procedure EndToEnd;
  end;

  /// Top-level test suite
  TBlogTests = class(TSynTests)
  private
    FContext: TBlogTestContext;
  public
    constructor Create(
      const Ident: string = ''
      ); override;
    destructor Destroy; override;
  published
    procedure Services;
  end;

implementation

{ TBlogTestContext }

constructor TBlogTestContext.Create;

  procedure RegisterService(aImpl: TInterfacedObject;
    aInterface: PRttiInfo);
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
    TOrmBlogTag,
    TOrmPostTag,
    TOrmBlogComment,
    TOrmMediaFile
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
  // Keep interface references
  Auth := FAuthImpl;
  User := FUserImpl;
  Post := FPostImpl;
  Tag := FTagImpl;
  Comment := FCommentImpl;
  Media := FMediaImpl;
  Blog := FBlogImpl;
  // Register on REST server
  RegisterService(FAuthImpl, TypeInfo(IAuth));
  RegisterService(FUserImpl, TypeInfo(IUser));
  RegisterService(FPostImpl, TypeInfo(IPost));
  RegisterService(FTagImpl, TypeInfo(ITag));
  RegisterService(FCommentImpl, TypeInfo(IComment));
  RegisterService(FMediaImpl, TypeInfo(IMedia));
  RegisterService(FBlogImpl, TypeInfo(IBlog));
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
  FreeAndNil(FRestServer);
  FreeAndNil(FModel);
  FreeAndNil(FJwt);
  // Clean up temp media directory
  if DirectoryExists(FMediaPath) then
    DirectoryDelete(FMediaPath, FILES_ALL, True);
  inherited Destroy;
end;


{ TMsTestCase }

function TMsTestCase.Context: TBlogTestContext;
begin
  Result := (Owner as TBlogTests).FContext;
end;

{ TTestUserService }

procedure TTestUserService.AddAndGet;
var
  Id: TID;
  Json: RawJson;
  Doc: TDocVariantData;
begin
  Id := Context.User.Add(
    '{"DisplayName":"Max","Bio":"Test author","WebsiteUrl":"https://example.com"}');
  Check(Id > 0, 'User.Add should return positive ID');
  Json := Context.User.Get(Id);
  Check(Json <> '', 'User.Get should return JSON');
  Doc.InitJson(Json, JSON_FAST_FLOAT);
  CheckEqual(Doc.U['DisplayName'], 'Max');
  CheckEqual(Doc.U['Bio'], 'Test author');
end;

procedure TTestUserService.AddEmptyName;
begin
  CheckEqual(Context.User.Add('{"Bio":"No name"}'), 0,
    'empty DisplayName should return 0');
  CheckEqual(Context.User.Add('{}'), 0,
    'empty JSON should return 0');
end;

procedure TTestUserService.GetNotFound;
begin
  CheckEqual(Context.User.Get(99999), '{}');
end;

procedure TTestUserService.Update;
var
  Id: TID;
  Doc: TDocVariantData;
begin
  Id := Context.User.Add('{"DisplayName":"Update Test"}');
  Check(Id > 0);
  Check(Context.User.Update(Id, '{"Bio":"Updated bio"}'));
  Doc.InitJson(Context.User.Get(Id), JSON_FAST_FLOAT);
  CheckEqual(Doc.U['Bio'], 'Updated bio');
  CheckEqual(Doc.U['DisplayName'], 'Update Test');
end;

procedure TTestUserService.UpdateNotFound;
begin
  Check(not Context.User.Update(99999, '{"Bio":"ghost"}'),
    'update non-existent should return false');
end;

procedure TTestUserService.GetAll;
var
  Json: RawJson;
  Arr: TDocVariantData;
begin
  Json := Context.User.GetAll;
  Check(Json <> '', 'GetAll should return JSON');
  Check(Json <> '[]', 'GetAll should not be empty');
  Arr.InitJson(Json, JSON_FAST_FLOAT);
  Check(Arr.Count >= 2, 'should have at least 2 users');
end;

procedure TTestUserService.Remove;
var
  Id: TID;
begin
  Id := Context.User.Add('{"DisplayName":"To Remove"}');
  Check(Id > 0);
  Check(Context.User.Remove(Id));
  CheckEqual(Context.User.Get(Id), '{}');
end;

procedure TTestUserService.RemoveNotFound;
begin
  // mORMot2 ORM returns True even if no row was deleted
  Check(Context.User.Remove(99999),
    'DELETE on non-existent is not an error in mORMot2');
  CheckEqual(Context.User.Get(99999), '{}',
    'record should still not exist');
end;

{ TTestAuthService }

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
  CheckEqual(Context.Auth.Register('', 'pass123', 1), 0,
    'empty email should return 0');
end;

procedure TTestAuthService.RegisterEmptyPassword;
begin
  CheckEqual(Context.Auth.Register('nopass@example.com', '', 1), 0,
    'empty password should return 0');
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
  ClientProof := ScramClientProof(McfHash, 'test@example.com',
    ClientSignature, ['test@example.com', ServerNonce]);
  Check(ClientProof <> '', 'ScramClientProof should succeed');
  // Phase 3: Authenticate
  Ok := Context.Auth.Authenticate('test@example.com', ServerNonce,
    ClientProof, Token, UserId, ServerProof);
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
  ClientProof := ScramClientProof(McfHash, 'test@example.com',
    ClientSignature, ['test@example.com', ServerNonce]);
  Check(not Context.Auth.Authenticate('test@example.com', ServerNonce,
    ClientProof, Token, UserId, ServerProof),
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
  ClientProof := ScramClientProof(McfHash, 'unknown@example.com',
    ClientSignature, ['unknown@example.com', ServerNonce]);
  Check(not Context.Auth.Authenticate('unknown@example.com', ServerNonce,
    ClientProof, Token, UserId, ServerProof),
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
  ClientProof := ScramClientProof(McfHash, 'test@example.com',
    ClientSignature, ['test@example.com', ServerNonce]);
  // First auth consumes the nonce
  Context.Auth.Authenticate('test@example.com', ServerNonce,
    ClientProof, Token, UserId, ServerProof);
  // Replay with same nonce should fail
  Check(not Context.Auth.Authenticate('test@example.com', ServerNonce,
    ClientProof, Token, UserId, ServerProof),
    'replayed nonce should fail');
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
  ClientProof := ScramClientProof(McfHash, 'test@example.com',
    ClientSignature, ['test@example.com', ServerNonce]);
  Context.Auth.Authenticate('test@example.com', ServerNonce,
    ClientProof, Token, UserId, ServerProof);
  // Validate the token
  Check(Context.Auth.Validate(Token, ValidatedUserId),
    'Validate should succeed');
  CheckEqual(ValidatedUserId, UserId, 'UserId should match');
  // Invalid token should fail
  Check(not Context.Auth.Validate('invalid.token.here', ValidatedUserId),
    'invalid token should fail');
end;

procedure TTestAuthService.ValidateInvalidToken;
var
  UserId: TID;
begin
  Check(not Context.Auth.Validate('', UserId),
    'empty token should fail');
  Check(not Context.Auth.Validate('not.a.jwt', UserId),
    'garbage token should fail');
end;

procedure TTestAuthService.ChangePassword;
var
  McfInfo, ServerNonce, McfHash: RawUtf8;
  ClientProof, Token, ServerProof: RawUtf8;
  UserId, AuthUserId: TID;
  ClientSignature: THash256;
  Ok: boolean;
begin
  // Register a new user with a unique userId for this test
  UserId := Context.User.Add('{"DisplayName":"PW Changer"}');
  Check(UserId > 0, 'create user for changepw test');
  AuthUserId := Context.Auth.Register('changepw@example.com', 'oldpass', UserId);
  Check(AuthUserId > 0, 'register changepw account');
  // Change password
  Check(Context.Auth.ChangePassword(UserId, 'oldpass', 'newpass'),
    'ChangePassword should succeed');
  // Login with new password
  Context.Auth.Challenge('changepw@example.com', McfInfo, ServerNonce);
  McfHash := ModularCryptHash(McfInfo, 'newpass');
  ClientProof := ScramClientProof(McfHash, 'changepw@example.com',
    ClientSignature, ['changepw@example.com', ServerNonce]);
  Ok := Context.Auth.Authenticate('changepw@example.com', ServerNonce,
    ClientProof, Token, UserId, ServerProof);
  Check(Ok, 'login with new password should succeed');
end;

procedure TTestAuthService.ChangePasswordWrongOld;
var
  UserId: TID;
begin
  UserId := Context.User.Add('{"DisplayName":"WrongOld Test"}');
  Context.Auth.Register('wrongold@example.com', 'correct', UserId);
  Check(not Context.Auth.ChangePassword(UserId, 'WRONG', 'newpass'),
    'wrong old password should fail');
end;

{ TTestPostService }

procedure TTestPostService.AddAndGet;
var
  Id: TID;
  Doc: TDocVariantData;
begin
  Id := Context.Post.Add(
    '{"Title":"First Post","Body":"Hello world","AuthorId":1,"Status":1}');
  Check(Id > 0, 'Post.Add should return positive ID');
  Doc.InitJson(Context.Post.Get(Id), JSON_FAST_FLOAT);
  CheckEqual(Doc.U['Title'], 'First Post');
  CheckEqual(Doc.U['Slug'], 'first-post');
  CheckEqual(Doc.I['Status'], POST_STATUS_PUBLISHED);
end;

procedure TTestPostService.AddEmptyTitle;
begin
  CheckEqual(Context.Post.Add('{"Body":"no title","AuthorId":1}'), 0,
    'empty title should return 0');
  CheckEqual(Context.Post.Add('{}'), 0,
    'empty JSON should return 0');
end;

procedure TTestPostService.GetNotFound;
begin
  CheckEqual(Context.Post.Get(99999), '{}');
end;

procedure TTestPostService.GetBySlug;
var
  Doc: TDocVariantData;
begin
  Doc.InitJson(Context.Post.GetBySlug('first-post'), JSON_FAST_FLOAT);
  CheckEqual(Doc.U['Title'], 'First Post');
end;

procedure TTestPostService.GetBySlugNotFound;
begin
  CheckEqual(Context.Post.GetBySlug('no-such-slug'), '{}');
end;

procedure TTestPostService.GetList;
var
  Id: TID;
  Doc: TDocVariantData;
begin
  // Add more posts
  Id := Context.Post.Add(
    '{"Title":"Draft Post","Body":"Not published","AuthorId":1,"Status":0}');
  Check(Id > 0);
  Id := Context.Post.Add(
    '{"Title":"Second Published","Body":"Content","AuthorId":1,"Status":1}');
  Check(Id > 0);
  // Get published only (status=1)
  Doc.InitJson(Context.Post.GetList(1, 10, 1, 0), JSON_FAST_FLOAT);
  Check(Doc.I['total'] >= 2, 'should have at least 2 published posts');
  // Filter by author
  Doc.InitJson(Context.Post.GetList(1, 10, 0, 1), JSON_FAST_FLOAT);
  Check(Doc.I['total'] >= 3, 'author 1 should have at least 3 posts');
end;

procedure TTestPostService.Update;
var
  Id: TID;
  Doc: TDocVariantData;
begin
  Id := Context.Post.Add(
    '{"Title":"To Update","Body":"Original","AuthorId":1,"Status":0}');
  Check(Id > 0);
  Check(Context.Post.Update(Id, '{"Title":"Updated Title","Status":1}'));
  Doc.InitJson(Context.Post.Get(Id), JSON_FAST_FLOAT);
  CheckEqual(Doc.U['Title'], 'Updated Title');
  CheckEqual(Doc.U['Slug'], 'updated-title');
  CheckEqual(Doc.I['Status'], POST_STATUS_PUBLISHED);
end;

procedure TTestPostService.UpdateNotFound;
begin
  Check(not Context.Post.Update(99999, '{"Title":"ghost"}'),
    'update non-existent should return false');
end;

procedure TTestPostService.Remove;
var
  Id: TID;
begin
  Id := Context.Post.Add(
    '{"Title":"To Delete","Body":"Gone soon","AuthorId":1,"Status":0}');
  Check(Id > 0);
  Check(Context.Post.Remove(Id));
  CheckEqual(Context.Post.Get(Id), '{}');
end;

procedure TTestPostService.RemoveNotFound;
begin
  // mORMot2 ORM returns True even if no row was deleted
  Check(Context.Post.Remove(99999),
    'DELETE on non-existent is not an error in mORMot2');
  CheckEqual(Context.Post.Get(99999), '{}',
    'record should still not exist');
end;

{ TTestTagService }

procedure TTestTagService.AddAndGet;
var
  Id: TID;
  Doc: TDocVariantData;
begin
  Id := Context.Tag.Add('{"Name":"Delphi","Description":"Delphi language"}');
  Check(Id > 0, 'Tag.Add should return positive ID');
  Doc.InitJson(Context.Tag.Get(Id), JSON_FAST_FLOAT);
  CheckEqual(Doc.U['Name'], 'Delphi');
  CheckEqual(Doc.U['Slug'], 'delphi');
end;

procedure TTestTagService.AddEmptyName;
begin
  CheckEqual(Context.Tag.Add('{"Description":"no name"}'), 0,
    'empty name should return 0');
end;

procedure TTestTagService.AddDuplicateName;
begin
  CheckEqual(Context.Tag.Add('{"Name":"Delphi"}'), 0,
    'duplicate name should fail (UNIQUE constraint)');
end;

procedure TTestTagService.GetNotFound;
begin
  CheckEqual(Context.Tag.Get(99999), '{}');
end;

procedure TTestTagService.GetAll;
var
  Id: TID;
  Arr: TDocVariantData;
begin
  Id := Context.Tag.Add('{"Name":"mORMot2"}');
  Check(Id > 0);
  Id := Context.Tag.Add('{"Name":"Testing"}');
  Check(Id > 0);
  Arr.InitJson(Context.Tag.GetAll, JSON_FAST_FLOAT);
  Check(Arr.Count >= 3, 'should have at least 3 tags');
end;

procedure TTestTagService.SetPostTags;
begin
  Check(Context.Tag.SetPostTags(1, '[1,2]'),
    'SetPostTags should succeed');
end;

procedure TTestTagService.SetPostTagsInvalidJson;
begin
  Check(not Context.Tag.SetPostTags(1, 'not-json'),
    'invalid JSON should return false');
  Check(not Context.Tag.SetPostTags(1, '{"not":"array"}'),
    'non-array JSON should return false');
end;

procedure TTestTagService.GetByPost;
var
  Arr: TDocVariantData;
begin
  Arr.InitJson(Context.Tag.GetByPost(1), JSON_FAST_FLOAT);
  CheckEqual(Arr.Count, 2, 'post 1 should have 2 tags');
end;

procedure TTestTagService.GetByPostNoTags;
var
  PostId: TID;
begin
  PostId := Context.Post.Add(
    '{"Title":"No Tags Post","Body":"x","AuthorId":1,"Status":0}');
  CheckEqual(Context.Tag.GetByPost(PostId), '[]',
    'post without tags should return empty array');
end;

procedure TTestTagService.Remove;
var
  Id: TID;
begin
  Id := Context.Tag.Add('{"Name":"Temporary"}');
  Check(Id > 0);
  Check(Context.Tag.Remove(Id));
  CheckEqual(Context.Tag.Get(Id), '{}');
end;

procedure TTestTagService.RemoveCascade;
var
  TagId, PostId: TID;
  Arr: TDocVariantData;
begin
  TagId := Context.Tag.Add('{"Name":"CascadeTest"}');
  PostId := Context.Post.Add(
    '{"Title":"Cascade Post","Body":"x","AuthorId":1,"Status":0}');
  Context.Tag.SetPostTags(PostId, FormatUtf8('[%]', [TagId]));
  // Verify tag is assigned
  Arr.InitJson(Context.Tag.GetByPost(PostId), JSON_FAST_FLOAT);
  Check(Arr.Count = 1, 'should have 1 tag before remove');
  // Remove tag — PostTag associations should be deleted too
  Check(Context.Tag.Remove(TagId));
  Arr.InitJson(Context.Tag.GetByPost(PostId), JSON_FAST_FLOAT);
  CheckEqual(Arr.Count, 0, 'tag associations should be gone after remove');
end;

{ TTestCommentService }

procedure TTestCommentService.AddPending;
var
  Id: TID;
begin
  Id := Context.Comment.Add(1,
    '{"AuthorName":"Visitor","AuthorEmail":"v@test.com","Body":"Nice post!"}');
  Check(Id > 0, 'Comment.Add should return positive ID');
end;

procedure TTestCommentService.AddEmptyBody;
begin
  CheckEqual(Context.Comment.Add(1, '{"AuthorName":"X","Body":""}'), 0,
    'empty body should return 0');
  CheckEqual(Context.Comment.Add(1, '{"AuthorName":"X"}'), 0,
    'missing body should return 0');
end;

procedure TTestCommentService.AddInvalidPostId;
begin
  CheckEqual(Context.Comment.Add(0, '{"AuthorName":"X","Body":"text"}'), 0,
    'postId=0 should return 0');
  CheckEqual(Context.Comment.Add(-1, '{"AuthorName":"X","Body":"text"}'), 0,
    'negative postId should return 0');
end;

procedure TTestCommentService.GetPending;
var
  Arr: TDocVariantData;
begin
  Arr.InitJson(Context.Comment.GetPending, JSON_FAST_FLOAT);
  Check(Arr.Count >= 1, 'should have at least 1 pending comment');
end;

procedure TTestCommentService.Approve;
begin
  Check(Context.Comment.Approve(1, 1), 'Approve should succeed');
end;

procedure TTestCommentService.ApproveNotFound;
begin
  Check(not Context.Comment.Approve(99999, 1),
    'approve non-existent should return false');
end;

procedure TTestCommentService.Reject;
var
  Id: TID;
begin
  Id := Context.Comment.Add(1,
    '{"AuthorName":"Spammer","Body":"Buy stuff!"}');
  Check(Id > 0);
  Check(Context.Comment.Reject(Id, 1), 'Reject should succeed');
end;

procedure TTestCommentService.GetByPost;
var
  Arr: TDocVariantData;
begin
  // Only approved comments should appear
  Arr.InitJson(Context.Comment.GetByPost(1), JSON_FAST_FLOAT);
  Check(Arr.Count >= 1, 'should have at least 1 approved comment');
  CheckEqual(_Safe(Arr.Values[0])^.U['AuthorName'], 'Visitor');
end;

procedure TTestCommentService.GetByPostNoComments;
var
  PostId: TID;
begin
  PostId := Context.Post.Add(
    '{"Title":"No Comments Post","Body":"x","AuthorId":1,"Status":0}');
  CheckEqual(Context.Comment.GetByPost(PostId), '[]',
    'post without approved comments should return empty array');
end;

{ TTestMediaService }

procedure TTestMediaService.UploadAndGetInfo;
var
  Id: TID;
  Doc: TDocVariantData;
begin
  Id := Context.Media.Upload('test.png',
    BinToBase64('fake-png-data'), 'Test image', 1);
  Check(Id > 0, 'Media.Upload should return positive ID');
  Doc.InitJson(Context.Media.GetInfo(Id), JSON_FAST_FLOAT);
  CheckEqual(Doc.U['FileName'], 'test.png');
  CheckEqual(Doc.U['MimeType'], 'image/png');
  CheckEqual(Doc.U['AltText'], 'Test image');
end;

procedure TTestMediaService.UploadEmptyFileName;
begin
  CheckEqual(Context.Media.Upload('', BinToBase64('data'), '', 1), 0,
    'empty filename should return 0');
end;

procedure TTestMediaService.UploadEmptyData;
begin
  CheckEqual(Context.Media.Upload('test.png', '', '', 1), 0,
    'empty data should return 0');
end;

procedure TTestMediaService.UploadTooLarge;
var
  LargeData: RawByteString;
begin
  SetLength(LargeData, MAX_UPLOAD_SIZE + 1);
  FillCharFast(pointer(LargeData)^, Length(LargeData), Ord('X'));
  CheckEqual(Context.Media.Upload('big.bin',
    BinToBase64(LargeData), '', 1), 0,
    'oversized upload should return 0');
end;

procedure TTestMediaService.GetInfoNotFound;
begin
  CheckEqual(Context.Media.GetInfo(99999), '{}');
end;

procedure TTestMediaService.GetFile;
var
  Id: TID;
  ContentType: RawUtf8;
  FileData: RawByteString;
begin
  Id := Context.Media.Upload('hello.txt',
    BinToBase64('Hello World'), 'text file', 1);
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
begin
  Id := Context.Media.Upload('remove.txt',
    BinToBase64('to delete'), '', 1);
  Check(Id > 0);
  Check(Context.Media.Remove(Id));
  CheckEqual(Context.Media.GetInfo(Id), '{}');
end;

procedure TTestMediaService.RemoveNotFound;
begin
  // Media.Remove checks Retrieve first, so non-existent returns False
  Check(not Context.Media.Remove(99999),
    'remove non-existent media should return false');
end;

{ TTestBlogAggregation }

procedure TTestBlogAggregation.GetPostFull;
var
  Doc: TDocVariantData;
begin
  Doc.InitJson(Context.Blog.GetPostFull(1), JSON_FAST_FLOAT);
  Check(Doc.U['Title'] <> '', 'should have Title');
  Check(Doc.GetValueIndex('Author') >= 0, 'should have Author');
  Check(Doc.GetValueIndex('Tags') >= 0, 'should have Tags');
  Check(Doc.GetValueIndex('Comments') >= 0, 'should have Comments');
end;

procedure TTestBlogAggregation.GetPostFullNotFound;
begin
  CheckEqual(Context.Blog.GetPostFull(99999), '{}');
end;

{ TTestFullWorkflow }

procedure TTestFullWorkflow.EndToEnd;
var
  AuthorId, PostId, TagId1, TagId2, CommentId: TID;
  McfInfo, ServerNonce, McfHash: RawUtf8;
  ClientProof, Token, ServerProof: RawUtf8;
  UserId: TID;
  ClientSignature: THash256;
  Doc: TDocVariantData;
begin
  // 1. Create author
  AuthorId := Context.User.Add(
    '{"DisplayName":"Workflow Author","Bio":"E2E test"}');
  Check(AuthorId > 0, '1. create author');
  // 2. Register auth account
  Check(Context.Auth.Register('workflow@example.com', 'testpass',
    AuthorId) > 0, '2. register auth');
  // 3. Login via SCRAM
  Context.Auth.Challenge('workflow@example.com', McfInfo, ServerNonce);
  McfHash := ModularCryptHash(McfInfo, 'testpass');
  ClientProof := ScramClientProof(McfHash, 'workflow@example.com',
    ClientSignature, ['workflow@example.com', ServerNonce]);
  Check(Context.Auth.Authenticate('workflow@example.com', ServerNonce,
    ClientProof, Token, UserId, ServerProof), '3. SCRAM login');
  // 4. Validate JWT
  Check(Context.Auth.Validate(Token, UserId), '4. validate token');
  // 5. Create post
  PostId := Context.Post.Add(FormatUtf8(
    '{"Title":"E2E Test Post","Body":"Full workflow","AuthorId":%,"Status":1}',
    [AuthorId]));
  Check(PostId > 0, '5. create post');
  // 6. Create tags
  TagId1 := Context.Tag.Add('{"Name":"E2E-Tag-1"}');
  TagId2 := Context.Tag.Add('{"Name":"E2E-Tag-2"}');
  Check(TagId1 > 0, '6a. create tag 1');
  Check(TagId2 > 0, '6b. create tag 2');
  // 7. Assign tags
  Check(Context.Tag.SetPostTags(PostId,
    FormatUtf8('[%,%]', [TagId1, TagId2])), '7. assign tags');
  // 8. Add comment
  CommentId := Context.Comment.Add(PostId,
    '{"AuthorName":"E2E Visitor","Body":"Great workflow!"}');
  Check(CommentId > 0, '8. add comment');
  // 9. Approve comment
  Check(Context.Comment.Approve(CommentId, AuthorId), '9. approve');
  // 10. Aggregate via IBlog
  Doc.InitJson(Context.Blog.GetPostFull(PostId), JSON_FAST_FLOAT);
  CheckEqual(Doc.U['Title'], 'E2E Test Post', '10a. post title');
  Check(Doc.GetValueIndex('Author') >= 0, '10b. has author');
  Check(Doc.A_['Tags']^.Count = 2, '10c. has 2 tags');
  Check(Doc.A_['Comments']^.Count >= 1, '10d. has comments');
end;

{ TBlogTests }

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
  AddCase(TTestTagService);
  AddCase(TTestCommentService);
  AddCase(TTestMediaService);
  AddCase(TTestBlogAggregation);
  AddCase(TTestFullWorkflow);
end;

end.

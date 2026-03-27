/// <summary>
///   Data Transfer Objects (DTOs) for communication
///   between the blog microservices.
/// </summary>
unit ms.shared.dto;

{$SCOPEDENUMS ON}
{$I mormot.defines.inc}
{$WARN SYMBOL_PLATFORM OFF}
{$WARN UNIT_PLATFORM OFF}

interface

uses
  mormot.core.base,
  mormot.core.json;

type

  // Auth service DTOs

  /// <summary>
  ///   Request payload for user login.
  /// </summary>
  TAuthLoginRequest = packed record
    Email: RawUtf8;
    Password: RawUtf8;
  end;

  /// <summary>
  ///   Response payload after successful login.
  /// </summary>
  TAuthLoginResponse = packed record
    Token: RawUtf8;
    UserId: TID;
  end;

  /// <summary>
  ///   Request payload for user registration.
  /// </summary>
  TAuthRegisterRequest = packed record
    Email: RawUtf8;
    Password: RawUtf8;
    UserId: TID;
  end;

  /// <summary>
  ///   Request payload for token validation.
  /// </summary>
  TAuthValidateRequest = packed record
    Token: RawUtf8;
  end;

  /// <summary>
  ///   Response payload for token validation.
  /// </summary>
  TAuthValidateResponse = packed record
    Valid: Boolean;
    UserId: TID;
  end;

  /// <summary>
  ///   Request payload for changing a user password.
  /// </summary>
  TAuthChangePasswordRequest = packed record
    OldPassword: RawUtf8;
    NewPassword: RawUtf8;
  end;

  // User service DTOs

  /// <summary>
  ///   Data transfer object representing a user.
  /// </summary>
  TUserDto = packed record
    Id: TID;
    DisplayName: RawUtf8;
    Slug: RawUtf8;
    Bio: RawUtf8;
    WebsiteUrl: RawUtf8;
    AvatarMediaId: TID;
    CreatedAt: TDateTime;
    UpdatedAt: TDateTime;
  end;

  /// <summary>
  ///   Request payload for creating a new user.
  /// </summary>
  TUserCreateRequest = packed record
    DisplayName: RawUtf8;
    Bio: RawUtf8;
    WebsiteUrl: RawUtf8;
  end;

  // Post service DTOs

  /// <summary>
  ///   Data transfer object representing a blog post.
  /// </summary>
  TPostDto = packed record
    Id: TID;
    Title: RawUtf8;
    Slug: RawUtf8;
    Body: RawUtf8;
    Excerpt: RawUtf8;
    AuthorId: TID;
    FeaturedImageId: TID;
    MetaTitle: RawUtf8;
    MetaDescription: RawUtf8;
    MetaKeywords: RawUtf8;
    Status: Integer;
    PublishedAt: TDateTime;
    CreatedAt: TDateTime;
    UpdatedAt: TDateTime;
  end;

  /// <summary>
  ///   Request payload for creating a new blog post.
  /// </summary>
  TPostCreateRequest = packed record
    Title: RawUtf8;
    Body: RawUtf8;
    Excerpt: RawUtf8;
    AuthorId: TID;
    FeaturedImageId: TID;
    MetaTitle: RawUtf8;
    MetaDescription: RawUtf8;
    MetaKeywords: RawUtf8;
    Status: Integer;
  end;

  /// <summary>
  ///   Paginated response containing a list of blog posts.
  /// </summary>
  TPostListResponse = packed record
    Items: array of TPostDto;
    Total: Integer;
    Page: Integer;
  end;

  // Tag service DTOs

  /// <summary>
  ///   Data transfer object representing a tag.
  /// </summary>
  TTagDto = packed record
    Id: TID;
    Name: RawUtf8;
    Slug: RawUtf8;
    Description: RawUtf8;
    PostCount: Integer;
  end;

  /// <summary>
  ///   Request payload for creating a new tag.
  /// </summary>
  TTagCreateRequest = packed record
    Name: RawUtf8;
    Description: RawUtf8;
  end;

  /// <summary>
  ///   Request payload for associating tags with a post.
  /// </summary>
  TPostTagsRequest = packed record
    TagIds: array of TID;
  end;

  // Comment service DTOs

  /// <summary>
  ///   Data transfer object representing a comment.
  /// </summary>
  TCommentDto = packed record
    Id: TID;
    PostId: TID;
    AuthorName: RawUtf8;
    AuthorEmail: RawUtf8;
    Body: RawUtf8;
    Status: Integer;
    ModeratedBy: TID;
    ModeratedAt: TDateTime;
    CreatedAt: TDateTime;
  end;

  /// <summary>
  ///   Request payload for creating a new comment.
  /// </summary>
  TCommentCreateRequest = packed record
    AuthorName: RawUtf8;
    AuthorEmail: RawUtf8;
    Body: RawUtf8;
  end;

  /// <summary>
  ///   Response payload containing comment counts by status.
  /// </summary>
  TCommentCountResponse = packed record
    Total: Integer;
    Approved: Integer;
    Pending: Integer;
  end;

  // Media service DTOs

  /// <summary>
  ///   Data transfer object representing a media item.
  /// </summary>
  TMediaDto = packed record
    Id: TID;
    FileName: RawUtf8;
    MimeType: RawUtf8;
    FileSize: Int64;
    AltText: RawUtf8;
    Url: RawUtf8;
    UploadedBy: TID;
    CreatedAt: TDateTime;
  end;

  // General DTOs

  /// <summary>
  ///   Response payload containing a single ID.
  /// </summary>
  TIdResponse = packed record
    Id: TID;
  end;

  /// <summary>
  ///   Response payload indicating success or failure.
  /// </summary>
  TSuccessResponse = packed record
    Success: Boolean;
  end;

  /// <summary>
  ///   Response payload containing an error message and code.
  /// </summary>
  TErrorResponse = packed record
    Error: RawUtf8;
    Code: Integer;
  end;

implementation

initialization
  // Register JSON serialization for all DTOs
  Rtti.RegisterFromText([
    TypeInfo(TAuthLoginRequest),       'Email,Password: RawUtf8',
    TypeInfo(TAuthLoginResponse),      'Token: RawUtf8; UserId: TID',
    TypeInfo(TAuthRegisterRequest),    'Email,Password: RawUtf8; UserId: TID',
    TypeInfo(TAuthValidateRequest),    'Token: RawUtf8',
    TypeInfo(TAuthValidateResponse),   'Valid: Boolean; UserId: TID',
    TypeInfo(TAuthChangePasswordRequest), 'OldPassword,NewPassword: RawUtf8',

    TypeInfo(TUserDto),          'Id: TID; DisplayName,Slug,Bio,WebsiteUrl: RawUtf8; AvatarMediaId: TID; CreatedAt,UpdatedAt: TDateTime',
    TypeInfo(TUserCreateRequest),'DisplayName,Bio,WebsiteUrl: RawUtf8',

    TypeInfo(TPostDto),            'Id: TID; Title,Slug,Body,Excerpt: RawUtf8; AuthorId,FeaturedImageId: TID; MetaTitle,MetaDescription,MetaKeywords: RawUtf8; Status: Integer; PublishedAt,CreatedAt,UpdatedAt: TDateTime',
    TypeInfo(TPostCreateRequest),  'Title,Body,Excerpt: RawUtf8; AuthorId,FeaturedImageId: TID; MetaTitle,MetaDescription,MetaKeywords: RawUtf8; Status: Integer',
    TypeInfo(TPostListResponse),   'Items: array of TPostDto; Total,Page: Integer',

    TypeInfo(TTagDto),           'Id: TID; Name,Slug,Description: RawUtf8; PostCount: Integer',
    TypeInfo(TTagCreateRequest), 'Name,Description: RawUtf8',
    TypeInfo(TPostTagsRequest),  'TagIds: array of TID',

    TypeInfo(TCommentDto),           'Id,PostId: TID; AuthorName,AuthorEmail,Body: RawUtf8; Status: Integer; ModeratedBy: TID; ModeratedAt,CreatedAt: TDateTime',
    TypeInfo(TCommentCreateRequest), 'AuthorName,AuthorEmail,Body: RawUtf8',
    TypeInfo(TCommentCountResponse), 'Total,Approved,Pending: Integer',

    TypeInfo(TMediaDto),       'Id: TID; FileName,MimeType: RawUtf8; FileSize: Int64; AltText,Url: RawUtf8; UploadedBy: TID; CreatedAt: TDateTime',

    TypeInfo(TIdResponse),      'Id: TID',
    TypeInfo(TSuccessResponse), 'Success: Boolean',
    TypeInfo(TErrorResponse),   'Error: RawUtf8; Code: Integer'
  ]);

end.

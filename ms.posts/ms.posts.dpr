program ms.posts;

{$APPTYPE CONSOLE}

{$I mormot.defines.inc}

{$R *.res}

uses
  {$I mormot.uses.inc}
  SysUtils,
  mormot.core.base,
  mormot.core.os,
  mormot.db.raw.sqlite3.static,
  ms.shared,
  ms.shared.service,
  ms.posts.model,
  ms.posts.server;

var
  Server: TPostsServer;
begin
  Server := TPostsServer.Create(SERVICE_POSTS, PORT_POSTS);
  try
    Server.Run;
  finally
    Server.Free;
  end;
end.

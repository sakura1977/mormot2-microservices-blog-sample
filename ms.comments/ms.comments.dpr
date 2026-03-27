program ms.comments;

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
  ms.comments.model,
  ms.comments.server;

var
  Server: TCommentsServer;
begin
  Server := TCommentsServer.Create(SERVICE_COMMENTS, PORT_COMMENTS);
  try
    Server.Run;
  finally
    Server.Free;
  end;
end.

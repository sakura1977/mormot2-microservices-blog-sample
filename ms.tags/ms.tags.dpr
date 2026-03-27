program ms.tags;

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
  ms.tags.model,
  ms.tags.server;

var
  Server: TTagsServer;
begin
  Server := TTagsServer.Create(SERVICE_TAGS, PORT_TAGS);
  try
    Server.Run;
  finally
    Server.Free;
  end;
end.

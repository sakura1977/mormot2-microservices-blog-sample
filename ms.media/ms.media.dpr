program ms.media;

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
  ms.media.model,
  ms.media.server;

var
  Server: TMediaServer;
begin
  Server := TMediaServer.Create(SERVICE_MEDIA, PORT_MEDIA);
  try
    Server.Run;
  finally
    Server.Free;
  end;
end.

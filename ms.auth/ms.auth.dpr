program ms.auth;

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
  ms.shared.jwt,
  ms.auth.model,
  ms.auth.server;

var
  Server: TAuthServer;
begin
  Server := TAuthServer.Create(SERVICE_AUTH, PORT_AUTH);
  try
    Server.Run;
  finally
    Server.Free;
  end;
end.

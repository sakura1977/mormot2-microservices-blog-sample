program ms.config;

{$APPTYPE CONSOLE}

{$I mormot.defines.inc}

{$R *.res}

uses
  {$I mormot.uses.inc}
  SysUtils,
  mormot.core.base,
  mormot.core.os,
  mormot.rest.http.server,
  mormot.soa.core,
  mormot.soa.server,
  mormot.db.raw.sqlite3.static,
  ms.shared,
  ms.shared.api,
  ms.shared.service,
  ms.config.server;

var
  Server: TConfigServer;
begin
  Server := TConfigServer.Create(SERVICE_CONFIG, PORT_CONFIG);
  try
    Server.Run;
  finally
    Server.Free;
  end;
end.

program ms.logs;

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
  ms.logs.model,
  ms.logs.server;

var
  Server: TLogsServer;
begin
  Server := TLogsServer.Create(SERVICE_LOGS, PORT_LOGS);
  try
    Server.Run;
  finally
    Server.Free;
  end;
end.

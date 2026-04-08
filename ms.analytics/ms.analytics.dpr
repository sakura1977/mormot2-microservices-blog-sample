program ms.analytics;

{$APPTYPE CONSOLE}

{$I mormot.defines.inc}

{$R *.res}

uses
  {$I mormot.uses.inc}
  SysUtils,
  mormot.core.base,
  mormot.core.os,
  mormot.rest.http.client,
  mormot.rest.http.server,
  mormot.soa.client,
  mormot.soa.core,
  mormot.soa.server,
  mormot.db.raw.sqlite3.static,
  ms.shared,
  ms.shared.api,
  ms.shared.service,
  ms.analytics.server;

var
  Server: TAnalyticsServer;
begin
  Server := TAnalyticsServer.Create(SERVICE_ANALYTICS, PORT_ANALYTICS);
  try
    Server.Run;
  finally
    Server.Free;
  end;
end.

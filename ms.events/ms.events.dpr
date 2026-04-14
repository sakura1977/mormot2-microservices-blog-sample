program ms.events;

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
  ms.events.model,
  ms.events.server;

var
  Server: TEventsServer;
begin
  Server := TEventsServer.Create(SERVICE_EVENTS, PORT_EVENTS);
  try
    Server.Run;
  finally
    Server.Free;
  end;
end.

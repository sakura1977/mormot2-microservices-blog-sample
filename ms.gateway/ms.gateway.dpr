program ms.gateway;

{$APPTYPE CONSOLE}

{$I mormot.defines.inc}

{$R *.res}

uses
  {$I mormot.uses.inc}
  SysUtils,
  mormot.core.base,
  mormot.core.os,
  mormot.db.raw.sqlite3.static,
  mormot.net.async,
  mormot.rest.http.server,
  mormot.rest.http.client,
  mormot.soa.core,
  mormot.soa.server,
  mormot.soa.client,
  ms.shared,
  ms.shared.api,
  ms.shared.service,
  ms.gateway.server;

var
  Server: TGatewayServer;
begin
  Server := TGatewayServer.Create(SERVICE_GATEWAY, PORT_GATEWAY);
  try
    Server.Run;
  finally
    Server.Free;
  end;
end.

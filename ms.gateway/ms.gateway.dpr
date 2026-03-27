program ms.gateway;

{$APPTYPE CONSOLE}

{$I mormot.defines.inc}

{$R *.res}

uses
  {$I mormot.uses.inc}
  SysUtils,
  mormot.core.base,
  mormot.core.os,
  ms.shared,
  ms.shared.service,
  ms.shared.client,
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

program ms.users;

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
  ms.users.model,
  ms.users.server;

var
  Server: TUsersServer;
begin
  Server := TUsersServer.Create(SERVICE_USERS, PORT_USERS);
  try
    Server.Run;
  finally
    Server.Free;
  end;
end.

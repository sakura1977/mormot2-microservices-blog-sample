program ms.controller;

{$APPTYPE CONSOLE}

{$I mormot.defines.inc}

{$R *.res}

uses
  {$I mormot.uses.inc}
  SysUtils,
  mormot.core.base,
  mormot.core.log,
  mormot.core.os,
  ms.shared,
  ms.controller.orchestrator;

const
  PORT_CONTROLLER = '8090';
var
  Orch: TServiceOrchestrator;
begin
  Orch := TServiceOrchestrator.Create(PORT_CONTROLLER);
  try
    Orch.Run;
  finally
    Orch.Free;
  end;
end.

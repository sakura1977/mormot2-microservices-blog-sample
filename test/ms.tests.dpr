/// Test runner for the Blog Microservices.
/// Runs all services in a single process with in-memory SQLite databases.
program ms.tests;

{$APPTYPE CONSOLE}
{$I mormot.defines.inc}

uses
  {$I mormot.uses.inc}
  SysUtils,
  mormot.core.base,
  mormot.core.test,
  mormot.core.log,
  mormot.db.raw.sqlite3.static,
  ms.testCases in 'ms.testCases.pas';

var
  Tests: TBlogTests;
begin
  Tests := TBlogTests.Create;
  try
    Tests.Run;
  finally
    Tests.Free;
  end;
end.

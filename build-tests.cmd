@echo off
setlocal

set DELPHI_BIN=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin
call "%DELPHI_BIN%\rsvars.bat"

set CONFIG=Debug
set PLATFORM=Win32

echo ============================================
echo  Building test project (%CONFIG% / %PLATFORM%)
echo ============================================
echo.

MSBuild.exe "%~dp0test\ms.tests.dproj" /p:Config=%CONFIG% /p:Platform=%PLATFORM% /t:Build /v:minimal
if errorlevel 1 (
  echo FAILED
  exit /b 1
)
echo OK
exit /b 0

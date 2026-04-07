@echo off
setlocal

set DELPHI_BIN=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin
call "%DELPHI_BIN%\rsvars.bat"

set CONFIG=Debug
set PLATFORM=Win64
set ERRORS=0

echo ============================================
echo  Building all projects (%CONFIG% / %PLATFORM%)
echo ============================================
echo.

call :BUILD ms.auth\ms.auth.dproj
call :BUILD ms.users\ms.users.dproj
call :BUILD ms.posts\ms.posts.dproj
call :BUILD ms.tags\ms.tags.dproj
call :BUILD ms.comments\ms.comments.dproj
call :BUILD ms.media\ms.media.dproj
call :BUILD ms.gateway\ms.gateway.dproj
call :BUILD ms.controller\ms.controller.dproj

echo.
echo ============================================
if %ERRORS% == 0 (
  echo  All projects built successfully.
) else (
  echo  %ERRORS% project(s) failed to build.
)
echo ============================================

exit /b %ERRORS%

:BUILD
echo Building %~1 ...
MSBuild.exe "%~dp0%~1" /p:Config=%CONFIG% /p:Platform=%PLATFORM% /t:Build /v:minimal
if errorlevel 1 (
  echo   FAILED: %~1
  set /a ERRORS+=1
) else (
  echo   OK: %~1
)
echo.
exit /b 0

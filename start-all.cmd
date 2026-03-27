@echo off
:: ============================================
::  Blog Microservices -- Start all services
::  Startup order respects dependencies
:: ============================================

setlocal

:: Output directory (same as in .dproj)
set "OUTDIR=%gitroot%\_out\Win32-Debug\APP"

echo.
echo === Starting blog microservices ===
echo Output directory: %OUTDIR%
echo.

:: Check if directory exists
if not exist "%OUTDIR%" (
    echo ERROR: Output directory not found.
    echo Please compile all projects first.
    echo.
    pause
    exit /b 1
)

:: 1. Backend services without dependencies
echo [1/7] Starting ms.media...
start "ms.media" /MIN "%OUTDIR%\ms.media.exe"
timeout /t 1 /nobreak >nul

echo [2/7] Starting ms.users...
start "ms.users" /MIN "%OUTDIR%\ms.users.exe"
timeout /t 1 /nobreak >nul

:: 2. Auth (requires ms.users)
echo [3/7] Starting ms.auth...
start "ms.auth" /MIN "%OUTDIR%\ms.auth.exe"
timeout /t 1 /nobreak >nul

:: 3. Remaining backend services
echo [4/7] Starting ms.posts...
start "ms.posts" /MIN "%OUTDIR%\ms.posts.exe"
timeout /t 1 /nobreak >nul

echo [5/7] Starting ms.tags...
start "ms.tags" /MIN "%OUTDIR%\ms.tags.exe"
timeout /t 1 /nobreak >nul

echo [6/7] Starting ms.comments...
start "ms.comments" /MIN "%OUTDIR%\ms.comments.exe"
timeout /t 1 /nobreak >nul

:: 4. Gateway (requires all others)
echo [7/7] Starting ms.gateway...
start "ms.gateway" /MIN "%OUTDIR%\ms.gateway.exe"
timeout /t 2 /nobreak >nul

echo.
echo === All services started ===
echo.
echo   Gateway:    http://localhost:8080
echo   Auth:       http://localhost:8081
echo   Users:      http://localhost:8082
echo   Posts:      http://localhost:8083
echo   Tags:       http://localhost:8084
echo   Comments:   http://localhost:8085
echo   Media:      http://localhost:8086
echo.
echo   Open blog: http://localhost:8080
echo.

endlocal

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

:: 0. Config service (must start first -- all others depend on it)
echo [1/11] Starting ms.config...
start "ms.config" /MIN "%OUTDIR%\ms.config.exe"
timeout /t 2 /nobreak >nul

:: 1. Central logging (must come right after config so the rest can ship their startup logs)
echo [2/11] Starting ms.logs...
start "ms.logs" /MIN "%OUTDIR%\ms.logs.exe"
timeout /t 1 /nobreak >nul

:: 1b. Event bus (after logs so its own startup logs are shipped; before any producer/consumer)
echo [3/11] Starting ms.events...
start "ms.events" /MIN "%OUTDIR%\ms.events.exe"
timeout /t 1 /nobreak >nul

:: 2. Backend services without dependencies
echo [4/11] Starting ms.media...
start "ms.media" /MIN "%OUTDIR%\ms.media.exe"
timeout /t 1 /nobreak >nul

echo [5/11] Starting ms.users...
start "ms.users" /MIN "%OUTDIR%\ms.users.exe"
timeout /t 1 /nobreak >nul

:: 3. Auth (requires ms.users)
echo [6/11] Starting ms.auth...
start "ms.auth" /MIN "%OUTDIR%\ms.auth.exe"
timeout /t 1 /nobreak >nul

:: 4. Remaining backend services
echo [7/11] Starting ms.posts...
start "ms.posts" /MIN "%OUTDIR%\ms.posts.exe"
timeout /t 1 /nobreak >nul

echo [8/11] Starting ms.tags...
start "ms.tags" /MIN "%OUTDIR%\ms.tags.exe"
timeout /t 1 /nobreak >nul

echo [9/11] Starting ms.comments...
start "ms.comments" /MIN "%OUTDIR%\ms.comments.exe"
timeout /t 1 /nobreak >nul

:: 5. Analytics (requires backend services)
echo [10/11] Starting ms.analytics...
start "ms.analytics" /MIN "%OUTDIR%\ms.analytics.exe"
timeout /t 1 /nobreak >nul

:: 6. Gateway (requires all others)
echo [11/11] Starting ms.gateway...
start "ms.gateway" /MIN "%OUTDIR%\ms.gateway.exe"
timeout /t 2 /nobreak >nul

echo.
echo === All services started ===
echo.
echo   Config:     http://localhost:8087
echo   Gateway:    http://localhost:8080
echo   Auth:       http://localhost:8081
echo   Users:      http://localhost:8082
echo   Posts:      http://localhost:8083
echo   Tags:       http://localhost:8084
echo   Comments:   http://localhost:8085
echo   Media:      http://localhost:8086
echo   Analytics:  http://localhost:8088
echo   Logs:       http://localhost:8089
echo   Events:     http://localhost:8091
echo.
echo   Open blog: http://localhost:8080
echo.

endlocal

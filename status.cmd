@echo off
:: ============================================
::  Blog Microservices -- Check health status
:: ============================================

setlocal

echo.
echo === Blog Microservices Status ===
echo.

set "SERVICES=ms.config:8087 ms.logs:8089 ms.auth:8081 ms.users:8082 ms.posts:8083 ms.tags:8084 ms.comments:8085 ms.media:8086 ms.analytics:8088 ms.gateway:8080"

for %%S in (%SERVICES%) do (
    for /f "tokens=1,2 delims=:" %%A in ("%%S") do (
        curl -s -o nul -w "  %%A (%%B): %%{http_code}" http://localhost:%%B/api/health 2>nul || echo   %%A ^(%%B^): NOT REACHABLE
    )
)

echo.
echo === Done ===
echo.

endlocal

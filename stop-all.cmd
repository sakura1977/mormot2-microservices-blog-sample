@echo off
:: ============================================
::  Blog Microservices -- Stop all services
::  Graceful shutdown via /api/shutdown
:: ============================================

setlocal

echo.
echo === Stopping blog microservices ===
echo.

:: Gateway first (stops accepting new requests)
echo [1/11] Stopping ms.gateway...
curl -s -X POST http://localhost:8080/api/shutdown >nul 2>&1

echo [2/11] Stopping ms.analytics...
curl -s -X POST http://localhost:8088/api/shutdown >nul 2>&1

echo [3/11] Stopping ms.comments...
curl -s -X POST http://localhost:8085/api/shutdown >nul 2>&1

echo [4/11] Stopping ms.tags...
curl -s -X POST http://localhost:8084/api/shutdown >nul 2>&1

echo [5/11] Stopping ms.posts...
curl -s -X POST http://localhost:8083/api/shutdown >nul 2>&1

echo [6/11] Stopping ms.auth...
curl -s -X POST http://localhost:8081/api/shutdown >nul 2>&1

echo [7/11] Stopping ms.users...
curl -s -X POST http://localhost:8082/api/shutdown >nul 2>&1

echo [8/11] Stopping ms.media...
curl -s -X POST http://localhost:8086/api/shutdown >nul 2>&1

:: ms.events before ms.logs so its shutdown log lines still reach the central store
echo [9/11] Stopping ms.events...
curl -s -X POST http://localhost:8091/api/shutdown >nul 2>&1

:: ms.logs second-to-last so it can still receive shutdown messages from the others
echo [10/11] Stopping ms.logs...
curl -s -X POST http://localhost:8089/api/shutdown >nul 2>&1

:: Config service last (other services no longer need it)
echo [11/11] Stopping ms.config...
curl -s -X POST http://localhost:8087/api/shutdown >nul 2>&1

:: Brief wait
timeout /t 2 /nobreak >nul

echo.
echo === All services stopped ===
echo.

endlocal

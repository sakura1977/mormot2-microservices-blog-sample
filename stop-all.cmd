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
echo [1/7] Stopping ms.gateway...
curl -s -X POST http://localhost:8080/api/shutdown >nul 2>&1

echo [2/7] Stopping ms.comments...
curl -s -X POST http://localhost:8085/api/shutdown >nul 2>&1

echo [3/7] Stopping ms.tags...
curl -s -X POST http://localhost:8084/api/shutdown >nul 2>&1

echo [4/7] Stopping ms.posts...
curl -s -X POST http://localhost:8083/api/shutdown >nul 2>&1

echo [5/7] Stopping ms.auth...
curl -s -X POST http://localhost:8081/api/shutdown >nul 2>&1

echo [6/7] Stopping ms.users...
curl -s -X POST http://localhost:8082/api/shutdown >nul 2>&1

echo [7/7] Stopping ms.media...
curl -s -X POST http://localhost:8086/api/shutdown >nul 2>&1

:: Brief wait
timeout /t 2 /nobreak >nul

echo.
echo === All services stopped ===
echo.

endlocal

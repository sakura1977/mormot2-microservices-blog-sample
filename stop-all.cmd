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
echo [1/8] Stopping ms.gateway...
curl -s -X POST http://localhost:8080/api/shutdown >nul 2>&1

echo [2/8] Stopping ms.comments...
curl -s -X POST http://localhost:8085/api/shutdown >nul 2>&1

echo [3/8] Stopping ms.tags...
curl -s -X POST http://localhost:8084/api/shutdown >nul 2>&1

echo [4/8] Stopping ms.posts...
curl -s -X POST http://localhost:8083/api/shutdown >nul 2>&1

echo [5/8] Stopping ms.auth...
curl -s -X POST http://localhost:8081/api/shutdown >nul 2>&1

echo [6/8] Stopping ms.users...
curl -s -X POST http://localhost:8082/api/shutdown >nul 2>&1

echo [7/8] Stopping ms.media...
curl -s -X POST http://localhost:8086/api/shutdown >nul 2>&1

:: Config service last (other services no longer need it)
echo [8/8] Stopping ms.config...
curl -s -X POST http://localhost:8087/api/shutdown >nul 2>&1

:: Brief wait
timeout /t 2 /nobreak >nul

echo.
echo === All services stopped ===
echo.

endlocal

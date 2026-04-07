@echo off
:: ============================================
::  Blog Microservices -- Create demo data
::  Uses mORMot2 SOA interface-based services.
::  Prerequisite: All services must be running
:: ============================================

setlocal

echo.
echo === Creating demo data (mORMot2 SOA) ===
echo.

:: 1. Create author via IUser.Add
echo [1/5] Creating author "Max"...
curl -s -X POST http://localhost:8082/api/User/Add ^
  -H "Content-Type: application/json" ^
  -d "[{\"DisplayName\":\"Max\",\"Bio\":\"Software developer and blogger. Writes about Delphi, mORMot and microservices.\",\"WebsiteUrl\":\"https://example.com\"}]"
echo.

:: 2. Create auth account via IAuth.Register (password: demo1234)
echo [2/5] Creating login for max@example.com...
curl -s -X POST http://localhost:8081/api/Auth/Register ^
  -H "Content-Type: application/json" ^
  -d "[\"max@example.com\",\"demo1234\",1]"
echo.

:: 3. Create tags via ITag.Add
echo [3/5] Creating tags...
curl -s -X POST http://localhost:8084/api/Tag/Add ^
  -H "Content-Type: application/json" ^
  -d "[{\"Name\":\"Delphi\",\"Description\":\"Everything about Embarcadero Delphi\"}]"
echo.

curl -s -X POST http://localhost:8084/api/Tag/Add ^
  -H "Content-Type: application/json" ^
  -d "[{\"Name\":\"mORMot2\",\"Description\":\"mORMot2 framework for Delphi and FPC\"}]"
echo.

curl -s -X POST http://localhost:8084/api/Tag/Add ^
  -H "Content-Type: application/json" ^
  -d "[{\"Name\":\"Microservices\",\"Description\":\"Microservice architecture and patterns\"}]"
echo.

curl -s -X POST http://localhost:8084/api/Tag/Add ^
  -H "Content-Type: application/json" ^
  -d "[{\"Name\":\"Tutorial\",\"Description\":\"Step-by-step guides\"}]"
echo.

:: 4. Create posts via IPost.Add
echo [4/5] Creating sample posts...

curl -s -X POST http://localhost:8083/api/Post/Add ^
  -H "Content-Type: application/json" ^
  -d "[{\"Title\":\"Welcome to the Blog Microservices Demo\",\"Body\":\"This is the first post on our blog, built entirely from microservices.\",\"Excerpt\":\"A blog system built as a microservice architecture with Delphi and mORMot2.\",\"AuthorId\":1,\"Status\":1}]"
echo.

curl -s -X POST http://localhost:8083/api/Post/Add ^
  -H "Content-Type: application/json" ^
  -d "[{\"Title\":\"Microservices with Delphi -- Why and How?\",\"Body\":\"Microservices are an architectural pattern where an application consists of small, independent services.\",\"Excerpt\":\"Why Delphi is ideal for microservices and how mORMot2 helps.\",\"AuthorId\":1,\"Status\":1}]"
echo.

curl -s -X POST http://localhost:8083/api/Post/Add ^
  -H "Content-Type: application/json" ^
  -d "[{\"Title\":\"mORMot2 ORM -- Database Access Made Easy\",\"Body\":\"The mORMot2 framework provides a powerful ORM that greatly simplifies working with databases.\",\"Excerpt\":\"Introduction to the mORMot2 ORM for Delphi developers.\",\"AuthorId\":1,\"Status\":1}]"
echo.

:: 5. Assign tags via ITag.SetPostTags
echo [5/5] Assigning tags...

:: Post 1: Delphi, mORMot2, Microservices
curl -s -X POST http://localhost:8084/api/Tag/SetPostTags ^
  -H "Content-Type: application/json" ^
  -d "[1,[1,2,3]]"
echo.

:: Post 2: Delphi, Microservices
curl -s -X POST http://localhost:8084/api/Tag/SetPostTags ^
  -H "Content-Type: application/json" ^
  -d "[2,[1,3]]"
echo.

:: Post 3: mORMot2, Tutorial
curl -s -X POST http://localhost:8084/api/Tag/SetPostTags ^
  -H "Content-Type: application/json" ^
  -d "[3,[2,4]]"
echo.

echo.
echo === Demo data created successfully! ===
echo.
echo   Author:  Max
echo   Login:   max@example.com / demo1234
echo   Auth:    SCRAM-MCF (PBKDF2-SHA256, client-side hashing)
echo   API:     mORMot2 interface-based services (SOA)
echo   Posts:   3
echo   Tags:    4 (Delphi, mORMot2, Microservices, Tutorial)
echo.
echo   Open blog: http://localhost:8080
echo.

endlocal

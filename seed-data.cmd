@echo off
:: ============================================
::  Blog Microservices -- Create demo data
::  Prerequisite: All services must be running
:: ============================================

setlocal

echo.
echo === Creating demo data ===
echo.

:: 1. Create author
echo [1/6] Creating author "Max"...
curl -s -X POST http://localhost:8082/api/users ^
  -H "Content-Type: application/json" ^
  -d "{\"DisplayName\":\"Max\",\"Bio\":\"Software developer and blogger. Writes about Delphi, mORMot and microservices.\",\"WebsiteUrl\":\"https://example.com\"}"
echo.

:: 2. Create auth account (password: demo1234)
echo [2/6] Creating login for max@example.com...
curl -s -X POST http://localhost:8081/api/auth/register ^
  -H "Content-Type: application/json" ^
  -d "{\"Email\":\"max@example.com\",\"Password\":\"demo1234\",\"UserId\":1}"
echo.

:: 3. Create tags
echo [3/6] Creating tags...
curl -s -X POST http://localhost:8084/api/tags ^
  -H "Content-Type: application/json" ^
  -d "{\"Name\":\"Delphi\",\"Description\":\"Everything about Embarcadero Delphi\"}"
echo.

curl -s -X POST http://localhost:8084/api/tags ^
  -H "Content-Type: application/json" ^
  -d "{\"Name\":\"mORMot2\",\"Description\":\"mORMot2 framework for Delphi and FPC\"}"
echo.

curl -s -X POST http://localhost:8084/api/tags ^
  -H "Content-Type: application/json" ^
  -d "{\"Name\":\"Microservices\",\"Description\":\"Microservice architecture and patterns\"}"
echo.

curl -s -X POST http://localhost:8084/api/tags ^
  -H "Content-Type: application/json" ^
  -d "{\"Name\":\"Tutorial\",\"Description\":\"Step-by-step guides\"}"
echo.

:: 4. Login to obtain token
echo [4/6] Logging in as max@example.com...
for /f "tokens=*" %%T in ('curl -s -X POST http://localhost:8081/api/auth/login -H "Content-Type: application/json" -d "{\"Email\":\"max@example.com\",\"Password\":\"demo1234\"}"') do set "LOGIN_RESULT=%%T"
echo %LOGIN_RESULT%

:: Token extraction (simple, since format is known: {"token":"...","userId":1})
:: For the seed script we work directly against the backend services

:: 5. Create posts
echo [5/6] Creating sample posts...

curl -s -X POST http://localhost:8083/api/posts ^
  -H "Content-Type: application/json" ^
  -d "{\"Title\":\"Welcome to the Blog Microservices Demo\",\"Body\":\"This is the first post on our blog, built entirely from microservices. Each service -- authentication, posts, tags, comments and media -- runs as an independent console application.\n\nThe entire architecture is based on Delphi and the mORMot2 framework. Services communicate via REST APIs with JSON.\",\"Excerpt\":\"A blog system built as a microservice architecture with Delphi and mORMot2.\",\"AuthorId\":1,\"MetaTitle\":\"Blog Microservices Demo\",\"MetaDescription\":\"Microservice-based blog with Delphi 13 and mORMot2\",\"MetaKeywords\":\"Delphi,mORMot2,Microservices,Blog\",\"Status\":1}"
echo.

curl -s -X POST http://localhost:8083/api/posts ^
  -H "Content-Type: application/json" ^
  -d "{\"Title\":\"Microservices with Delphi -- Why and How?\",\"Body\":\"Microservices are an architectural pattern where an application consists of small, independent services. Each service has a clearly defined responsibility and communicates via lightweight protocols.\n\nIn this post we show why Delphi is an excellent choice for microservices:\n\n1. Native compilation -- fast, resource-efficient executables\n2. mORMot2 -- powerful REST and ORM framework\n3. SQLite -- embedded database per service\n4. Simple deployment -- one EXE per service, no runtime needed\",\"Excerpt\":\"Why Delphi is ideal for microservices and how mORMot2 helps.\",\"AuthorId\":1,\"MetaTitle\":\"Microservices with Delphi\",\"MetaDescription\":\"Delphi and mORMot2 for microservice architectures\",\"MetaKeywords\":\"Delphi,Microservices,Architecture\",\"Status\":1}"
echo.

curl -s -X POST http://localhost:8083/api/posts ^
  -H "Content-Type: application/json" ^
  -d "{\"Title\":\"mORMot2 ORM -- Database Access Made Easy\",\"Body\":\"The mORMot2 framework provides a powerful ORM (Object-Relational Mapping) that greatly simplifies working with databases.\n\nA simple example:\n\ntype\n  TOrmAuthor = class(TOrm)\n  published\n    property DisplayName: RawUtf8;\n    property Bio: RawUtf8;\n  end;\n\nWith just a few lines of code we have a complete database model with automatic table creation, CRUD operations and JSON serialization.\",\"Excerpt\":\"Introduction to the mORMot2 ORM for Delphi developers.\",\"AuthorId\":1,\"MetaTitle\":\"mORMot2 ORM Tutorial\",\"MetaDescription\":\"Database access with mORMot2 ORM in Delphi\",\"MetaKeywords\":\"mORMot2,ORM,SQLite,Delphi,Tutorial\",\"Status\":1}"
echo.

:: 6. Assign tags to posts
echo [6/6] Assigning tags...

:: Post 1: Delphi, mORMot2, Microservices
curl -s -X PUT http://localhost:8084/api/posts/1/tags ^
  -H "Content-Type: application/json" ^
  -d "{\"TagIds\":[1,2,3]}"
echo.

:: Post 2: Delphi, Microservices
curl -s -X PUT http://localhost:8084/api/posts/2/tags ^
  -H "Content-Type: application/json" ^
  -d "{\"TagIds\":[1,3]}"
echo.

:: Post 3: mORMot2, Tutorial
curl -s -X PUT http://localhost:8084/api/posts/3/tags ^
  -H "Content-Type: application/json" ^
  -d "{\"TagIds\":[2,4]}"
echo.

echo.
echo === Demo data created successfully! ===
echo.
echo   Author:  Max
echo   Login:   max@example.com / demo1234
echo   Posts:   3
echo   Tags:    4 (Delphi, mORMot2, Microservices, Tutorial)
echo.
echo   Open blog: http://localhost:8080
echo.

endlocal

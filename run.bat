@echo off

set APP_NAME=callisto app
set COMPANY_NAME=callisto default company

:: TODO: replace with vendored shaderslang
call shaders.bat
if %errorlevel% neq 0 exit /b %errorlevel%

odin run callisto\editor -define:VERBOSE=true -- build -clean -debug -app-name:"%APP_NAME%" -company-name:"%COMPANY_NAME%"

:: editor could be called with -- run -debug, but the stdout is weird at the moment.
if %errorlevel% neq 0 exit /b %errorlevel%
out\"%APP_NAME%.exe"

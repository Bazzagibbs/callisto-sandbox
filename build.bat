@echo off

set APP_NAME=callisto app
set COMPANY_NAME=callisto default company

odin run callisto\editor -debug -- build -clean -debug -dump-spirv -app-name:"%APP_NAME%" -company-name:"%COMPANY_NAME%"

if %errorlevel% neq 0 exit /b %errorlevel%

:: editor could be called with -- run -debug, but the stdout is weird at the moment.
if "%1"=="-run" (
        out\"%APP_NAME%.exe"
)

@echo off

set APP_NAME=callisto app
set COMPANY_NAME=callisto default company

if "%1"=="-reload" (
        editor reload -debug -app-name:"%APP_NAME%" -company-name:"%COMPANY_NAME%"
        exit
)

:: this is gross and I don't like it, but shadercross requires DLLs mainly because of dxcompiler.
:: maybe I need to start packaging the editor separately unless I can statically link everything
robocopy callisto\editor\sdl3_shadercross\bin . /np /nfl /njs /njh /ndl /nc /ns
odin run callisto\editor -debug -- build -clean -debug -dump-spirv -app-name:"%APP_NAME%" -company-name:"%COMPANY_NAME%"

if %errorlevel% neq 0 exit /b %errorlevel%

:: editor could be called with -- run -debug, but the stdout is weird at the moment.
if "%1"=="-run" (
        out\"%APP_NAME%.exe"
)

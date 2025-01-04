echo off
REM call shaders.bat
REM if %errorlevel% neq 0 exit /b %errorlevel%

py callisto\build.py develop

if %errorlevel% neq 0 exit /b %errorlevel%
out\callisto_app.exe

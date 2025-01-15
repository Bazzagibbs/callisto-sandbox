@echo off

if not exist "resources_imported\shaders" mkdir resources_imported\shaders

slangc resources\shaders\mesh.vert.slang -profile vs_5_0 -o resources_imported\shaders\mesh.vert.dxbc -entry vertex_main
if %errorlevel% neq 0 exit /b %errorlevel%

slangc resources\shaders\mesh.frag.slang -profile ps_5_0 -o resources_imported\shaders\mesh.frag.dxbc -entry fragment_main
if %errorlevel% neq 0 exit /b %errorlevel%

:: slangc resources_src\shaders\compute_draw.slang -o resources\shaders\compute_draw.spv
:: glslc -fshader-stage=compute resources_src\shaders\compute_draw.glsl -o resources\shaders\compute_draw.spv

slangc resources_src\shaders\mesh.vertex.slang -profile vs_5_0 -o resources\shaders\mesh.vertex.dxbc -entry vertex_main
if %errorlevel% neq 0 exit /b %errorlevel%

slangc resources_src\shaders\mesh.fragment.slang -profile ps_5_0 -o resources\shaders\mesh.fragment.dxbc -entry fragment_main
if %errorlevel% neq 0 exit /b %errorlevel%

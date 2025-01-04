:: slangc resources_src\shaders\compute_draw.slang -o resources\shaders\compute_draw.spv
:: glslc -fshader-stage=compute resources_src\shaders\compute_draw.glsl -o resources\shaders\compute_draw.spv

slangc resources_src\shaders\mesh.vertex.slang -o resources\shaders\mesh.vertex.spv
slangc resources_src\shaders\mesh.fragment.slang -o resources\shaders\mesh.fragment.spv

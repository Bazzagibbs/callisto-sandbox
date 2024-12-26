struct Constant_Handles {
        uint scene_id;
        uint pass_id;
        uint shader_id;
        uint instance_id;
};

layout(push_constant) Constant_Handles constants;

layout(binding = 0) ByteAddressBuffer storage;
layout(binding = 1) Sampler2D samplers[];
layout(binding = 2) RWTexture2D rw_textures[];
// layout(binding = 3) Acceleration_Structures;

// ---------------

struct Shader_Constants {
        uint tex_target_id;
};



// ConstantBuffer constant_buffers[];
// RWTexture2D target;
// RWTexture2D<half4> target;



[shader("compute")]
[numthreads(16, 16, 1)]
void compute_main(uint3 thread_id : SV_DispatchThreadID, uint3 local_id : SV_GroupThreadID) {
        uint2 texel_coord = thread_id.xy;
        Shader_Constants shader = storage[constants.shader_id];

        RWTexture2D target = rw_textures[shader.tex_target_id];
        
        uint width, height;
        target.GetDimensions(width, height);

        if (texel_coord.x < width && texel_coord.y < height) {
                float4 color = {0, 0, 0, 1};

                if (local_id.x != 0 && local_id.y != 0) {
                        color.r = local_id.x / 16.0;
                        color.g = local_id.y / 16.0;
                }

                target[texel_coord] = color;
        }
        
}

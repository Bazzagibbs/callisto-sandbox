struct Buffer_0 {
        float4 color;
        uint target_tex_id;
        uint sprite_tex_id;
};

struct Push_Constant {
        Buffer_0 *buffer_0;
        void *_padding_a;
        void *_padding_b;
        void *_padding_c;
};

layout(push_constant) Push_Constant constants;

// layout(binding = 0) ByteAddressBuffer storage;
layout(binding = 1) Sampler2D samplers[];
layout(binding = 2) RWTexture2D rw_textures[];



[shader("compute")]
[numthreads(16, 16, 1)]
void compute_main(uint3 thread_id : SV_DispatchThreadID, uint3 local_id : SV_GroupThreadID) {
        Sampler2D sprite = samplers[constants.buffer_0.sprite_tex_id];
        RWTexture2D target = rw_textures[constants.buffer_0.target_tex_id];
        
        uint width, height;
        sprite.GetDimensions(width, height);
        
        uint2 tex_coord_int = thread_id.xy;
        float2 tex_coord = float2(float(tex_coord_int.x) / float(width),
                                  float(tex_coord_int.y) / float(height));

        float4 color = sprite.SampleLevel(tex_coord, 0); // NOTE: default .Sample() in compute requires derivative exts.
        color *= constants.buffer_0.color;

        target[tex_coord_int] = color;
}

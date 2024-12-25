struct Constant_Handles {
        uint scene;
        uint pass;
        uint material;
        uint instance;
};

[push_constant] Constant_Handles handles;

// ConstantBuffer constant_buffers[];
// RWTexture2D target;
// RWTexture2D<half4> target;



[shader("compute")]
[numthreads(16, 16, 1)]
void compute_main(uint3 thread_id : SV_DispatchThreadID, uint3 local_id : SV_GroupThreadID) {
        uint2 texel_coord = thread_id.xy;

        /*
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
        */
}

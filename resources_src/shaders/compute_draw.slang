import callisto;

struct Material {
        float4 color;
        cal.Render_Target_Reference target;
        cal.Texture_Reference texture;
};


layout(push_constant) cal.Push_Constant<Material> push;


[shader("compute")]
[numthreads(16, 16, 1)]
void compute_main(uint3 thread_id : SV_DispatchThreadID, uint3 local_id : SV_GroupThreadID) {
        Sampler2D tex = push.material.texture.get();
        RWTexture2D target = push.material.target.get();
        
        uint width, height;
        tex.GetDimensions(width, height);
        
        uint2 tex_coord_int = thread_id.xy;
        float2 tex_coord = float2(float(tex_coord_int.x) / float(width),
                                  float(tex_coord_int.y) / float(height));

        float4 color = tex.SampleLevel(tex_coord, 0); // NOTE: default .Sample() in compute requires derivative exts.
        color *= push.material.color;

        target[tex_coord_int] = color;
}

import callisto;

struct Material {
        float4 color;
        cal.Texture_Reference diffuse;
};

[push_constant] cal.Push_Constant<Material> push;


struct V2F {
        float3 position : SV_Position;
        half2 tex_coord;
};



[shader("fragment")]
float4 main(V2F input) : SV_Target {
        float4 color = push.material.diffuse.get().Sample(input.tex_coord);
        color *= push.material.color;
        return color;
}

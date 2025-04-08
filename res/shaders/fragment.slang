struct V2F {
        float4 position : SV_Position;
        float2 tex_coord : TEXCOORD;
};

[gl_binding(0, 2)]
Sampler2D diffuse;

[shader("fragment")]
float4 fragment_main(V2F input) : SV_Target {
        float4 color = diffuse.Sample(input.tex_coord);
        return color;
}

cbuffer Material : register(b0) {
        float4 color;
};

struct V2F {
        float4 position : SV_Position;
        half2 tex_coord : TEXCOORD;
};

Sampler2D diffuse : register(t0);

[shader("fragment")]
float4 fragment_main(V2F input) : SV_Target {
        float4 color = diffuse.Sample(input.tex_coord);
        color *= color;
        return color;
}

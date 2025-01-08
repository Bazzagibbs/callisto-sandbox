// struct Material_Constants {
//         float4 color;
// };
//
// ConstantBuffer<Material_Constants> material;

struct V2F {
        float4 position : SV_Position;
        half2 tex_coord : TEXCOORD;
};

SamplerState sampler;
Texture2D diffuse;

[shader("fragment")]
float4 fragment_main(V2F input) : SV_Target {
        float4 color = diffuse.Sample(sampler, input.tex_coord);
        return color;
}

struct V2F {
        float4 position : SV_Position;
        float2 uv_0 : TEXCOORD0;
};

Texture2D<float4> texture : register(t0, space2);
SamplerState sampler0 : register(s0, space2);


float4 main(V2F v2f) : SV_Target0 {
        float4 color = texture.Sample(sampler0, v2f.uv_0);
        return color;
}

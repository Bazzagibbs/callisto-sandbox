struct Vertex {
        float3 position : TEXCOORD0;
        float2 uv_0 : TEXCOORD1;
};

struct V2F {
        float4 position : SV_Position;
        float2 uv_0 : TEXCOORD0;
};

cbuffer Camera_Constants : register(b0, space1){
        float4x4 view;
        float4x4 proj;
        float4x4 viewproj;
};


cbuffer Model_Constants : register(b1, space1) {
        float4x4 model;
};

V2F main(Vertex vertex) {
        V2F v2f;

        // float4 world_pos = mul(float4(vertex.position, 1.0), model);
        float4 world_pos = mul(model, float4(vertex.position, 1.0));
        v2f.position = mul(world_pos, viewproj);
        v2f.uv_0 = vertex.uv_0;

        return v2f;
}

struct Vertex {
        float3 position : POSITION;
        float2 tex_coord : TEXCOORD0;
};

struct V2F {
        float4 position : SV_Position;
        float2 tex_coord : TEXCOORD;
};


// -------------------------

struct Camera_Constants {
        float4x4 view;
        float4x4 proj;
        float4x4 viewproj;
};

struct Model_Constants {
        float4x4 model;
        float4x4 modelview;
        float4x4 mvp;
};

StructuredBuffer<Camera_Constants> camera;
StructuredBuffer<Model_Constants> model;
// --------------------------

[shader("vertex")]
V2F vertex_main(Vertex vertex) {
        V2F v2f;
        v2f.position  = mul(model.Load(0).mvp, float4(vertex.position, 1));
        // v2f.position = float4(vertex.position, 1);
        v2f.tex_coord = vertex.tex_coord;

        return v2f;
}

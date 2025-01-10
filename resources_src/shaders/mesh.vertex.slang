import callisto;

// --------------------------
struct Vertex {
        float3 position : POSITION;
        half2 tex_coord : TEXCOORD0;
};

struct V2F {
        float4 position : SV_Position;
        half2 tex_coord : TEXCOORD;
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

ConstantBuffer<Camera_Constants> camera;
ConstantBuffer<Model_Constants> model;
// --------------------------

[shader("vertex")]
V2F vertex_main(Vertex vertex) {
        V2F v2f;
        v2f.position  = mul(model.mvp, float4(vertex.position, 1));
        v2f.tex_coord = vertex.tex_coord;

        return v2f;
}

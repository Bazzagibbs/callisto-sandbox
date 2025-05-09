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
        // float4x4 viewproj;
};

struct Model_Constants {
        float4x4 model;
        float4x4 modelview;
};

struct Material_Constants {};

// ConstantBuffer<Camera_Constants> camera;
// ConstantBuffer<Model_Constants> model;
// --------------------------

[shader("vertex")]
V2F vertex_main_foo(Vertex vertex, Camera_Constants camera, Material_Constants material, Model_Constants model) {
        V2F v2f;
        float4 pos = float4(vertex.position, 1);
        float4 view_pos = mul(model.modelview, pos);
        v2f.position  = mul(camera.proj, view_pos);
        // v2f.position = float4(vertex.position, 1);
        v2f.tex_coord = vertex.tex_coord;

        return v2f;
}

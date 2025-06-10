enum Shape {
        Line,
};

struct Vertex {
        float3 position : TEXCOORD0;
};

struct V2F {
        float4 position : SV_Position;
};

cbuffer Camera_Constants : register(b0, space1) {
        float4x4 view;
        float4x4 proj;
        float4x4 viewproj;
};

cbuffer Gizmo_Params : register(b1, space1) {
        float4x4 model;
        // Shape shape;
        // float3 point_0;
        // float3 point_1;
};


V2F main(Vertex vertex, int vertex_id: SV_VertexID) {
        V2F v2f;

        // switch(shape) {
        //         case Shape.Line:
        //         break;
        // }
        float4 world_pos = mul(model, float4(vertex.position, 1.0));
        v2f.position = mul(viewproj, world_pos);

        return v2f;
}

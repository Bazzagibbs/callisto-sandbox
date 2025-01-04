// --------------------------
struct Vertex {
        float3 position : POSITION;
        half2 tex_coord : TEXCOORD0;
};

struct V2F {
        float4 position : SV_Position;
        half2 tex_coord : TEXCOORD;
};
// --------------------------

[shader("vertex")]
V2F vertex_main(Vertex vertex) {
        V2F v2f;
        v2f.position  = float4(vertex.position, 1);
        v2f.tex_coord = vertex.tex_coord;

        return v2f;
}

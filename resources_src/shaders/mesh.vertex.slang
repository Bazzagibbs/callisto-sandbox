import callisto;


struct Material {
        float4 color;
        cal.Texture_Reference tex;
};

[push_constant] cal.Push_Constant<Material> push;


// --------------------------
struct Vertex {
        float3 position : POSITION;
        half2 tex_coord : TEX_COORD_0;
};

struct V2F {
        float3 position : SV_Position;
        half2 tex_coord;
};
// --------------------------

[shader("vertex")]
V2F main(Vertex vertex) {
        V2F v2f;
        v2f.position  = vertex.position;
        v2f.tex_coord = vertex.tex_coord;

        return v2f;
}

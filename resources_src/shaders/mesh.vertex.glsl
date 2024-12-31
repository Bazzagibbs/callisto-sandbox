#version 460
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_nonuniform_qualifier : require

struct Vertex {
        vec3 position;
        half2 uv;
};


layout(buffer_reference) buffer Mesh_Constants {
        Vertex_Pos verts[];
};



layout(push_constant) uniform _Push_Constant {
        Mesh_Constants mesh_constants;
        Constants pad_a;
        Constants pad_b;
        Constants pad_c;
};


// --------------------------
struct V2F {
        vec3 position;
        half2 uv;
};
// --------------------------

V2F main() {
        V2F v2f;
        v2f.position = 
        return v2f;
}

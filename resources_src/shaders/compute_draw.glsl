#version 460
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_nonuniform_qualifier : require

layout(buffer_reference) buffer Constants {
        vec4 color;
        uint sprite_id;
        uint target_id;
};

layout(push_constant) uniform _Push_Constant {
        Constants constants;
        Constants pad_a;
        Constants pad_b;
        Constants pad_c;
};

// layout(binding = 0) uniform buffer storage;
layout(binding = 1) uniform sampler2D textures[];
layout(rgba16f, binding = 2) uniform image2D rw_textures[];

// ---------------


layout(local_size_x = 16, local_size_y = 16) in;

void main() {
        ivec2 tex_coord_int = ivec2(gl_GlobalInvocationID.xy);
        vec2 tex_coord = vec2(float(tex_coord_int.x), float(tex_coord_int.y)) / 1024.0;

        vec4 color = texture(textures[constants.sprite_id], tex_coord);
        color *= constants.color; // tint

        imageStore(rw_textures[constants.target_id], tex_coord_int, color);
        
}

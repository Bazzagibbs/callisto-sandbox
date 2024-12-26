#version 460
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_nonuniform_qualifier : require
// #extension GL_EXT_

layout(buffer_reference) buffer Scene_Data {
        vec4 light_pos;
};

layout(buffer_reference) buffer Pass_Data {
        mat4x4 view;
        mat4x4 view_proj;
};

layout(buffer_reference) buffer Shader_Data {
        uint target_id;
};

layout(buffer_reference) buffer Instance_Data {
        // mat4x4 model; // is this ever used alone?
        mat4x4 model_view;
        mat4x4 model_view_proj;
};

layout(push_constant) uniform _Push_Constant {
        Scene_Data scene_data;
        Pass_Data pass_data;
        Shader_Data shader_data;
        Instance_Data instance_data;
};

// layout(binding = 0) uniform buffer storage;
// layout(binding = 1) uniform Sampler2D samplers[];
layout(rgba16f, binding = 2) uniform image2D rw_textures[];

// ---------------


layout(local_size_x = 16, local_size_y = 16) in;

void main() {
        rw_textures[shader_data.target_id];

        ivec2 size = imageSize(rw_textures[shader_data.target_id]);
        ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);

        if (texel_coord.x < size.x && texel_coord.y < size.y) {
                vec4 color = {0, 0, 0, 1};

                if (gl_LocalInvocationID.x != 0 && gl_LocalInvocationID.y != 0) {
                        color.r = gl_LocalInvocationID.x / 16.0;
                        color.g = gl_LocalInvocationID.y / 16.0;
                }

                imageStore(rw_textures[shader_data.target_id], texel_coord, color);
        }
        
}

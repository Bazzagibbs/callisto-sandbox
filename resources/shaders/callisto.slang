module callisto;

namespace cal {

public struct Render_Target_Reference {
        uint handle;

        public RWTexture2D get() {
                return render_targets[handle];
        }
};

public struct Texture_Reference {
        uint handle;

        public Sampler2D get() {
                return textures[handle];
        }
};


public layout(binding=0) Sampler2D textures[];
public layout(binding=1) RWTexture2D render_targets[];


public struct Scene_Constants {
        // float4 light_color;
        // float3 light_pos;
        // ...
};

public struct Camera_Constants {
        public float4x4 view;
        public float4x4 proj;
        public float4x4 viewproj;
};

public struct Instance_Constants {
        public float4x4 model;
        public float4x4 modelview;
        public float4x4 mvp;
};


// Provide struct definitions for per-pass and per-material constant buffers.
public struct Push_Constant<MATERIAL = void, PASS = void> {
        public Scene_Constants *scene;
        public Camera_Constants *camera;
        public PASS *pass;
        public MATERIAL *material;
        public Instance_Constants *instance;
};

// [vk_location(0)] public float3 vertex_position;
// [vk_location(1)] public float3 vertex_normal;
// [vk_location(2)] public float4 vertex_tangent;
// [vk_location(3)] public half2 vertex_texcoord_0;
// Skinning data

}

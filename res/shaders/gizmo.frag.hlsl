struct V2F {
        float4 position : SV_Position;
};

cbuffer Material_Constants : register(b0, space3) {
        float4 color;
};


float4 main(V2F v2f) : SV_Target0 {
        return color;
}

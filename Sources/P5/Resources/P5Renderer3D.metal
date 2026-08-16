#include <metal_stdlib>
using namespace metal;

struct P5Vertex3DMetal {
    float3 position;
    float3 normal;
    float2 textureCoordinate;
    float4 color;
};

struct P5Uniforms3DMetal {
    float4x4 modelMatrix;
    float4x4 viewProjectionMatrix;
    float3x3 normalMatrix;
    float4 baseColor;
    float4 cameraPosition;
    float4 materialParameters;
    float4 emissiveColor;
};

struct P5Light3DMetal {
    float4 positionAndKind;
    float4 colorAndIntensity;
    float4 directionAndRange;
};

struct P5VertexOutput3D {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 textureCoordinate;
    float4 color;
};

vertex P5VertexOutput3D p5Vertex3D(
    uint vertexID [[vertex_id]],
    const device P5Vertex3DMetal *vertices [[buffer(0)]],
    constant P5Uniforms3DMetal &uniforms [[buffer(1)]])
{
    P5Vertex3DMetal inputVertex = vertices[vertexID];
    float4 worldPosition = uniforms.modelMatrix * float4(inputVertex.position, 1.0);
    P5VertexOutput3D output;
    output.position = uniforms.viewProjectionMatrix * worldPosition;
    output.worldPosition = worldPosition.xyz;
    output.normal = normalize(uniforms.normalMatrix * inputVertex.normal);
    output.textureCoordinate = inputVertex.textureCoordinate;
    output.color = inputVertex.color;
    return output;
}

fragment float4 p5Fragment3D(
    P5VertexOutput3D input [[stage_in]],
    constant P5Uniforms3DMetal &uniforms [[buffer(1)]],
    const device P5Light3DMetal *lights [[buffer(2)]],
    constant uint &lightCount [[buffer(3)]],
    texture2d<float> colorTexture [[texture(0)]],
    sampler colorSampler [[sampler(0)]])
{
    bool hasTexture = uniforms.materialParameters.z > 0.5;
    bool isUnlit = uniforms.materialParameters.w > 0.5;
    float4 textureColor = hasTexture
        ? colorTexture.sample(colorSampler, input.textureCoordinate)
        : float4(1.0);
    float4 surface = uniforms.baseColor * input.color * textureColor;
    if (isUnlit) {
        return float4(surface.rgb + uniforms.emissiveColor.rgb, surface.a);
    }

    float3 normal = normalize(input.normal);
    float3 illumination = uniforms.emissiveColor.rgb;
    for (uint index = 0; index < lightCount; ++index) {
        P5Light3DMetal light = lights[index];
        uint kind = uint(light.positionAndKind.w);
        float3 lightColor = light.colorAndIntensity.rgb * light.colorAndIntensity.a;
        if (kind == 0) {
            illumination += lightColor;
        } else {
            float3 direction;
            float attenuation = 1.0;
            if (kind == 1) {
                direction = normalize(-light.directionAndRange.xyz);
            } else {
                float3 offset = light.positionAndKind.xyz - input.worldPosition;
                float distance = length(offset);
                direction = distance > 0.0 ? offset / distance : float3(0.0, 0.0, 1.0);
                float range = light.directionAndRange.w;
                attenuation = range > 0.0 ? clamp(1.0 - (distance / range), 0.0, 1.0) : 1.0;
                attenuation *= attenuation;
            }
            float diffuse = max(dot(normal, direction), 0.0);
            float roughness = max(uniforms.materialParameters.y, 0.04);
            illumination += lightColor * diffuse * attenuation * (1.0 - 0.25 * roughness);
        }
    }
    return float4(surface.rgb * illumination, surface.a);
}

#include <metal_stdlib>

using namespace metal;

struct DKCVertexOutput {
  float4 position [[position]];
  float2 textureCoordinate;
};

vertex DKCVertexOutput dkc_vertex_main(uint vertexID [[vertex_id]]) {
  constexpr float2 positions[4] = {
      float2(-1.0, 1.0),
      float2(1.0, 1.0),
      float2(-1.0, -1.0),
      float2(1.0, -1.0),
  };
  constexpr float2 textureCoordinates[4] = {
      float2(0.0, 0.0),
      float2(1.0, 0.0),
      float2(0.0, 1.0),
      float2(1.0, 1.0),
  };

  DKCVertexOutput output;
  output.position = float4(positions[vertexID], 0.0, 1.0);
  output.textureCoordinate = textureCoordinates[vertexID];
  return output;
}

fragment float4 dkc_fragment_main(
    DKCVertexOutput input [[stage_in]],
    texture2d<half> framebuffer [[texture(0)]]) {
  constexpr sampler nearestSampler(coord::normalized,
                                    address::clamp_to_edge,
                                    filter::nearest);
  return float4(framebuffer.sample(nearestSampler, input.textureCoordinate));
}

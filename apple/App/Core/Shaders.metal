#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Colour effects for SwiftUI (Polish.swift). Same look on Android (AGSL in ui/Polish.kt).

// A slow, soft liquid gradient between two colours. The view's own alpha keeps its shape.
[[ stitchable ]] half4 liquid(float2 position, half4 color, float2 size, float time, half4 a, half4 b) {
  float2 uv = position / max(size, float2(1.0));
  float t = time * 0.35;
  float v = sin(uv.x * 3.1 + t) + sin(uv.y * 4.3 - t * 1.3) + sin((uv.x + uv.y) * 2.7 + t * 0.7)
          + sin(length(uv - float2(0.5 + 0.3 * sin(t * 0.5), 0.5)) * 6.0 - t);
  half m = half(0.5 + 0.5 * sin(v * 1.2));
  half3 c = mix(a.rgb, b.rgb, m);
  return half4(c * color.a, color.a);
}

// A moving sheen across a progress fill, like liquid catching light.
[[ stitchable ]] half4 wave(float2 position, half4 color, float2 size, float time) {
  float2 uv = position / max(size, float2(1.0));
  float sheen = 0.5 + 0.5 * sin(uv.x * 9.0 - time * 2.4 + sin(uv.y * 3.14 + time) * 0.8);
  half k = half(0.86 + 0.14 * sheen);
  return half4(color.rgb * k, color.a);
}

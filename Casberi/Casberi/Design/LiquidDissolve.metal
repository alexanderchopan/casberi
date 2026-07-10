#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// The liquid page dissolve (2026-07-10) — the OUTGOING screen's pixels are
/// displaced by two crossed sine fields whose amplitude rises from zero,
/// peaks mid-transition, and relaxes to zero: the page turns to liquid and
/// settles into the next one. Pure displacement; the fade rides the view's
/// opacity, not the shader.
[[ stitchable ]] float2 liquidDissolve(float2 position, float2 size, float progress) {
    float2 uv = position / size;
    // Zero at both ends, peak at the middle — crisp in, liquid, settled out.
    float envelope = progress * (1.0 - progress) * 4.0;
    float ampl = 34.0 * envelope;
    float x = sin(uv.y * 16.0 + progress * 7.0) + sin(uv.y * 5.0 - progress * 3.0) * 0.6;
    float y = sin(uv.x * 13.0 + progress * 6.0) + sin(uv.x * 4.0 + progress * 2.5) * 0.6;
    return position + float2(x, y) * ampl;
}

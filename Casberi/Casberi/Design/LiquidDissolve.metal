#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// The liquid dissolve, sixth draft (2026-07-10) — the WHOLE screen at once.
/// No origin, no wavefront, no burst: an organic ripple field covers the
/// page uniformly; the outgoing page liquefies and thins while the incoming
/// page ripples beneath it and settles. A soft shimmer rides the ripples
/// (light proportional to the local wave) so the motion reads on ink-black
/// without becoming an effect of its own.

static float2 rippleField(float2 uv, float t, float phase) {
    // Two crossed, incommensurate sine pairs — organic, no visible grid.
    // Broader, rolling waves ("more liquid", ruled 2026-07-10): lower
    // frequencies than the first cut, so the page heaves instead of buzzing.
    float x = sin(uv.y * 8.5 + t * 5.0 + phase)
            + sin((uv.x + uv.y) * 5.5 - t * 3.5 + phase) * 0.7;
    float y = sin(uv.x * 7.0  - t * 4.0 + phase)
            + sin((uv.x - uv.y) * 4.5 + t * 3.0 + phase) * 0.7;
    return float2(x, y);
}

/// Outgoing page: ripples build, the page thins away through the middle of
/// the ride, ripples relax — a dissolve that is liquid the whole way.
[[ stitchable ]] half4 liquidOut(float2 position, SwiftUI::Layer layer,
                                 float2 size, float progress) {
    float2 uv = position / size;
    float env = progress * (1.0 - progress) * 4.0;     // 0 → 1 → 0
    float2 wave = rippleField(uv, progress, 0.0);
    half4 c = layer.sample(position + wave * env * 42.0);

    // Shimmer: the ripples catch light where they crest — subtle, additive.
    float shimmer = env * max(0.0, wave.x * wave.y) * 0.13;
    c.rgb += half3(shimmer);

    // The dissolve itself: full through 25%, gone by 85% — wide overlap so
    // both pages are co-present through the middle.
    float a = 1.0 - smoothstep(0.25, 0.85, progress);
    c.rgb *= half(a);                                   // premultiplied
    c.a   *= half(a);
    return c;
}

/// Incoming page: born rippling with the same field (phase-shifted so the
/// two pages read as one disturbed surface, not two copies), settling to
/// crisp as the ride ends.
[[ stitchable ]] half4 liquidIn(float2 position, SwiftUI::Layer layer,
                                float2 size, float progress) {
    float2 uv = position / size;
    float settle = (1.0 - progress) * (1.0 - progress); // 1 → 0, soft landing
    float env = min(1.0, progress * 3.0) * settle;      // ramps in, settles out
    float2 wave = rippleField(uv, progress, 1.7);
    half4 c = layer.sample(position + wave * env * 34.0);
    float shimmer = env * max(0.0, wave.x * wave.y) * 0.06;
    c.rgb += half3(shimmer);
    return c;
}

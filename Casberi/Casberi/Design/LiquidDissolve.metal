#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// The liquid wave (fourth draft, 2026-07-10) — a single circular wavefront
/// sweeps from the avatar across the page. Ahead of the wave: the outgoing
/// page, untouched. At the ring: pixels stretch radially and the front
/// carries its own LIGHT (a soft glass shine — displacement alone is
/// invisible on an ink-black app). Behind the wave: transparent, so the
/// destination page is revealed spatially, washed in by the front — never
/// a crossfade.
[[ stitchable ]] half4 liquidWave(float2 position, SwiftUI::Layer layer,
                                  float2 size, float2 origin, float progress) {
    float maxDist = length(size);
    float radius = progress * maxDist * 1.12;
    float band = 130.0;                       // the wave's thickness, points
    float dist = distance(position, origin);
    float d = dist - radius;                  // >0 ahead, <0 behind

    if (d > band)  { return layer.sample(position); }   // not reached yet
    if (d < -band) { return half4(0.0); }               // fully revealed

    float t = d / band;                       // -1 … 1 across the wave
    float bump = 1.0 - t * t;                 // 0 at edges, 1 at the crest

    // Pixels get dragged toward the origin as the crest passes — the page
    // visibly stretches into the wave.
    float2 dir = dist > 1.0 ? (position - origin) / dist : float2(0.0, 1.0);
    half4 c = layer.sample(position - dir * bump * 56.0);

    // The crest carries light: a soft additive shine, strongest at the
    // center of the band — this is what makes water readable on black.
    float shine = bump * bump * 0.38;
    c.rgb += half3(shine);

    // The trailing half of the band dissolves to reveal the new page.
    float alpha = smoothstep(-1.0, -0.2, t);
    c.rgb *= half(alpha);                     // premultiplied
    c.a   *= half(alpha);
    return c;
}

/// The incoming page's half of the wave (fifth draft, 2026-07-10) — the
/// destination doesn't wait statically under the old page (that read as "a
/// sheet popped up"); it ARRIVES liquid. Right behind the front it's still
/// gathered toward the origin and faintly aglow; it relaxes to crisp as the
/// front moves on. One substance, transforming.
[[ stitchable ]] half4 liquidSettle(float2 position, SwiftUI::Layer layer,
                                    float2 size, float2 origin, float progress) {
    float maxDist = length(size);
    float radius = progress * maxDist * 1.12;
    float dist = distance(position, origin);
    float d = dist - radius;                  // >0 ahead (still covered), <0 behind

    if (d > 0.0) { return layer.sample(position); }   // the old page covers this

    float behind = -d;                        // how far past the front
    float settle = exp(-behind / 240.0);      // 1 at the front → 0 once settled
    float2 dir = dist > 1.0 ? (position - origin) / dist : float2(0.0, 1.0);
    half4 c = layer.sample(position + dir * settle * 30.0);
    c.rgb += half3(settle * 0.12);            // a fading afterglow as it stills
    return c;
}

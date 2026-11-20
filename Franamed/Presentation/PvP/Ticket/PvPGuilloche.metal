//
//  PvPMosaicFoil.metal
//  Franamed
//
//  Created by Claude on 20.11.2026.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace pvp_guilloche {
    constant float tau = 6.28318;

    inline float3 spectrum(float phase) {
        return 0.5 + 0.5 * cos(tau * (phase + float3(0.0, 0.33, 0.67)));
    }

    /// A thin anti-aliased line wherever `value` crosses a whole number; `scale` is value units per point.
    inline float lines(float value, float scale, float width) {
        float d = abs(fract(value + 0.5) - 0.5) / max(scale, 1e-4);
        return 1.0 - smoothstep(width * 0.5, width * 0.5 + 0.8, d);
    }
}

/// Banknote guilloche: a rosette of interlaced sine rings in the middle and wave bands
/// at the top and bottom. The lines' colour runs along them and shifts as the phone tilts.
[[stitchable]] half4 pvpGuilloche(float2 position, half4 color, float2 size, float2 tilt, float strength) {
    using namespace pvp_guilloche;
    float2 uv = position / max(size, float2(1.0));
    float2 c = size * float2(0.5, 0.44);
    float2 p = position - c;
    float r = length(p);
    float a = atan2(p.y, p.x);
    float unit = size.x / 293.0;

    // Rosette: two families of rings wobbling with opposite phase, so they weave.
    float radius = r / unit;
    float wobbleA = 7.0 * sin(a * 18.0) + 3.0 * sin(a * 6.0);
    float wobbleB = 7.0 * sin(a * 18.0 + 3.14159) + 3.0 * sin(a * 6.0 + 1.0);
    float spacing = 6.0;
    float ringMask = smoothstep(150.0, 120.0, radius) * smoothstep(18.0, 34.0, radius);
    float rosette = max(lines((radius + wobbleA) / spacing, 1.0 / (spacing * unit), 0.6),
                        lines((radius + wobbleB) / spacing, 1.0 / (spacing * unit), 0.6)) * ringMask;

    // Wave bands near the edges.
    float x = position.x / unit;
    float y = position.y / unit;
    float band = 0.0;
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float top = 26.0 + fi * 4.2 + 5.0 * sin(x * 0.07 + fi * 0.5);
        float bottom = size.y / unit - 30.0 - fi * 4.2 + 5.0 * sin(x * 0.07 - fi * 0.5 + 1.3);
        band = max(band, 1.0 - smoothstep(0.35, 1.1, abs(y - top) * unit));
        band = max(band, 1.0 - smoothstep(0.35, 1.1, abs(y - bottom) * unit));
    }

    float ink = max(rosette, band * 0.8);
    float hue = a / tau * 0.6 + radius * 0.004 + uv.y * 0.5 + tilt.x * 1.4 - tilt.y * 0.9;
    float sweep = 0.55 + 0.45 * sin(tau * (uv.x * 0.8 + uv.y * 0.6 - (tilt.x + tilt.y) * 0.9));
    float3 line = mix(float3(0.55), spectrum(hue), 0.8) * (0.35 + 0.65 * sweep);
    float3 base = float3(color.rgb) / max(float(color.a), 0.001);
    float3 mixed = mix(base, line, ink * strength);
    return half4(half3(clamp(mixed, 0.0, 1.0) * float(color.a)), color.a);
}

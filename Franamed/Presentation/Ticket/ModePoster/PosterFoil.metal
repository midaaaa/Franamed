//
//  PosterFoil.metal
//  Franamed
//
//  Created by Дмитрий Филимонов on 27.10.2026.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace poster_foil {
    constant float tau = 6.28318;

    inline float hash(float2 p) {
        return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
    }

    inline float3 spectrum(float phase) {
        return 0.5 + 0.5 * cos(tau * (phase + float3(0.0, 0.33, 0.67)));
    }

    inline float3 pastel(float phase) {
        return mix(spectrum(phase), float3(1.0), 0.25);
    }

    inline float3 screen(float3 a, float3 b) {
        return 1.0 - (1.0 - a) * (1.0 - b);
    }

    inline float3 overlay(float3 a, float3 b) {
        return select(1.0 - 2.0 * (1.0 - a) * (1.0 - b), 2.0 * a * b, a < 0.5);
    }

    constant float span = 1.4;

    inline float wrapped(float value, float period) {
        return (fract(value / period + 0.5) - 0.5) * period;
    }

    inline float sweep(float2 tilt) {
        return tilt.x + tilt.y;
    }

    inline float2 orbit(float turns) {
        return float2(cos(tau * turns), sin(tau * turns));
    }

    inline float glint(float2 uv, float2 tilt, float2 direction) {
        return wrapped(dot(uv - 0.5, normalize(direction)) - sweep(tilt) * span, span);
    }

    inline float band(float2 uv, float2 tilt, float2 direction, float width) {
        float across = glint(uv, tilt, direction);
        return exp(-across * across * width);
    }

    float3 holo(float3 source, float2 uv, float2 position, float2 tilt) {
        float phase = dot(uv - 0.5, normalize(float2(0.45, 1.0))) * 1.6 + tilt.x * 2.0 + tilt.y;
        float lines = 0.5 + 0.5 * sin(dot(position, normalize(float2(1.0, -1.0))) * 2.2);
        float grain = mix(0.82, 1.0, hash(floor(position)));
        float3 foil = pastel(phase) * mix(0.84, 1.0, lines) * grain;
        float amount = 0.12 + 0.43 * band(uv, tilt, float2(0.6, 1.0), 9.0);
        return mix(source, screen(source, foil), amount);
    }

    float3 rainbow(float3 source, float2 uv, float2 tilt) {
        float phase = dot(uv, normalize(float2(-0.34, 0.94))) * 2.4 + tilt.x * 3.0 - tilt.y * 2.0;
        float amount = 0.3 + 0.35 * band(uv, tilt, float2(-0.5, 1.0), 5.0);
        return mix(source, overlay(source, spectrum(phase)), amount);
    }

    float3 diamond(float3 source, float2 uv, float2 position, float2 tilt) {
        float2 rotated = float2(position.x + position.y, position.y - position.x) * 0.7071;
        float cell = 16.0;
        float2 id = floor(rotated / cell);
        float2 local = fract(rotated / cell) - 0.5;
        float2 facet = sign(local) * 0.7071;
        float light = max(0.0, dot(facet, orbit(sweep(tilt) + 0.25)));
        float2 turns = 1.0 + floor(float2(hash(id + 1.7), hash(id + 5.3)) * 2.0);
        float shift = 0.5 + 0.5 * sin(tau * (hash(id) + dot(turns, tilt)));
        float hue = shift * 0.25 + dot(uv, float2(0.6, 1.0)) * 0.8 + tilt.x - tilt.y;
        float edge = smoothstep(0.46, 0.5, max(abs(local.x), abs(local.y)));
        float3 foil = spectrum(hue) * (0.35 + 0.65 * pow(light, 3.0)) + edge * 0.25;
        float amount = 0.25 + 0.4 * band(uv, tilt, float2(0.7, 1.0), 6.0);
        return mix(source, screen(source, foil), amount);
    }

    float4 hiddenGold(float2 uv, float2 tilt) {
        float across = glint(uv, tilt, float2(0.35, 1.0));
        float flash = exp(-across * across * 40.0);
        float sheen = 0.5 + 0.5 * sin(tau * (uv.y * 2.4 - uv.x * 1.2 + sweep(tilt) * 0.5));
        float3 dim = float3(0.33, 0.23, 0.07);
        float3 metal = mix(mix(dim, dim * 1.6, sheen * 0.5), float3(1.0, 0.86, 0.5), flash);
        return float4(metal, exp(-across * across * 6.0));
    }

    float4 apply(int style, float3 source, float2 uv, float2 position, float2 tilt) {
        switch (style) {
            case 1: return float4(holo(source, uv, position, tilt), 1.0);
            case 2: return float4(rainbow(source, uv, tilt), 1.0);
            case 3: return float4(diamond(source, uv, position, tilt), 1.0);
            case 4: return hiddenGold(uv, tilt);
            default: return float4(source, 1.0);
        }
    }

    inline float3 unpremultiplied(half4 sampled) {
        return float3(sampled.rgb) / max(float(sampled.a), 0.001);
    }

    inline half4 premultiplied(float3 color, float alpha) {
        return half4(half3(clamp(color, 0.0, 1.0) * alpha), half(alpha));
    }
}

[[stitchable]] half4 posterFoil(float2 position, SwiftUI::Layer layer, float2 size, float2 tilt, float style) {
    half4 sampled = layer.sample(position);
    if (sampled.a < 0.01h) { return sampled; }
    float2 uv = position / max(size, float2(1.0));
    float4 result = poster_foil::apply(int(style + 0.5), poster_foil::unpremultiplied(sampled), uv, position, tilt);
    return poster_foil::premultiplied(result.rgb, result.a * float(sampled.a));
}

[[stitchable]] half4 posterFoilMasked(float2 position, SwiftUI::Layer layer, float2 size, float2 tilt, float style,
                                      float mean, texture2d<half> mask) {
    half4 sampled = layer.sample(position);
    if (sampled.a < 0.01h) { return sampled; }
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    float2 uv = position / max(size, float2(1.0));
    float foreground = float(mask.sample(linear, uv).r);
    float3 source = poster_foil::unpremultiplied(sampled);
    float3 delta = (poster_foil::apply(int(style + 0.5), source, uv, position, tilt).rgb - source) * (1.0 - foreground);
    float gain = 0.6 + 0.8 * mean;
    delta *= gain / (1.0 + length(delta) * gain / 0.35);
    return poster_foil::premultiplied(source + delta, float(sampled.a));
}

[[stitchable]] half4 posterBevel(float2 position, half4 color, texture2d<half> map, float2 size, float2 tilt,
                                 float strength, float2 posterSize, float2 origin) {
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    half4 texel = map.sample(linear, position / max(size, float2(1.0)));
    float2 slope = float2(texel.rg) * 2.0 - 1.0;
    float3 normal = float3(slope, sqrt(saturate(1.0 - dot(slope, slope))));
    float3 light = normalize(float3(poster_foil::orbit(poster_foil::sweep(tilt) + 0.64) * 0.78, 0.65));
    float shade = dot(normal, light) - light.z;
    float flare = poster_foil::band((origin + position) / max(posterSize, float2(1.0)), tilt, float2(0.5, 1.0), 6.0);
    float highlight = max(shade, 0.0) * (0.6 + 0.8 * flare);
    float shadow = max(-shade, 0.0) * 0.8;
    float alpha = clamp((highlight + shadow) * strength, 0.0, 0.85) * float(texel.b) * float(color.a);
    float white = highlight / max(highlight + shadow, 1e-4);
    return half4(half3(white * alpha), half(alpha));
}

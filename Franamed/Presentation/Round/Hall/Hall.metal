//
//  Hall.metal
//  Franamed
//
//  Created by Дмитрий Филимонов on 24.09.2026.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace hall {

constant int gridColumns = 24;
constant int gridRows = 14;
constant float3 luma = float3(0.2126, 0.7152, 0.0722);
constant float underSeat = 0.0;

struct Hall {
    float focal;
    float principalY;
    float centerX;
    float3 eye;
    int rows;
    float pitch;
    float rise;
    float arc;
    float recline;
    float seatPitch;
    float backWidth;
    float seatTop;
    float armHeight;
    float armWidth;
    float armLength;
    float armSetback;
    float screenWidth;
    float screenHeight;
    float screenBottom;
    float3 mean;
    device const float *grid;
};

// MARK: Helpers

float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + float2(1, 0)), u.x),
               mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
}

float3 cell(device const float *grid, int2 i) {
    int k = (i.y * gridColumns + i.x) * 3;
    return float3(grid[k], grid[k + 1], grid[k + 2]);
}

float3 screenAt(device const float *grid, float2 uv) {
    float2 inside = smoothstep(float2(-0.06), float2(0.03), uv) * (1.0 - smoothstep(float2(0.97), float2(1.06), uv));
    float fade = inside.x * inside.y;
    if (fade <= 0) return 0;
    float2 c = clamp(uv, 0.0, 1.0) * float2(gridColumns, gridRows) - 0.5;
    int2 limit = int2(gridColumns - 1, gridRows - 1);
    int2 i0 = clamp(int2(floor(c)), int2(0), limit);
    int2 i1 = min(i0 + 1, limit);
    float2 f = saturate(c - float2(i0));
    float3 top = mix(cell(grid, i0), cell(grid, int2(i1.x, i0.y)), f.x);
    float3 bottom = mix(cell(grid, int2(i0.x, i1.y)), cell(grid, i1), f.x);
    return mix(top, bottom, f.y) * fade;
}

float textureFade(thread const Hall &h, float t, float feature) {
    float pixel = t / h.focal / 3.0;
    return saturate(1.0 - pixel / feature);
}

// MARK: Light

float3 light(thread const Hall &h, float3 p, float3 n, float3 d, float albedo, float gloss, float lower) {
    float3 toScreen = float3(0, h.screenBottom + h.screenHeight * 0.5, 0) - p;
    float distance2 = dot(toScreen, toScreen);
    toScreen *= rsqrt(distance2);
    float area = h.screenWidth * h.screenHeight;
    float reach = area / (distance2 + area);
    float wrap = saturate((dot(n, toScreen) + 0.3) / 1.3);
    float facing = saturate(dot(n, -d));

    float diffuse = wrap * reach * 3.6;
    float bounce = 0.4 * (0.5 + 0.5 * n.y) * lower * reach;
    float3 color = h.mean * albedo * (diffuse + bounce);

    float3 r = reflect(d, n);
    if (r.z < -0.02) {
        float3 s = p + (-p.z / r.z) * r;
        float2 uv = float2(s.x / h.screenWidth + 0.5,
                           (h.screenBottom + h.screenHeight - s.y) / h.screenHeight);
        float f0 = gloss > 1.5 ? 0.7 : 0.04;
        float fresnel = f0 + (1.0 - f0) * pow(1.0 - facing, 5.0);
        color += screenAt(h.grid, uv) * fresnel * 10.0 * min(gloss, 1.0);
    }
    return color;
}

float3 perceive(float3 c) {
    float y = dot(c, luma);
    if (y <= 1e-6) return 0;
    float shown = 0.9 * (1.0 - exp(-0.3 * pow(y, 0.85)));
    float dim = 1.0 - smoothstep(0.0, 0.35, shown);
    float3 chroma = mix(c / y, float3(1), 0.2 + 0.25 * dim);
    chroma *= mix(float3(1), float3(0.95, 0.99, 1.07), dim);
    return chroma / dot(chroma, luma) * shown;
}

// MARK: Seats

float roundBox3(float3 p, float3 b, float r) {
    float3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

struct Row {
    float distance;
    float floorY;
    float offset;
    float radius;
};

float rowFace(thread const Row &row, float x) {
    return row.distance - x * x / (2.0 * row.radius);
}

constant float seatThickness = 0.24;

float seat(thread const Hall &h, float lx, float ly, float zl, thread float &crease) {
    float t = seatThickness;
    float bottom = -0.6;
    float shell = roundBox3(float3(lx, ly - (h.seatTop + bottom) * 0.5, zl + t * 0.5),
                            float3(h.backWidth * 0.5, (h.seatTop - bottom) * 0.5, t * 0.5), 0.1);
    float pad = roundBox3(float3(lx, ly - (h.seatTop - 0.1), zl + t * 0.5 - 0.02),
                          float3(h.backWidth * 0.5 + 0.004, 0.11, t * 0.5 + 0.02), 0.09);
    crease = exp(-pow((shell - pad) / 0.006, 2.0)) * step(min(shell, pad), 0.01);
    return min(shell, pad);
}

float arm(thread const Hall &h, float ax, float ly, float zf) {
    return roundBox3(float3(ax, ly - h.armHeight * 0.5, zf + h.armSetback + h.armLength * 0.5),
                     float3(h.armWidth * 0.5, h.armHeight * 0.5, h.armLength * 0.5), 0.035);
}

float field(thread const Hall &h, thread const Row &row, float3 p, thread int &kind, thread float &crease) {
    float ly = p.y - row.floorY;
    float face = rowFace(row, p.x);
    float zl = p.z - face + (h.seatTop - ly) * h.recline;
    float zf = p.z - face;

    float sx = p.x - row.offset;
    float lx = sx - round(sx / h.seatPitch) * h.seatPitch;
    float lxNext = lx - sign(lx) * h.seatPitch;
    float creaseA, creaseB;
    float seatA = seat(h, lx, ly, zl, creaseA);
    float seatB = seat(h, lxNext, ly, zl, creaseB);
    float seats = min(seatA, seatB);

    float gx = sx - h.seatPitch * 0.5;
    float ax = gx - round(gx / h.seatPitch) * h.seatPitch;
    float axNext = ax - sign(ax) * h.seatPitch;
    float arms = min(arm(h, ax, ly, zf), arm(h, axNext, ly, zf));

    kind = arms < seats ? 2 : 0;
    crease = seatA < seatB ? creaseA : creaseB;
    return min(seats, arms);
}

float3 fieldNormal(thread const Hall &h, thread const Row &row, float3 p) {
    const float e = 0.0015;
    int kind; float crease;
    float3 k1 = float3(1, -1, -1), k2 = float3(-1, -1, 1), k3 = float3(-1, 1, -1), k4 = float3(1, 1, 1);
    float3 n = k1 * field(h, row, p + k1 * e, kind, crease) + k2 * field(h, row, p + k2 * e, kind, crease)
             + k3 * field(h, row, p + k3 * e, kind, crease) + k4 * field(h, row, p + k4 * e, kind, crease);
    return normalize(n);
}

float3 shade(thread const Hall &h, thread const Row &row, float3 p, float3 d, float t) {
    int kind; float crease;
    field(h, row, p, kind, crease);
    float3 n = fieldNormal(h, row, p);
    float ly = p.y - row.floorY;
    float albedo = 0.8;
    float gloss = 1.0;

    if (kind == 2) {
        albedo = 0.35 * (0.3 + 0.7 * saturate(n.y));
        gloss = 0.5;
        if (n.y > 0.7) {
            float face = rowFace(row, p.x);
            float sx = p.x - row.offset - h.seatPitch * 0.5;
            float ax = sx - round(sx / h.seatPitch) * h.seatPitch;
            float cup = length(float2(ax, p.z - face + h.armSetback + h.armLength - 0.11)) - 0.045;
            if (cup < 0) { albedo *= 0.15; gloss = 0; }
            else if (cup < 0.007) { gloss = 2.0; }
        }
        float lower = pow(saturate(ly / h.armHeight), 1.5);
        return mix(h.mean * underSeat, light(h, p, n, d, albedo, gloss, lower), smoothstep(0.1, 0.45, ly));
    }

    float2 surface = abs(n.z) > abs(n.x) ? float2(p.x, ly) : float2(p.z, ly);
    if (n.y > 0.7) surface = float2(p.x, p.z);

    float firstSeam = h.seatTop - 0.2;
    if (n.z > 0.4 && ly < firstSeam && ly > 0.3) {
        float u = fract((firstSeam - ly) / 0.17);
        float edge = min(u, 1.0 - u) * 0.17;
        float groove = exp(-pow(edge / 0.008, 2.0));
        n = normalize(n + float3(0, 0.35 * cos(u * M_PI_F), 0));
        albedo *= 1.0 - 0.6 * groove;
        gloss *= 1.0 - 0.8 * groove;
    }
    float grain = noise(surface / 0.0018);
    float fade = textureFade(h, t, 0.0014);
    albedo *= mix(1.0, 0.9 + 0.2 * grain, fade);
    gloss *= mix(1.0, 0.75 + 0.5 * grain, fade);
    albedo *= 1.0 - 0.55 * crease;
    gloss *= 1.0 - 0.8 * crease;

    float lower = pow(saturate((ly - 0.3) / (h.seatTop - 0.3)), 1.6);
    return mix(h.mean * underSeat, light(h, p, n, d, albedo, gloss, lower), smoothstep(0.25, 0.7, ly));
}

float4 march(thread const Hall &h, thread const Row &row, float3 d) {
    float reach = h.pitch - 0.05;
    float tStart = max((row.distance + 0.2 - h.eye.z) / d.z, 0.01);
    float tEnd = (row.distance - reach - h.eye.z) / d.z;
    float pixel = 1.0 / (h.focal * 2.0);

    float3 color = 0;
    float alpha = 0;
    int shaded = 0;
    float t = tStart;
    for (int i = 0; i < 64 && t < tEnd; i++) {
        float3 p = h.eye + t * d;
        int kind; float crease;
        float dist = field(h, row, p, kind, crease);
        float size = t * pixel;
        if (dist < size) {
            float cover = saturate(0.5 - dist / size);
            if (cover > 0.02) {
                float take = (1.0 - alpha) * cover;
                color += take * shade(h, row, p, d, t);
                alpha += take;
                shaded++;
            }
            if (alpha > 0.985 || shaded >= 5) break;
            t += max(dist, size * 0.5);
        } else {
            t += dist * 0.8;
        }
    }
    if (alpha <= 0) return 0;
    return float4(color / alpha, alpha > 0.97 ? 1.0 : alpha);
}
}

[[ stitchable ]] half4 cinemaHall(float2 position, half4 color,
                                  float3 camera, float4 eyeRows, float4 rowShape, float3 seat,
                                  float4 arm, float3 screen, float3 mean,
                                  device const float *grid, int gridCount) {
    using namespace hall;
    Hall h;
    h.focal = camera.x;
    h.principalY = camera.y;
    h.centerX = camera.z;
    h.eye = eyeRows.xyz;
    h.rows = int(eyeRows.w);
    h.pitch = rowShape.x;
    h.rise = rowShape.y;
    h.arc = rowShape.z;
    h.recline = rowShape.w;
    h.seatPitch = seat.x;
    h.backWidth = seat.y;
    h.seatTop = seat.z;
    h.armHeight = arm.x;
    h.armWidth = arm.y;
    h.armLength = arm.z;
    h.armSetback = arm.w;
    h.screenWidth = screen.x;
    h.screenHeight = screen.y;
    h.screenBottom = screen.z;
    h.mean = mean;
    h.grid = grid;

    float3 d = normalize(float3((position.x - h.centerX) / h.focal, -(position.y - h.principalY) / h.focal, -1));

    float3 accumulated = 0;
    float alpha = 0;
    for (int k = 0; k < h.rows && alpha < 0.998; k++) {
        Row row;
        row.distance = h.eye.z - h.pitch * float(k + 1);
        row.radius = row.distance + h.arc;
        row.floorY = h.rise * float(h.rows - k - 1);
        row.offset = (k % 2 == 0) ? h.seatPitch * 0.5 : 0.0;
        float4 s = march(h, row, d);
        accumulated += (1.0 - alpha) * s.a * s.rgb;
        alpha += (1.0 - alpha) * s.a;
    }

    accumulated += (1.0 - alpha) * h.mean * underSeat;
    float3 shown = perceive(accumulated);
    shown = pow(max(shown, 0.0), 1.0 / 2.2);
    return half4(half3(shown), 1.0h);
}

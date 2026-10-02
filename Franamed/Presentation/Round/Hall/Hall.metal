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

constant int skipFrameFlag = 1;
constant int rowBoundsFlag = 2;
constant int ownBoundsFlag = 4;

struct HallArgs {
    float4 camera;
    float4 eyeRows;
    float4 rowShape;
    float4 seat;
    float4 arm;
    float4 screen;
    float4 mean;
    float4 options;
};

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
    int flags;
    float frameTop;
    float frameBottom;
    device const float *grid;
};

Hall makeHall(HallArgs args, device const float *grid) {
    Hall h;
    h.focal = args.camera.x;
    h.principalY = args.camera.y;
    h.centerX = args.camera.z;
    h.eye = args.eyeRows.xyz;
    h.rows = int(args.eyeRows.w);
    h.pitch = args.rowShape.x;
    h.rise = args.rowShape.y;
    h.arc = args.rowShape.z;
    h.recline = args.rowShape.w;
    h.seatPitch = args.seat.x;
    h.backWidth = args.seat.y;
    h.seatTop = args.seat.z;
    h.armHeight = args.arm.x;
    h.armWidth = args.arm.y;
    h.armLength = args.arm.z;
    h.armSetback = args.arm.w;
    h.screenWidth = args.screen.x;
    h.screenHeight = args.screen.y;
    h.screenBottom = args.screen.z;
    h.mean = args.mean.xyz;
    h.flags = int(args.options.x);
    h.frameTop = args.options.y;
    h.frameBottom = args.options.z;
    h.grid = grid;
    return h;
}

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

constant float cupInset = 0.11;
constant float secondCupInset = 0.24;
constant float cupRadius = 0.045;
constant float cupDepth = 0.09;
constant float capHalfWidth = 0.095;
constant float capHalfHeight = 0.035;
constant float bodyHalfWidth = 0.075;
constant float plinthHeight = 0.07;
constant float holderInward = 0.0;
constant int rowArmKind = 10;

enum OwnKind { ownNone, ownCap, ownBody, ownRing, ownPlastic };

float cappedCylinder(float3 q, float radius, float bottom, float top) {
    float2 d = float2(length(q.xz) - radius, abs(q.y - (bottom + top) * 0.5) - (top - bottom) * 0.5);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float torusY(float3 q, float radius, float tube) {
    return length(float2(length(q.xz) - radius, q.y)) - tube;
}

void keep(float d, int k, thread float &best, thread int &kind) {
    if (d < best) { best = d; kind = k; }
}

// MARK: Armrest

struct ArmFrame {
    float3 a;
    float halfLength;
    float inner;
    float holderInward;
    float holders;
    bool plinth;
    bool ring;
};

float3 armHolder(thread const ArmFrame &f, float inset) {
    return float3(f.inner - f.holderInward, f.a.y, f.a.z - (inset - f.halfLength));
}

float armHoles(thread const Hall &h, thread const ArmFrame &f) {
    float holes = cappedCylinder(armHolder(f, cupInset), cupRadius, h.armHeight - cupDepth, h.armHeight + 0.1);
    if (f.holders > 1.5) {
        holes = min(holes, cappedCylinder(armHolder(f, secondCupInset), cupRadius,
                                          h.armHeight - cupDepth, h.armHeight + 0.1));
    }
    return holes;
}

float armRing(thread const Hall &h, thread const ArmFrame &f) {
    float ring = torusY(armHolder(f, cupInset) - float3(0, h.armHeight, 0), cupRadius + 0.003, 0.0045);
    if (f.holders > 1.5) {
        ring = min(ring, torusY(armHolder(f, secondCupInset) - float3(0, h.armHeight, 0), cupRadius + 0.003, 0.0045));
    }
    return ring;
}

float armShape(thread const Hall &h, thread const ArmFrame &f, thread int &part) {
    part = ownCap;
    float outline = roundBox3(f.a - float3(0, h.armHeight * 0.5, 0),
                              float3(capHalfWidth, h.armHeight * 0.5, f.halfLength), 0.04);
    if (outline > 0.03) return outline;
    float holes = armHoles(h, f);

    float best = 10.0;
    float cap = roundBox3(f.a - float3(0, h.armHeight - capHalfHeight, 0),
                          float3(capHalfWidth, capHalfHeight, f.halfLength), 0.03);
    keep(max(cap, -holes), ownCap, best, part);

    float bodyTop = h.armHeight - capHalfHeight * 2.0 + 0.01;
    float body = roundBox3(f.a - float3(0, (plinthHeight + bodyTop) * 0.5, 0.01),
                           float3(bodyHalfWidth, (bodyTop - plinthHeight) * 0.5, f.halfLength - 0.01), 0.025);
    keep(max(body, -holes), ownBody, best, part);

    if (f.plinth) {
        float plinth = roundBox3(f.a - float3(0, plinthHeight * 0.5, 0.03),
                                 float3(bodyHalfWidth - 0.008, plinthHeight * 0.5, f.halfLength - 0.03), 0.01);
        keep(plinth, ownPlastic, best, part);
    }

    if (f.ring) keep(armRing(h, f), ownRing, best, part);
    return best;
}

float3 shadeArm(thread const Hall &h, float3 p, float3 n, float3 d, int part, thread const ArmFrame &f) {
    float lower = pow(saturate(f.a.y / h.armHeight), 1.5);
    float fade = smoothstep(0.1, 0.45, f.a.y);
    float3 dark = h.mean * underSeat;

    switch (part) {
    case ownRing:
        return light(h, p, n, d, 0.3, 2.0, 1.0);
    case ownPlastic:
        return mix(dark, light(h, p, n, d, 0.06, 0.6, lower), fade);
    case ownBody: {
        float albedo = 0.2;
        if (n.z < -0.6) {
            float u = fract(f.inner / 0.03);
            float groove = exp(-pow(min(u, 1.0 - u) * 0.03 / 0.003, 2.0));
            albedo *= 1.0 - 0.6 * groove;
        }
        return mix(dark, light(h, p, n, d, albedo, 0.3, lower), fade);
    }
    default: {
        float albedo = 0.35 * (0.3 + 0.7 * saturate(n.y));
        float gloss = 0.5;
        albedo *= 0.9 + 0.2 * noise(float2(f.a.x, f.a.z) / 0.0018);
        if (n.y > 0.7) {
            float edge = capHalfWidth - abs(f.a.x);
            float stitch = exp(-pow((edge - 0.012) / 0.0012, 2.0)) * step(0.5, fract(f.a.z / 0.008));
            albedo *= 1.0 - 0.5 * stitch;
            gloss *= 1.0 - 0.6 * stitch;
        }
        float cup = length(armHolder(f, cupInset).xz) - cupRadius;
        if (f.holders > 1.5) cup = min(cup, length(armHolder(f, secondCupInset).xz) - cupRadius);
        if (cup < 0) { albedo *= 0.15; gloss = 0; }
        return mix(dark, light(h, p, n, d, albedo, gloss, lower), fade);
    }
    }
}

ArmFrame rowArm(thread const Hall &h, float ax, float ly, float zf) {
    ArmFrame f;
    f.a = float3(ax, ly, zf + h.armSetback + h.armLength * 0.5);
    f.halfLength = h.armLength * 0.5;
    f.inner = ax;
    f.holderInward = 0;
    f.holders = 1;
    f.plinth = false;
    f.ring = true;
    return f;
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

    crease = seatA < seatB ? creaseA : creaseB;

    float gx = sx - h.seatPitch * 0.5;
    float ax = gx - round(gx / h.seatPitch) * h.seatPitch;
    float axNext = ax - sign(ax) * h.seatPitch;
    int partA, partB;
    float armA = armShape(h, rowArm(h, ax, ly, zf), partA);
    float armB = armShape(h, rowArm(h, axNext, ly, zf), partB);
    float arms = min(armA, armB);

    kind = arms < seats ? rowArmKind + (armA < armB ? partA : partB) : 0;
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

float3 shadeSeat(thread const Hall &h, thread const Row &row, float3 p, float3 n, float3 d, float t, float crease);

float3 shade(thread const Hall &h, thread const Row &row, float3 p, float3 d, float t) {
    int kind; float crease;
    field(h, row, p, kind, crease);
    float3 n = fieldNormal(h, row, p);
    float ly = p.y - row.floorY;

    if (kind >= rowArmKind) {
        float zf = p.z - rowFace(row, p.x);
        float gx = p.x - row.offset - h.seatPitch * 0.5;
        float ax = gx - round(gx / h.seatPitch) * h.seatPitch;
        ArmFrame fa = rowArm(h, ax, ly, zf);
        ArmFrame fb = rowArm(h, ax - sign(ax) * h.seatPitch, ly, zf);
        int part;
        bool nearA = armShape(h, fa, part) < armShape(h, fb, part);
        return shadeArm(h, p, n, d, kind - rowArmKind, nearA ? fa : fb);
    }
    return shadeSeat(h, row, p, n, d, t, crease);
}

float3 shadeSeat(thread const Hall &h, thread const Row &row, float3 p, float3 n, float3 d, float t, float crease) {
    float ly = p.y - row.floorY;
    float albedo = 0.8;
    float gloss = 1.0;
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

float4 march(thread const Hall &h, thread const Row &row, float3 d, thread float &hitT) {
    hitT = 0;
    float reach = h.pitch - 0.05;
    float tStart = max((row.distance + 0.2 - h.eye.z) / d.z, 0.01);
    float tEnd = (row.distance - reach - h.eye.z) / d.z;
    if ((h.flags & rowBoundsFlag) != 0) {
        float top = row.floorY + h.seatTop + 0.04;
        if (min(h.eye.y + tStart * d.y, h.eye.y + tEnd * d.y) > top) return 0;
        if (d.y < 0) tStart = max(tStart, (top - h.eye.y) / d.y);
    }
    float pixel = 1.0 / (h.focal * 2.0);

    float3 color = 0;
    float3 last = 0;
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
                if (shaded < 5) {
                    last = shade(h, row, p, d, t);
                    shaded++;
                }
                if (hitT == 0) hitT = t;
                float take = (1.0 - alpha) * cover;
                color += take * last;
                alpha += take;
            }
            if (alpha > 0.985) break;
            t += max(dist, size * 0.5);
        } else {
            t += dist * 0.8;
        }
    }
    if (alpha <= 0) return 0;
    return float4(color / alpha, alpha > 0.97 ? 1.0 : alpha);
}

// MARK: Own seat

constant float ownArmReach = 0.85;
constant float ownArmLength = 0.9;

struct OwnPoint {
    float3 q;
    float3 a;
    float side;
    float inner;
    float tip;
};

float3 ownLocal(thread const Hall &h, float3 p) {
    return float3(p.x, p.y - h.rise * float(h.rows), p.z - h.eye.z);
}

OwnPoint ownPoint(thread const Hall &h, float3 p) {
    OwnPoint o;
    o.q = ownLocal(h, p);
    o.side = o.q.x < 0 ? -1.0 : 1.0;
    o.a = float3(o.q.x - o.side * h.seatPitch * 0.5, o.q.y, o.q.z + ownArmReach - ownArmLength * 0.5);
    o.inner = -o.side * o.a.x;
    o.tip = -ownArmLength * 0.5;
    return o;
}

ArmFrame ownArm(thread const Hall &h, thread const OwnPoint &o) {
    ArmFrame f;
    f.a = o.a;
    f.halfLength = ownArmLength * 0.5;
    f.inner = o.inner;
    f.holderInward = holderInward;
    f.holders = 1;
    f.plinth = true;
    f.ring = true;
    return f;
}

float ownField(thread const Hall &h, float3 p, thread int &kind) {
    return armShape(h, ownArm(h, ownPoint(h, p)), kind);
}

float3 ownNormal(thread const Hall &h, float3 p) {
    const float e = 0.001;
    int kind;
    float3 k1 = float3(1, -1, -1), k2 = float3(-1, -1, 1), k3 = float3(-1, 1, -1), k4 = float3(1, 1, 1);
    return normalize(k1 * ownField(h, p + k1 * e, kind) + k2 * ownField(h, p + k2 * e, kind)
                   + k3 * ownField(h, p + k3 * e, kind) + k4 * ownField(h, p + k4 * e, kind));
}

float3 ownShadeWith(thread const Hall &h, float3 p, float3 d, float3 n, int kind);

float3 ownShade(thread const Hall &h, float3 p, float3 d) {
    int kind;
    ownField(h, p, kind);
    return ownShadeWith(h, p, d, ownNormal(h, p), kind);
}

float3 ownShadeWith(thread const Hall &h, float3 p, float3 d, float3 n, int kind) {
    return shadeArm(h, p, n, d, kind, ownArm(h, ownPoint(h, p)));
}

float2 boxRange(float3 origin, float3 inverse, float3 low, float3 high) {
    float3 a = (low - origin) * inverse;
    float3 b = (high - origin) * inverse;
    float3 enter = min(a, b);
    float3 leave = max(a, b);
    return float2(max(max(enter.x, enter.y), enter.z), min(min(leave.x, leave.y), leave.z));
}

float2 ownRange(thread const Hall &h, float3 d) {
    float3 origin = ownLocal(h, h.eye);
    float3 inverse = 1.0 / d;
    float2 range = float2(1e9, -1e9);
    for (int side = -1; side <= 1; side += 2) {
        float x = float(side) * h.seatPitch * 0.5;
        float2 r = boxRange(origin, inverse, float3(x - 0.25, -0.05, -1.05), float3(x + 0.25, h.armHeight + 0.05, 0.2));
        if (r.x <= r.y) range = float2(min(range.x, r.x), max(range.y, r.y));
    }
    return range;
}

float4 marchOwn(thread const Hall &h, float3 d, thread float &hitT) {
    hitT = 0;
    float pixel = 1.0 / (h.focal * 2.0);
    float t = 0.05;
    float tEnd = 2.0;
    if ((h.flags & ownBoundsFlag) != 0) {
        float2 range = ownRange(h, d);
        if (range.x > range.y) return 0;
        t = max(t, range.x);
        tEnd = min(tEnd, range.y);
    }

    float3 color = 0;
    float3 last = 0;
    float alpha = 0;
    int shaded = 0;
    for (int i = 0; i < 48 && t < tEnd; i++) {
        float3 p = h.eye + t * d;
        int kind;
        float dist = ownField(h, p, kind);
        float size = t * pixel;
        if (dist < size) {
            float cover = saturate(0.5 - dist / size);
            if (cover > 0.02) {
                if (shaded < 4) {
                    last = ownShade(h, p, d);
                    shaded++;
                }
                if (hitT == 0) hitT = t;
                float take = (1.0 - alpha) * cover;
                color += take * last;
                alpha += take;
            }
            if (alpha > 0.985) break;
            t += max(dist, size * 0.5);
        } else {
            t += dist * 0.9;
        }
    }
    if (alpha <= 0) return 0;
    return float4(color / alpha, alpha > 0.97 ? 1.0 : alpha);
}

float3 rayAt(thread const Hall &h, float2 position) {
    return normalize(float3((position.x - h.centerX) / h.focal, -(position.y - h.principalY) / h.focal, -1));
}

bool underFrame(thread const Hall &h, float2 position) {
    return (h.flags & skipFrameFlag) != 0 && position.y > h.frameTop && position.y < h.frameBottom;
}

float4 renderRows(thread const Hall &h, float3 d) {
    float3 accumulated = 0;
    float alpha = 0;
    for (int k = 0; k < h.rows && alpha < 0.998; k++) {
        Row row;
        row.distance = h.eye.z - h.pitch * float(k + 1);
        row.radius = row.distance + h.arc;
        row.floorY = h.rise * float(h.rows - k - 1);
        row.offset = (k % 2 == 0) ? h.seatPitch * 0.5 : 0.0;
        float hitT;
        float4 s = march(h, row, d, hitT);
        accumulated += (1.0 - alpha) * s.a * s.rgb;
        alpha += (1.0 - alpha) * s.a;
    }
    return float4(accumulated, alpha);
}

float3 finish(thread const Hall &h, float3 near, float nearAlpha, float4 rows) {
    float3 accumulated = nearAlpha * near + (1.0 - nearAlpha) * rows.rgb;
    float alpha = nearAlpha + (1.0 - nearAlpha) * rows.a;
    accumulated += (1.0 - alpha) * h.mean * underSeat;
    float3 shown = perceive(accumulated);
    return pow(max(shown, 0.0), 1.0 / 2.2);
}

float3 render(thread const Hall &h, float2 position) {
    if (underFrame(h, position)) return 0;
    float3 d = rayAt(h, position);
    float hitT;
    float4 near = marchOwn(h, d, hitT);
    float4 rows = near.a > 0.998 ? float4(0) : renderRows(h, d);
    return finish(h, near.rgb, near.a, rows);
}
}

[[ stitchable ]] half4 cinemaHall(float2 position, half4 color,
                                  float4 camera, float4 eyeRows, float4 rowShape, float4 seat,
                                  float4 arm, float4 screen, float4 mean, float4 options,
                                  device const float *grid, int gridCount) {
    using namespace hall;
    HallArgs args = { camera, eyeRows, rowShape, seat, arm, screen, mean, options };
    Hall h = makeHall(args, grid);
    return half4(half3(render(h, position)), 1.0h);
}

[[ kernel ]] void cinemaHallKernel(texture2d<float, access::write> target [[ texture(0) ]],
                                   constant hall::HallArgs &args [[ buffer(0) ]],
                                   device const float *grid [[ buffer(1) ]],
                                   uint2 gid [[ thread_position_in_grid ]]) {
    using namespace hall;
    if (gid.x >= target.get_width() || gid.y >= target.get_height()) return;
    Hall h = makeHall(args, grid);
    target.write(float4(render(h, float2(gid) + 0.5), 1.0), gid);
}

// MARK: Mesh

namespace hall {

enum MeshShape { meshSeat, meshRowArm, meshRowRing, meshOwnArm, meshOwnRing };

struct MeshGrid {
    float4 origin;
    uint4 dims;
    uint4 limits;
};

struct MeshDraw {
    float4 row;
    float4 instance;
};

constant uint noVertex = 0xFFFFFFFF;

ArmFrame bare(ArmFrame f) {
    f.ring = false;
    return f;
}

float3 ownWorld(thread const Hall &h, float3 q) {
    return float3(q.x, q.y + h.rise * float(h.rows), q.z + h.eye.z);
}

float meshField(thread const Hall &h, int shape, float3 q) {
    int part;
    switch (shape) {
    case meshSeat: {
        float crease;
        return seat(h, q.x, q.y, q.z, crease);
    }
    case meshRowArm:
        return armShape(h, bare(rowArm(h, q.x, q.y, q.z)), part);
    case meshRowRing:
        return armRing(h, rowArm(h, q.x, q.y, q.z));
    case meshOwnArm:
        return armShape(h, bare(ownArm(h, ownPoint(h, ownWorld(h, q)))), part);
    case meshOwnRing:
        return armRing(h, ownArm(h, ownPoint(h, ownWorld(h, q))));
    default:
        return 10.0;
    }
}

float3 meshGradient(thread const Hall &h, int shape, float3 q, float e) {
    float3 k1 = float3(1, -1, -1), k2 = float3(-1, -1, 1), k3 = float3(-1, 1, -1), k4 = float3(1, 1, 1);
    return (k1 * meshField(h, shape, q + k1 * e) + k2 * meshField(h, shape, q + k2 * e)
          + k3 * meshField(h, shape, q + k3 * e) + k4 * meshField(h, shape, q + k4 * e)) / (4.0 * e);
}

uint pointIndex(uint3 p, uint3 n) {
    return (p.z * n.y + p.y) * n.x + p.x;
}

constant uchar2 cubeEdges[12] = {
    uchar2(0, 1), uchar2(2, 3), uchar2(4, 5), uchar2(6, 7),
    uchar2(0, 2), uchar2(1, 3), uchar2(4, 6), uchar2(5, 7),
    uchar2(0, 4), uchar2(1, 5), uchar2(2, 6), uchar2(3, 7),
};

float3 cornerOffset(uint i) {
    return float3(i & 1, (i >> 1) & 1, (i >> 2) & 1);
}

Row meshRow(float4 placement) {
    Row row;
    row.offset = 0;
    row.floorY = placement.y;
    row.distance = placement.z;
    row.radius = placement.w;
    return row;
}

uint along(uint3 v, uint3 axis) {
    return v.x * axis.x + v.y * axis.y + v.z * axis.z;
}

float seatAt(thread const Hall &h, thread const Row &row, float center, float3 p, thread float &crease) {
    float ly = p.y - row.floorY;
    float zl = p.z - rowFace(row, p.x) + (h.seatTop - ly) * h.recline;
    return seat(h, p.x - center, ly, zl, crease);
}

ArmFrame rowArmAt(thread const Hall &h, thread const Row &row, float center, float3 p) {
    return rowArm(h, p.x - center, p.y - row.floorY, p.z - rowFace(row, p.x));
}

}

[[ kernel ]] void hallMeshSample(device float *samples [[ buffer(0) ]],
                                 constant hall::HallArgs &args [[ buffer(1) ]],
                                 constant hall::MeshGrid &grid [[ buffer(2) ]],
                                 uint3 gid [[ thread_position_in_grid ]]) {
    using namespace hall;
    uint3 n = grid.dims.xyz + 1;
    if (any(gid >= n)) return;
    Hall h = makeHall(args, nullptr);
    samples[pointIndex(gid, n)] = meshField(h, int(grid.dims.w), grid.origin.xyz + float3(gid) * grid.origin.w);
}

[[ kernel ]] void hallMeshVertices(device const float *samples [[ buffer(0) ]],
                                   constant hall::HallArgs &args [[ buffer(1) ]],
                                   constant hall::MeshGrid &grid [[ buffer(2) ]],
                                   device uint *cells [[ buffer(3) ]],
                                   device float4 *vertices [[ buffer(4) ]],
                                   device atomic_uint *counts [[ buffer(5) ]],
                                   uint3 gid [[ thread_position_in_grid ]]) {
    using namespace hall;
    uint3 c = grid.dims.xyz;
    if (any(gid >= c)) return;
    uint3 n = c + 1;
    uint cell = pointIndex(gid, c);

    float v[8];
    int inside = 0;
    for (uint i = 0; i < 8; i++) {
        v[i] = samples[pointIndex(gid + uint3(cornerOffset(i)), n)];
        inside += v[i] < 0 ? 1 : 0;
    }
    if (inside == 0 || inside == 8) {
        cells[cell] = noVertex;
        return;
    }

    float3 sum = 0;
    float crossings = 0;
    for (int e = 0; e < 12; e++) {
        float a = v[cubeEdges[e].x], b = v[cubeEdges[e].y];
        if ((a < 0) == (b < 0)) continue;
        sum += mix(cornerOffset(cubeEdges[e].x), cornerOffset(cubeEdges[e].y), a / (a - b));
        crossings += 1;
    }

    float voxel = grid.origin.w;
    float3 low = grid.origin.xyz + float3(gid) * voxel;
    float3 p = low + sum / crossings * voxel;
    Hall h = makeHall(args, nullptr);
    int shape = int(grid.dims.w);
    for (int k = 0; k < 3; k++) {
        float d = meshField(h, shape, p);
        float3 g = meshGradient(h, shape, p, voxel * 0.05);
        float g2 = dot(g, g);
        if (g2 < 1e-6) break;
        p = clamp(p - d * g / g2, low - voxel * 0.5, low + voxel * 1.5);
    }

    uint index = atomic_fetch_add_explicit(&counts[0], 1, memory_order_relaxed);
    if (index >= grid.limits.x) {
        cells[cell] = noVertex;
        return;
    }
    vertices[index * 2] = float4(p, 1);
    vertices[index * 2 + 1] = float4(normalize(meshGradient(h, shape, p, 0.0005)), 0);
    cells[cell] = index;
}

[[ kernel ]] void hallMeshQuads(device const float *samples [[ buffer(0) ]],
                                constant hall::MeshGrid &grid [[ buffer(2) ]],
                                device const uint *cells [[ buffer(3) ]],
                                device uint *indices [[ buffer(4) ]],
                                device atomic_uint *counts [[ buffer(5) ]],
                                uint3 gid [[ thread_position_in_grid ]]) {
    using namespace hall;
    uint3 c = grid.dims.xyz;
    uint3 n = c + 1;
    if (any(gid >= n)) return;
    float s0 = samples[pointIndex(gid, n)];

    for (int axis = 0; axis < 3; axis++) {
        uint3 e = uint3(axis == 0, axis == 1, axis == 2);
        uint3 u = uint3(axis == 2, axis == 0, axis == 1);
        uint3 w = uint3(axis == 1, axis == 2, axis == 0);
        uint3 next = gid + e;
        if (any(next >= n)) continue;
        float s1 = samples[pointIndex(next, n)];
        if ((s0 < 0) == (s1 < 0)) continue;
        if (along(gid, u) == 0 || along(gid, w) == 0 || along(gid, u) >= along(c, u) || along(gid, w) >= along(c, w)) continue;

        uint a = cells[pointIndex(gid - u - w, c)];
        uint b = cells[pointIndex(gid - w, c)];
        uint d = cells[pointIndex(gid, c)];
        uint f = cells[pointIndex(gid - u, c)];
        if (a == noVertex || b == noVertex || d == noVertex || f == noVertex) continue;

        uint base = atomic_fetch_add_explicit(&counts[1], 6, memory_order_relaxed);
        if (base + 6 > grid.limits.y) continue;
        bool flip = s0 < 0;
        indices[base] = a;
        indices[base + 1] = flip ? d : b;
        indices[base + 2] = flip ? b : d;
        indices[base + 3] = a;
        indices[base + 4] = flip ? f : d;
        indices[base + 5] = flip ? d : f;
    }
}

struct HallMeshOut {
    float4 position [[ position ]];
    float3 world;
    float3 normal;
    float center [[ flat ]];
};

constant float meshNear = 0.05;
constant float meshFar = 40.0;
constant float meshMinFacing = 0.05;

[[ vertex ]] HallMeshOut hallMeshVertex(uint vid [[ vertex_id ]],
                                        uint iid [[ instance_id ]],
                                        device const float4 *vertices [[ buffer(0) ]],
                                        constant hall::HallArgs &args [[ buffer(1) ]],
                                        constant hall::MeshDraw &draw [[ buffer(2) ]],
                                        constant float4 &viewport [[ buffer(3) ]]) {
    using namespace hall;
    Hall h = makeHall(args, nullptr);
    float3 q = vertices[vid * 2].xyz;
    float3 g = vertices[vid * 2 + 1].xyz;
    int shape = int(draw.instance.x);
    float center = draw.row.x + (draw.instance.y + float(iid)) * h.seatPitch;

    float3 p;
    float3 n = g;
    if (shape >= meshOwnArm) {
        p = ownWorld(h, q);
    } else {
        Row row = meshRow(draw.row);
        float x = center + q.x;
        bool seated = shape == meshSeat;
        float zf = seated ? q.z - (h.seatTop - q.y) * h.recline : q.z;
        p = float3(x, row.floorY + q.y, zf + rowFace(row, x));
        n = float3(g.x + g.z * x / row.radius, g.y - (seated ? g.z * h.recline : 0.0), g.z);
    }

    float3 v = p - h.eye;
    float w = -v.z;
    HallMeshOut out;
    out.position = float4((2.0 * h.centerX / viewport.x - 1.0) * w + 2.0 * h.focal / viewport.x * v.x,
                          (1.0 - 2.0 * h.principalY / viewport.y) * w + 2.0 * h.focal / viewport.y * v.y,
                          meshFar / (meshFar - meshNear) * (w - meshNear),
                          w);
    out.world = p;
    out.normal = n;
    out.center = center;
    return out;
}

constant int meshGroup [[ function_constant(0) ]];

[[ fragment ]] float4 hallMeshFragment(HallMeshOut in [[ stage_in ]],
                                       constant hall::HallArgs &args [[ buffer(0) ]],
                                       device const float *grid [[ buffer(1) ]],
                                       constant hall::MeshDraw &draw [[ buffer(2) ]]) {
    using namespace hall;
    Hall h = makeHall(args, grid);
    float3 p = in.world;
    float3 toPoint = p - h.eye;
    float t = length(toPoint);
    float3 d = toPoint / t;
    float3 color;

    float3 n = normalize(in.normal);
    float facing = dot(n, -d);
    if (facing < meshMinFacing) n = normalize(n - (meshMinFacing - facing) * d);
    if (meshGroup == 2) {
        int kind;
        ownField(h, p, kind);
        color = ownShadeWith(h, p, d, n, kind);
    } else {
        Row row = meshRow(draw.row);
        if (meshGroup == 0) {
            float crease;
            seatAt(h, row, in.center, p, crease);
            color = shadeSeat(h, row, p, n, d, t, crease);
        } else {
            int part;
            ArmFrame frame = rowArmAt(h, row, in.center, p);
            armShape(h, frame, part);
            color = shadeArm(h, p, n, d, part, frame);
        }
    }
    return float4(finish(h, color, 1.0, float4(0)), 1.0);
}

[[ vertex ]] float4 hallMeshOccluder(uint vid [[ vertex_id ]],
                                     constant hall::HallArgs &args [[ buffer(1) ]],
                                     constant float4 &viewport [[ buffer(3) ]]) {
    float y = (vid & 2) ? args.options.z : args.options.y;
    return float4((vid & 1) ? 1.0 : -1.0, 1.0 - 2.0 * y / viewport.y, 0.0, 1.0);
}

[[ fragment ]] float4 hallMeshBlack() {
    return float4(0, 0, 0, 1);
}

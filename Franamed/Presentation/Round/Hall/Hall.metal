//
//  Hall.metal
//  Franamed
//
//  Created by Дмитрий Филимонов on 24.09.2026.
//

#include <metal_stdlib>
using namespace metal;

namespace hall {

constant int gridColumns = 24;
constant int spinnerPetals = 8;
constant int gridRows = 14;
constant float3 luma = float3(0.2126, 0.7152, 0.0722);

struct HallArgs {
    float4 camera;
    float4 eye;
    float4 rows;
    float4 seat;
    float4 arm;
    float4 screen;
    float4 mean;
    float4 frame;
    float4 picture;
    float4 glow;
};

struct PhoneArgs {
    float4 right;
    float4 up;
    float4 back;
    float4 cameraRight;
    float4 cameraUp;
    float4 cameraBack;
    float4 center;
    float4 face;
    float4 lens;
    float4 view;
    float4 chrome;
    float4 color;
    float4 stage;
    float4 glow;
};

struct Hall {
    float focal;
    float principalY;
    float centerX;
    float3 eye;
    int rows;
    float rise;
    float recline;
    float seatPitch;
    float backWidth;
    float seatTop;
    float armHeight;
    float armLength;
    float armSetback;
    float screenWidth;
    float screenHeight;
    float screenBottom;
    float3 mean;
    device const float *grid;
};

Hall makeHall(HallArgs args, device const float *grid) {
    Hall h;
    h.focal = args.camera.x;
    h.principalY = args.camera.y;
    h.centerX = args.camera.z;
    h.eye = args.eye.xyz;
    h.rows = int(args.rows.x);
    h.rise = args.rows.y;
    h.recline = args.rows.z;
    h.seatPitch = args.seat.x;
    h.backWidth = args.seat.y;
    h.seatTop = args.seat.z;
    h.armHeight = args.arm.x;
    h.armLength = args.arm.y;
    h.armSetback = args.arm.z;
    h.screenWidth = args.screen.x;
    h.screenHeight = args.screen.y;
    h.screenBottom = args.screen.z;
    h.mean = args.mean.xyz;
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
constant float cupRadius = 0.045;
constant float cupDepth = 0.09;
constant float capHalfWidth = 0.095;
constant float capHalfHeight = 0.035;
constant float bodyHalfWidth = 0.075;
constant float plinthHeight = 0.07;

enum ArmPart { partCap, partBody, partRing, partPlastic };

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
    bool plinth;
    bool ring;
};

float3 armHolder(thread const ArmFrame &f) {
    return float3(f.inner, f.a.y, f.a.z - (cupInset - f.halfLength));
}

float armHole(thread const Hall &h, thread const ArmFrame &f) {
    return cappedCylinder(armHolder(f), cupRadius, h.armHeight - cupDepth, h.armHeight + 0.1);
}

float armRing(thread const Hall &h, thread const ArmFrame &f) {
    return torusY(armHolder(f) - float3(0, h.armHeight, 0), cupRadius + 0.003, 0.0045);
}

float armShape(thread const Hall &h, thread const ArmFrame &f, thread int &part) {
    part = partCap;
    float outline = roundBox3(f.a - float3(0, h.armHeight * 0.5, 0),
                              float3(capHalfWidth, h.armHeight * 0.5, f.halfLength), 0.04);
    if (outline > 0.03) return outline;
    float hole = armHole(h, f);

    float best = 10.0;
    float cap = roundBox3(f.a - float3(0, h.armHeight - capHalfHeight, 0),
                          float3(capHalfWidth, capHalfHeight, f.halfLength), 0.03);
    keep(max(cap, -hole), partCap, best, part);

    float bodyTop = h.armHeight - capHalfHeight * 2.0 + 0.01;
    float body = roundBox3(f.a - float3(0, (plinthHeight + bodyTop) * 0.5, 0.01),
                           float3(bodyHalfWidth, (bodyTop - plinthHeight) * 0.5, f.halfLength - 0.01), 0.025);
    keep(max(body, -hole), partBody, best, part);

    if (f.plinth) {
        float plinth = roundBox3(f.a - float3(0, plinthHeight * 0.5, 0.03),
                                 float3(bodyHalfWidth - 0.008, plinthHeight * 0.5, f.halfLength - 0.03), 0.01);
        keep(plinth, partPlastic, best, part);
    }

    if (f.ring) keep(armRing(h, f), partRing, best, part);
    return best;
}

float3 shadeArm(thread const Hall &h, float3 p, float3 n, float3 d, int part, thread const ArmFrame &f) {
    float lower = pow(saturate(f.a.y / h.armHeight), 1.5);
    float fade = smoothstep(0.1, 0.45, f.a.y);

    switch (part) {
    case partRing:
        return light(h, p, n, d, 0.3, 2.0, 1.0);
    case partPlastic:
        return light(h, p, n, d, 0.06, 0.6, lower) * fade;
    case partBody: {
        float albedo = 0.2;
        if (n.z < -0.6) {
            float u = fract(f.inner / 0.03);
            float groove = exp(-pow(min(u, 1.0 - u) * 0.03 / 0.003, 2.0));
            albedo *= 1.0 - 0.6 * groove;
        }
        return light(h, p, n, d, albedo, 0.3, lower) * fade;
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
        if (length(armHolder(f).xz) < cupRadius) { albedo *= 0.15; gloss = 0; }
        return light(h, p, n, d, albedo, gloss, lower) * fade;
    }
    }
}

ArmFrame rowArm(thread const Hall &h, float ax, float ly, float zf) {
    ArmFrame f;
    f.a = float3(ax, ly, zf + h.armSetback + h.armLength * 0.5);
    f.halfLength = h.armLength * 0.5;
    f.inner = ax;
    f.plinth = false;
    f.ring = true;
    return f;
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
    return light(h, p, n, d, albedo, gloss, lower) * smoothstep(0.25, 0.7, ly);
}

// MARK: Own seat

constant float ownArmReach = 0.85;
constant float ownArmLength = 0.9;

struct OwnPoint {
    float3 q;
    float3 a;
    float inner;
};

float3 ownLocal(thread const Hall &h, float3 p) {
    return float3(p.x, p.y - h.rise * float(h.rows), p.z - h.eye.z);
}

OwnPoint ownPoint(thread const Hall &h, float3 p) {
    OwnPoint o;
    o.q = ownLocal(h, p);
    float side = o.q.x < 0 ? -1.0 : 1.0;
    o.a = float3(o.q.x - side * h.seatPitch * 0.5, o.q.y, o.q.z + ownArmReach - ownArmLength * 0.5);
    o.inner = -side * o.a.x;
    return o;
}

ArmFrame ownArm(thread const Hall &h, thread const OwnPoint &o) {
    ArmFrame f;
    f.a = o.a;
    f.halfLength = ownArmLength * 0.5;
    f.inner = o.inner;
    f.plinth = true;
    f.ring = true;
    return f;
}

float3 finish(float3 color) {
    return pow(max(perceive(color), 0.0), 1.0 / 2.2);
}

// MARK: Mesh

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
    if (meshGroup == 0) {
        Row row = meshRow(draw.row);
        float crease;
        seatAt(h, row, in.center, p, crease);
        color = shadeSeat(h, row, p, n, d, t, crease);
    } else {
        ArmFrame frame = meshGroup == 2 ? ownArm(h, ownPoint(h, p)) : rowArmAt(h, meshRow(draw.row), in.center, p);
        int part;
        armShape(h, frame, part);
        color = shadeArm(h, p, n, d, part, frame);
    }
    return float4(finish(color), 1.0);
}

struct HallPictureOut {
    float4 position [[ position ]];
    float2 uv;
};

[[ vertex ]] HallPictureOut hallPictureVertex(uint vid [[ vertex_id ]],
                                              constant hall::HallArgs &args [[ buffer(1) ]],
                                              constant float4 &viewport [[ buffer(3) ]]) {
    float2 corner = float2(vid & 1, (vid >> 1) & 1);
    float x = mix(args.frame.z, args.frame.w, corner.x);
    float y = mix(args.frame.x, args.frame.y, corner.y);
    HallPictureOut out;
    out.position = float4(2.0 * x / viewport.x - 1.0, 1.0 - 2.0 * y / viewport.y, 0.99999, 1.0);
    out.uv = corner;
    return out;
}

[[ fragment ]] float4 hallPictureFragment(HallPictureOut in [[ stage_in ]],
                                          constant hall::HallArgs &args [[ buffer(0) ]],
                                          texture2d<float> picture [[ texture(0) ]]) {
    float boxAspect = (args.frame.w - args.frame.z) / max(args.frame.y - args.frame.x, 1.0);
    float ratio = args.picture.x / max(boxAspect, 0.01);
    float2 uv = in.uv;
    if (ratio > 1.0) {
        uv.y = (uv.y - 0.5) * ratio + 0.5;
    } else if (ratio > 0.0) {
        uv.x = (uv.x - 0.5) / ratio + 0.5;
    }
    constexpr sampler linear(filter::linear, mip_filter::linear, address::clamp_to_edge);
    float3 color = picture.sample(linear, uv, bias(-0.5)).rgb;
    bool inside = args.picture.y > 0.5 && all(uv >= 0.0) && all(uv <= 1.0);
    color = inside ? color : float3(0.0);
    if (args.picture.w >= 0.0) {
        float2 box = float2(args.picture.z, args.picture.z / max(boxAspect, 0.01));
        float2 p = (in.uv - 0.5) * box;
        float pixel = max(fwidth(p.x), 1e-3);
        float step = floor(args.picture.w * hall::spinnerPetals);
        for (int i = 0; i < hall::spinnerPetals; i++) {
            float angle = float(i) * 2.0 * M_PI_F / float(hall::spinnerPetals);
            float2 axis = float2(sin(angle), -cos(angle));
            float along = clamp(dot(p, axis), 4.2, 6.8);
            float distance = length(p - axis * along) - 1.2;
            float age = fract((step - float(i)) / float(hall::spinnerPetals));
            float shade = 1.0 - 0.75 * age;
            color = mix(color, float3(1.0), (1.0 - smoothstep(-pixel, pixel, distance)) * shade);
        }
    }
    return float4(color, 1.0);
}

namespace phone {

constant int perimeterSegments = 160;
constant float nearDepth = 0.05;

float4 project(float3 p, constant hall::PhoneArgs &phone, float4 viewport) {
    float w = -p.z;
    float f = phone.stage.z;
    float z = 0.0002 + (w - (phone.center.z - nearDepth)) * 0.005;
    return float4((2.0 * phone.stage.x / viewport.x - 1.0) * w + 2.0 * f / viewport.x * p.x,
                  (1.0 - 2.0 * phone.stage.y / viewport.y) * w + 2.0 * f / viewport.y * p.y,
                  z * w,
                  w);
}

float3 place(float2 delta, float depth, constant hall::PhoneArgs &phone) {
    float distance = phone.center.z;
    float metersPerPixel = distance / phone.stage.z;
    float2 offset = (phone.center.xy - phone.stage.xy) * float2(1.0, -1.0) * metersPerPixel;
    float2 local = float2(delta.x, -delta.y) * metersPerPixel;
    return float3(offset, -distance) + phone.right.xyz * local.x + phone.up.xyz * local.y + phone.back.xyz * depth;
}

bool isPortrait(constant hall::PhoneArgs &phone) {
    return phone.chrome.x > 0.5;
}

float2 toPortrait(float2 delta, constant hall::PhoneArgs &phone) {
    return isPortrait(phone) ? delta : float2(-delta.y, delta.x);
}

float2 fromPortrait(float2 q, constant hall::PhoneArgs &phone) {
    return isPortrait(phone) ? q : float2(q.y, -q.x);
}

float2 portraitExtent(constant hall::PhoneArgs &phone) {
    return (isPortrait(phone) ? phone.face.xy : phone.face.yx) * 0.5;
}

float cornerRadius(float2 extent) {
    return 0.155 * extent.x * 2.0;
}

void perimeter(float t, float2 extent, float radius, thread float2 &point, thread float2 &normal) {
    float lx = 2.0 * (extent.x - radius), ly = 2.0 * (extent.y - radius), arc = radius * M_PI_F * 0.5;
    float lengths[8] = { lx, arc, ly, arc, lx, arc, ly, arc };
    float2 corners[4] = { float2(1, -1), float2(1, 1), float2(-1, 1), float2(-1, -1) };
    float s = fract(t) * (2.0 * lx + 2.0 * ly + 4.0 * arc);
    int segment = 0;
    for (; segment < 7 && s > lengths[segment]; segment++) s -= lengths[segment];
    int side = segment / 2;
    if (segment % 2 == 1) {
        float angle = (float(side) - 1.0) * M_PI_F * 0.5 + s / max(radius, 1e-3);
        normal = float2(cos(angle), sin(angle));
        point = corners[side] * (extent - radius) + normal * radius;
    } else {
        float2 directions[4] = { float2(1, 0), float2(0, 1), float2(-1, 0), float2(0, -1) };
        float2 starts[4] = { float2(-1, -1), float2(1, -1), float2(1, 1), float2(-1, 1) };
        normal = float2(directions[side].y, -directions[side].x);
        point = starts[side] * (extent - radius) + normal * radius + directions[side] * s;
    }
}

float coverage(float distance) {
    float aa = max(fwidth(distance), 1e-3);
    return 1.0 - smoothstep(-aa, aa, distance);
}

float roundedBox(float2 p, float2 extent, float radius) {
    float2 q = abs(p) - extent + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

}

struct HallPhoneOut {
    float4 position [[ position ]];
    float2 uv;
};

[[ vertex ]] HallPhoneOut hallPhoneVertex(uint vid [[ vertex_id ]],
                                          constant hall::PhoneArgs &phone [[ buffer(2) ]],
                                          constant float4 &viewport [[ buffer(3) ]]) {
    float2 corner = float2(vid & 1, (vid >> 1) & 1);
    float2 delta = (corner - 0.5) * phone.face.xy;
    HallPhoneOut out;
    out.position = phone::project(phone::place(delta, phone.view.w * 0.5, phone), phone, viewport);
    out.uv = corner;
    return out;
}

namespace phone {

float3 titanium(float3 screenLight, float3 base) {
    float3 light = mix(float3(dot(screenLight, hall::luma)), screenLight, 0.5);
    return base * light * 1.3;
}

float disc(float2 q, float2 center, float radius) {
    return coverage(length(q - center) - radius);
}

}

[[ fragment ]] float4 hallPhoneFragment(HallPhoneOut in [[ stage_in ]],
                                        constant hall::HallArgs &args [[ buffer(0) ]],
                                        constant hall::PhoneArgs &phone [[ buffer(2) ]],
                                        texture2d<float> lens [[ texture(0) ]],
                                        texture2d<float> chrome [[ texture(1) ]],
                                        texture2d<float> turnedChrome [[ texture(2) ]]) {
    float2 size = phone.face.xy;
    float2 delta = (in.uv - 0.5) * size;
    float2 q = phone::toPortrait(delta, phone);
    float2 extent = phone::portraitExtent(phone);
    float u = extent.x * 2.0;
    float radius = phone::cornerRadius(extent);
    float bezel = 0.039 * u;
    float body = phone::roundedBox(q, extent, radius);
    float screen = phone::roundedBox(q, extent - bezel, radius - bezel);

    float2 screenHalf = extent - bezel;
    float w = screenHalf.x * 2.0;
    float top = -screenHalf.y, bottom = screenHalf.y;
    bool wide = phone.chrome.z > 1.5;
    float finderTop = top + (wide ? 0.14 : 0.30) * w;
    float2 finder = float2(screenHalf.x, min(screenHalf.x * phone.chrome.z, screenHalf.y));
    float2 finderCenter = float2(0.0, min(finderTop + finder.y, bottom - finder.y));

    float2 lensDelta = delta - phone::fromPortrait(finderCenter, phone);
    float3 ray = float3(phone.lens.x + lensDelta.x * phone.lens.z, phone.lens.y - lensDelta.y * phone.lens.z, -1.0);
    float3 d = phone.cameraRight.xyz * ray.x + phone.cameraUp.xyz * ray.y + phone.cameraBack.xyz * ray.z;
    float depth = max(-d.z, 1e-4);
    float2 hallPoint = float2(args.camera.z + args.camera.x * d.x / depth, args.camera.y - args.camera.x * d.y / depth);
    float2 lensSize = float2(lens.get_width(), lens.get_height());
    float2 lensUV = (phone.view.xy + phone.view.z * hallPoint) / lensSize;
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    float3 color = lens.sample(linear, lensUV).rgb;

    float2 inner = q - finderCenter;
    float inFinder = phone::coverage(phone::roundedBox(inner, finder, 0.0));
    color *= mix(wide ? 0.18 : 0.38, 1.0, inFinder);

    float2 cell = finder * 2.0 / 3.0;
    float2 toLine = abs(fmod(inner + finder + cell * 0.5, cell) - cell * 0.5);
    float gridInside = phone::coverage(phone::roundedBox(inner, finder - 0.01 * u, 0.0));
    float gridLine = phone::coverage(min(toLine.x, toLine.y) - 0.0025 * u) * gridInside * phone.chrome.y;
    color = mix(color, float3(1.0), gridLine * 0.35);

    float2 thumb = float2(-0.352 * w, bottom - 0.148 * w);
    color = mix(color, float3(0.0), phone::disc(q, thumb, 0.061 * w));

    constexpr sampler overlaySampler(filter::linear, mip_filter::linear, address::clamp_to_zero);
    float2 overlayUV = (q + screenHalf) / (2.0 * screenHalf);
    float4 overlay = mix(turnedChrome.sample(overlaySampler, overlayUV), chrome.sample(overlaySampler, overlayUV),
                         phone.stage.w);
    color = color * (1.0 - overlay.a) + overlay.rgb;
    color *= phone.color.w;

    float island = phone::coverage(phone::roundedBox(q - float2(0.0, -extent.y + bezel + 0.075 * u),
                                                     float2(0.16, 0.047) * u, 0.047 * u));
    color = mix(color, float3(0.0), island);
    float2 islandCamera = float2(0.105 * u, -extent.y + bezel + 0.075 * u);
    color = mix(color, float3(0.05, 0.06, 0.13), phone::disc(q, islandCamera, 0.017 * u) * 0.9);

    float3 glass = float3(0.0);
    float rimWidth = 0.014 * u;
    float rim = 1.0 - phone::coverage(body + rimWidth);
    float3 rimColor = phone::titanium(args.mean.xyz, phone.color.rgb);
    glass = mix(glass, rimColor, rim);
    color = mix(glass, color, phone::coverage(screen));

    float alpha = phone::coverage(body) * phone.center.w;
    return float4(color * alpha, alpha);
}

struct HallPhoneMetalOut {
    float4 position [[ position ]];
};

[[ vertex ]] HallPhoneMetalOut hallPhoneSideVertex(uint vid [[ vertex_id ]],
                                                  constant hall::PhoneArgs &phone [[ buffer(2) ]],
                                                  constant float4 &viewport [[ buffer(3) ]]) {
    float2 extent = phone::portraitExtent(phone);
    float radius = phone::cornerRadius(extent);
    float t = float(vid / 2) / float(phone::perimeterSegments);
    float across = (vid & 1) ? -1.0 : 1.0;
    float2 q, qNormal;
    phone::perimeter(t, extent, radius, q, qNormal);
    float3 p = phone::place(phone::fromPortrait(q, phone), phone.view.w * 0.5 * across, phone);
    HallPhoneMetalOut out;
    out.position = phone::project(p, phone, viewport);
    return out;
}

namespace phone {

constant float4 buttons[4] = {
    float4(-1.0, -0.61, -0.525, 0.0),
    float4(-1.0, -0.427, -0.308, 0.0),
    float4(-1.0, -0.26, -0.113, 0.0),
    float4(1.0, -0.35, -0.113, 0.0),
};

}

[[ fragment ]] float4 hallPhoneMetalFragment(HallPhoneMetalOut in [[ stage_in ]],
                                             constant hall::HallArgs &args [[ buffer(0) ]],
                                             constant hall::PhoneArgs &phone [[ buffer(2) ]]) {
    float3 color = phone::titanium(args.mean.xyz, phone.color.rgb);
    return float4(color * phone.center.w, phone.center.w);
}


constant int buttonSegments = 24;

static HallPhoneMetalOut phoneButtonPoint(float2 profile, float lift, uint button,
                                          constant hall::PhoneArgs &phone, float4 viewport) {
    float2 extent = phone::portraitExtent(phone);
    float4 b = phone::buttons[button];
    float metersPerPixel = phone.center.z / phone.stage.z;
    float along = (b.y + b.z) * 0.5 * extent.y + profile.y;
    float2 q = float2(b.x * (extent.x + lift), along);
    float2 delta = phone::fromPortrait(q, phone);
    float3 p = phone::place(delta, profile.x * metersPerPixel, phone);
    HallPhoneMetalOut out;
    out.position = phone::project(p, phone, viewport);
    return out;
}

static float2 phoneButtonExtent(uint button, constant hall::PhoneArgs &phone) {
    float2 extent = phone::portraitExtent(phone);
    float4 b = phone::buttons[button];
    float halfThickness = phone.view.w * 0.5 * phone.stage.z / phone.center.z;
    return float2(0.3 * halfThickness, (b.z - b.y) * 0.5 * extent.y);
}

[[ vertex ]] HallPhoneMetalOut hallPhoneButtonRimVertex(uint vid [[ vertex_id ]],
                                                         uint iid [[ instance_id ]],
                                                         constant hall::PhoneArgs &phone [[ buffer(2) ]],
                                                         constant float4 &viewport [[ buffer(3) ]]) {
    float2 size = phoneButtonExtent(iid, phone);
    float2 profile, normal;
    phone::perimeter(float(vid / 2) / float(buttonSegments), size, size.x, profile, normal);
    float u = phone::portraitExtent(phone).x * 2.0;
    float lift = (vid & 1) ? 0.009 * u : -0.004 * u;
    return phoneButtonPoint(profile, lift, iid, phone, viewport);
}

[[ vertex ]] HallPhoneMetalOut hallPhoneButtonCapVertex(uint vid [[ vertex_id ]],
                                                         uint iid [[ instance_id ]],
                                                         constant hall::PhoneArgs &phone [[ buffer(2) ]],
                                                         constant float4 &viewport [[ buffer(3) ]]) {
    float2 size = phoneButtonExtent(iid, phone);
    uint corner = vid % 3;
    float t = float(vid / 3 + (corner == 2 ? 1 : 0)) / float(buttonSegments);
    float2 profile = float2(0.0), normal = float2(0.0);
    if (corner != 0) phone::perimeter(t, size, size.x, profile, normal);
    float u = phone::portraitExtent(phone).x * 2.0;
    return phoneButtonPoint(profile, 0.009 * u, iid, phone, viewport);
}


namespace glow {

float cumulative(float x) {
    x = clamp(x, -4.0, 4.0);
    return 0.5 + 0.5 * tanh(0.7978845 * (x + 0.044715 * x * x * x));
}

float covered(float2 p, float2 low, float2 high, float sigma) {
    float2 a = (low - p) / sigma, b = (high - p) / sigma;
    return (cumulative(b.x) - cumulative(a.x)) * (cumulative(b.y) - cumulative(a.y));
}

}

// MARK: Glow

struct HallGlowOut {
    float4 position [[ position ]];
    float2 delta;
};

[[ vertex ]] HallGlowOut hallPhoneGlowVertex(uint vid [[ vertex_id ]],
                                             constant hall::PhoneArgs &phone [[ buffer(2) ]],
                                             constant float4 &viewport [[ buffer(3) ]]) {
    float2 corner = float2(vid & 1, (vid >> 1) & 1);
    float margin = 0.6 * min(phone.face.x, phone.face.y);
    float2 delta = (corner - 0.5) * (phone.face.xy + 2.0 * margin);
    HallGlowOut out;
    out.position = phone::project(phone::place(delta, phone.view.w * 0.5, phone), phone, viewport);
    out.delta = delta;
    return out;
}

[[ fragment ]] float4 hallPhoneGlowFragment(HallGlowOut in [[ stage_in ]],
                                            constant hall::PhoneArgs &phone [[ buffer(2) ]]) {
    float2 q = phone::toPortrait(in.delta, phone);
    float2 extent = phone::portraitExtent(phone);
    float u = extent.x * 2.0;
    float bezel = 0.039 * u;
    float edge = phone::roundedBox(q, extent - bezel, phone::cornerRadius(extent) - bezel);
    float spread = glow::cumulative(-edge / (0.04 * u));
    float halo = glow::cumulative(-edge / (0.22 * u));
    float haze = smoothstep(0.0, max(fwidth(edge), 1e-3), edge);
    float glow = (0.5 * spread + 0.25 * halo) * haze;
    return float4(phone.glow.rgb * phone.glow.w * glow, 0.0);
}

struct HallScreenGlowOut {
    float4 position [[ position ]];
};

[[ vertex ]] HallScreenGlowOut hallScreenGlowVertex(uint vid [[ vertex_id ]]) {
    float2 corner = float2(vid & 1, (vid >> 1) & 1);
    HallScreenGlowOut out;
    out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

[[ fragment ]] float4 hallScreenGlowFragment(HallScreenGlowOut in [[ stage_in ]],
                                             constant hall::HallArgs &args [[ buffer(0) ]],
                                             texture2d<float> picture [[ texture(0) ]]) {
    float2 low = float2(args.frame.z, args.frame.x), high = float2(args.frame.w, args.frame.y);
    float2 p = in.position.xy;
    float2 box = max(high - low, float2(1.0));
    float ratio = args.picture.y > 0.5 ? args.picture.x / (box.x / box.y) : 0.0;
    float2 shown = ratio > 1.0 ? float2(box.x, box.y / ratio) : ratio > 0.0 ? float2(box.x * ratio, box.y) : box;
    low = (low + high - shown) * 0.5;
    high = low + shown;
    float2 size = shown;
    float spread = glow::covered(p, low, high, 0.025 * size.x);
    float halo = glow::covered(p, low, high, 0.12 * size.x);
    if (0.6 * spread + 0.4 * halo < 1e-4) return float4(0.0);
    float2 uv = (clamp(p, low + 0.15 * size, high - 0.15 * size) - low) / size;
    constexpr sampler soft(filter::linear, mip_filter::linear, address::clamp_to_edge);
    float3 near = args.picture.y > 0.5 ? picture.sample(soft, uv, level(7.0)).rgb : args.mean.xyz;
    float3 whole = args.picture.y > 0.5 ? picture.sample(soft, float2(0.5), level(12.0)).rgb : args.mean.xyz;

    float2 apart = max(low - p, p - high);
    float haze = smoothstep(0.0, 1.5, max(apart.x, apart.y));
    return float4((0.6 * spread * near + 0.4 * halo * whole) * haze * args.glow.x, 0.0);
}

[[ fragment ]] float4 hallVeilFragment(HallScreenGlowOut in [[ stage_in ]],
                                       constant hall::HallArgs &args [[ buffer(0) ]]) {
    return float4(0.0, 0.0, 0.0, args.glow.y);
}

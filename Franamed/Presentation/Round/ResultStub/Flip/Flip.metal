//
//  Flip.metal
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.09.2026.
//

#include <metal_stdlib>
using namespace metal;

struct FlipUniforms {
    float4x4 projection;
    float4   lightDir;
    float4   hallTint;
    float4   hallShape;

    float width;
    float height;
    float angle;
    float bend;

    float perspective;
    float sheen;
    float cols;
    float rows;

    float viewWidth;
    float viewHeight;
    float thickness;
    float gap;

    float face;
    float faceOffset;
    float edgeCount;
    float gloss;

    float4 tearLine;
    float4 tearShape;
    float4 tearState;
    float4 tearHeal;
};

constant float3 toScreen = float3(0.0, -0.866, -0.5);
constant float screenReach = 0.9;
constant float screenWrap = 2.0;

struct FlipVertex {
    float4 position [[position]];
    float2 uv;
    float3 normal;
    float2 paper;
};

struct Placed {
    float3 p;
    float3 xAxis;
};

static float tearHash(float n) {
    return fract(sin(n) * 43758.5453);
}

static float tearNoise(float x, float seed) {
    float i = floor(x);
    float f = fract(x);
    float k = f * f * (3.0 - 2.0 * f);
    return mix(tearHash(i + seed * 17.13), tearHash(i + 1.0 + seed * 17.13), k) * 2.0 - 1.0;
}

static bool isTorn(constant FlipUniforms &u) {
    return u.tearState.w != 0.0 && u.tearState.x > 0.0;
}

static float tearTipY(constant FlipUniforms &u) {
    return (u.tearState.x - 0.5) * u.height;
}

static float tearX(constant FlipUniforms &u, float y) {
    float t = y / u.height + 0.5;
    float seed = u.tearShape.z;
    return mix(u.tearLine.x, u.tearLine.y, t)
        + u.tearShape.x * sin(6.2832 * 0.7 * t + u.tearLine.z)
        + u.tearShape.y * sin(6.2832 * 2.1 * t + u.tearLine.w)
        + 1.3 * tearNoise(y / 3.2, seed)
        + 0.5 * tearNoise(y / 1.1, seed + 3.0);
}

static float tearFuzz(constant FlipUniforms &u, float y, float side) {
    float grown = smoothstep(0.0, 6.0, tearTipY(u) - y);
    float fibre = max(0.0, tearNoise(y / 0.45, u.tearShape.z + (side > 0.0 ? 7.0 : 13.0)));
    return 0.9 * fibre * fibre * grown;
}

static float3 tearOffset(constant FlipUniforms &u, float x, float y, float side) {
    if (side == 0.0 || u.tearState.x <= 0.0) return float3(0.0);
    float tip = tearTipY(u);
    float apart = smoothstep(1.0, 1.08, u.tearState.x);
    float2 slide = float2(side * u.tearState.z * apart, 0.0);
    if (y >= tip) return float3(slide, 0.0);
    float span = max(tip + u.height * 0.5, 1.0);
    float a = clamp((tip - y) / span, 0.0, 1.0) * (1.0 - apart);
    float phi = side * u.tearState.y * a;
    float2 pivot = float2(tearX(u, tip), tip);
    float2 d = float2(x, y) - pivot;
    float c = cos(phi);
    float s = sin(phi);
    float2 moved = pivot + float2(d.x * c - d.y * s, d.x * s + d.y * c) + slide;
    return float3(moved - float2(x, y), -side * u.tearState.y * 70.0 * a * a);
}

static bool tearKeeps(constant FlipUniforms &u, float2 p) {
    if (!isTorn(u)) return true;
    float side = u.tearState.w;
    float line = tearX(u, p.y);
    float fuzz = p.y < tearTipY(u) ? tearFuzz(u, p.y, side) : 0.0;
    return side < 0.0 ? p.x < line + fuzz : p.x >= line - fuzz;
}

static half3 tearBand(constant FlipUniforms &u, float2 p, bool isBack, half3 base) {
    float tip = tearTipY(u);
    if (!isTorn(u) || p.y >= tip) return base;
    float side = u.tearState.w;
    float inward = side < 0.0 ? tearX(u, p.y) - p.x : p.x - tearX(u, p.y);
    bool wide = (side * u.tearShape.w > 0.0) != isBack;
    float grown = smoothstep(0.0, 10.0, tip - p.y);
    float width = (wide ? 1.9 : 0.45) * (0.7 + 0.3 * tearNoise(p.y / 2.4, u.tearShape.z + 21.0)) * grown;
    float band = 1.0 - smoothstep(width * 0.55, width + 0.35, inward);
    float streak = 0.9 + 0.1 * tearNoise(p.y / 0.3, u.tearShape.z + 5.0);
    return mix(base, half3(0.97h, 0.96h, 0.93h) * half(streak), half(band));
}

static half3 tearScar(constant FlipUniforms &u, float2 p, half3 base) {
    if (u.tearHeal.z <= 0.0) return base;
    float tip = u.tearState.x > 0.0 ? tearTipY(u) : -u.height * 0.5;
    float end = (u.tearHeal.z - 0.5) * u.height;
    float along = smoothstep(tip - 1.0, tip + 3.0, p.y) * (1.0 - smoothstep(end - 10.0, end, p.y));
    if (along <= 0.0) return base;
    float across = p.x - tearX(u, p.y);
    float broken = 0.65 + 0.35 * tearNoise(p.y / 2.0, u.tearShape.z + 31.0);
    float crease = exp(-across * across / 0.5) * along * broken;
    float lift = exp(-(across - 0.9) * (across - 0.9) / 0.4) * along * broken;
    half3 scarred = mix(base, base * 0.8h, half(crease * 0.55));
    return mix(scarred, half3(0.98h, 0.97h, 0.94h), half(lift * 0.35));
}

static half3 tearHealGlow(constant FlipUniforms &u, float2 p, half3 lit) {
    float strength = u.tearHeal.x;
    if (strength <= 0.001) return lit;
    float tip = tearTipY(u);
    float reach = (u.tearHeal.y - 0.5) * u.height;
    float along = p.y - tip;
    float head = exp(-along * along / 20.0);
    float trail = step(0.0, along) * exp(-along / 26.0) * (1.0 - smoothstep(reach - 6.0, reach + 2.0, p.y));
    float body = max(head, trail * 0.55) * strength;
    float across = abs(p.x - tearX(u, p.y));
    float core = exp(-across * across / 2.0) * body;
    float halo = exp(-across * across / 60.0) * body;
    float glow = exp(-across * across / 220.0) * body;
    lit = mix(lit, half3(1.0h, 0.97h, 0.88h), half(glow * 0.6));
    return mix(lit, half3(1.0h, 1.0h, 0.98h), half(min(halo * 0.7 + core * 1.3, 1.0)));
}

static Placed placePaper(constant FlipUniforms &u, float x, float y, float w) {
    float halfWidth = max(u.width * 0.5, 0.001);
    float t = x / halfWidth;

    float curl = abs(u.bend) * halfWidth;
    float across = w + curl * t * t;
    float dAcross = curl * 2.0 * t / halfWidth;

    float c = cos(u.angle);
    float s = sin(u.angle);

    Placed out;
    out.p = float3(x * c + across * s, y, -x * s + across * c);
    out.xAxis = float3(c + dAcross * s, 0.0, -s + dAcross * c);
    return out;
}

static float4 projectPaper(constant FlipUniforms &u, float3 p) {
    float scale = u.perspective / max(u.perspective - p.z, 1.0);
    float2 screen = float2(u.viewWidth * 0.5 + p.x * scale,
                           u.viewHeight * 0.5 + p.y * scale);
    float4 clip = u.projection * float4(screen, 0.0, 1.0);
    clip.z = clamp(0.5 - p.z / 600.0, 0.0, 1.0);
    return clip;
}

vertex FlipVertex ticketFlipVertex(uint vid [[vertex_id]],
                                   constant FlipUniforms &u [[buffer(1)]]) {
    uint columns = uint(u.cols);
    uint col = vid % (columns + 1);
    uint row = vid / (columns + 1);

    float fx = float(col) / u.cols;
    float fy = float(row) / u.rows;

    float x = (fx - 0.5) * u.width;
    float y = (fy - 0.5) * u.height;
    float3 torn = tearOffset(u, x, y, u.tearState.w);

    Placed placed = placePaper(u, x + torn.x, y + torn.y, u.faceOffset * u.gap + torn.z);

    FlipVertex out;
    out.position = projectPaper(u, placed.p);
    out.uv = float2(fx, fy);
    out.paper = float2(x, y);
    out.normal = normalize(cross(placed.xAxis, float3(0.0, 1.0, 0.0))) * u.faceOffset;
    return out;
}

vertex FlipVertex ticketFlipEdgeVertex(uint vid [[vertex_id]],
                                       constant float4 *outline [[buffer(0)]],
                                       constant FlipUniforms &u [[buffer(1)]]) {
    float4 point = outline[(vid / 2) % max(uint(u.edgeCount), 1u)];
    float side = (vid & 1u) == 0u ? 1.0 : -1.0;
    float x = point.x;
    float y = point.y;
    float3 torn = tearOffset(u, x, y, u.tearState.w);

    Placed placed = placePaper(u, x + torn.x, y + torn.y, side * u.thickness * 0.5 + torn.z);

    FlipVertex out;
    out.position = projectPaper(u, placed.p);
    out.uv = float2(0.0, 0.0);
    out.paper = float2(x, y);
    out.normal = normalize(normalize(placed.xAxis) * point.z + float3(0.0, 1.0, 0.0) * point.w);
    return out;
}

vertex FlipVertex ticketFlipTearVertex(uint vid [[vertex_id]],
                                       constant FlipUniforms &u [[buffer(1)]]) {
    float k = float(vid / 2u) / max(u.edgeCount, 1.0);
    float side = (vid & 1u) == 0u ? 1.0 : -1.0;
    float half_ = u.tearState.w;
    float y = mix(-u.height * 0.5, min(tearTipY(u), u.height * 0.5), k);
    float x = tearX(u, y) + half_ * 0.1;
    float slope = tearX(u, y + 0.5) - tearX(u, y - 0.5);
    float3 torn = tearOffset(u, x, y, half_);

    Placed placed = placePaper(u, x + torn.x, y + torn.y, side * u.thickness * 0.5 + torn.z);
    float2 outward = normalize(float2(-half_, half_ * slope));

    FlipVertex out;
    out.position = projectPaper(u, placed.p);
    out.uv = float2(-1.0, 0.0);
    out.normal = normalize(normalize(placed.xAxis) * outward.x + float3(0.0, 1.0, 0.0) * outward.y);
    out.paper = float2(x, y);
    return out;
}

fragment half4 ticketFlipFragment(FlipVertex in [[stage_in]],
                                  texture2d<half> frontTexture [[texture(0)]],
                                  texture2d<half> backTexture  [[texture(1)]],
                                  sampler textureSampler [[sampler(0)]],
                                  constant FlipUniforms &u [[buffer(1)]]) {
    bool isEdge = u.face < 0.5;
    bool isBack = u.face > 1.5;

    half3 base = half3(0.9h * 0.88h);
    half alpha = 1.0h;

    if (isEdge && in.uv.x < -0.5) {
        float2 paperUV = in.paper / float2(u.width, u.height) + 0.5;
        if (frontTexture.sample(textureSampler, paperUV).a < 0.5h) { discard_fragment(); }
        base = half3(0.95h, 0.94h, 0.9h) * half(0.92 + 0.08 * tearNoise(in.paper.y / 0.4, u.tearShape.z + 9.0));
    } else if (!tearKeeps(u, in.paper)) {
        discard_fragment();
    }

    if (!isEdge) {
        float2 uv = in.uv;
        if (isBack) { uv.x = 1.0 - uv.x; }

        half4 tex = isBack ? backTexture.sample(textureSampler, uv)
                           : frontTexture.sample(textureSampler, uv);
        if (tex.a <= 0.004h) { discard_fragment(); }

        alpha = tex.a;
        base = half3(tex.rgb / max(tex.a, 0.002h));
        base = tearBand(u, in.paper, isBack, base);
        base = tearScar(u, in.paper, base);
    }

    float tiltCos = cos(u.hallShape.x);
    float tiltSin = sin(u.hallShape.x);
    float3 n = normalize(in.normal);
    float3 N = float3(n.x, n.y * tiltCos - n.z * tiltSin, n.y * tiltSin + n.z * tiltCos);
    float3 L = normalize(u.lightDir.xyz);
    float3 H = normalize(L + float3(0.0, 0.0, 1.0));

    float lambertFlat = 0.58 + 0.42 * clamp(L.z, 0.0, 1.0);
    float lambert = (0.58 + 0.42 * clamp(dot(N, L), 0.0, 1.0)) / max(lambertFlat, 0.001);

    float specFlat = pow(clamp(H.z, 0.0, 1.0), u.gloss) * u.sheen;
    float spec = max(pow(clamp(dot(N, H), 0.0, 1.0), u.gloss) * u.sheen - specFlat, 0.0);

    float3 tint = u.hallTint.rgb;
    float amount = u.hallTint.w;
    float3 bounce = mix(float3(1.0), tint, amount) * u.hallShape.y;
    float direct = clamp((dot(N, toScreen) + screenWrap) / (1.0 + screenWrap), 0.0, 1.0) * screenReach * amount;
    float3 light = (bounce * lambert + tint * direct) / (1.0 + screenReach * amount);
    float3 sheenColor = mix(float3(1.0), tint, amount);

    half3 lit = base * half3(light) + half3(sheenColor * spec * u.hallShape.w);
    lit = tearHealGlow(u, in.paper, lit);
    return half4(lit, alpha);
}

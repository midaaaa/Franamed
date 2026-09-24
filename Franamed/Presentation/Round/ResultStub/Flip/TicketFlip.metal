//
//  TicketFlip.metal
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.09.2026.
//

#include <metal_stdlib>
using namespace metal;

struct FlipUniforms {
    float4x4 projection;
    float4   lightDir;

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
};

struct FlipVertex {
    float4 position [[position]];
    float2 uv;
    float3 normal;
};

struct Placed {
    float3 p;
    float3 xAxis;
};

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

    Placed placed = placePaper(u, x, y, u.faceOffset * u.gap);

    FlipVertex out;
    out.position = projectPaper(u, placed.p);
    out.uv = float2(fx, fy);
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

    Placed placed = placePaper(u, x, y, side * u.thickness * 0.5);

    FlipVertex out;
    out.position = projectPaper(u, placed.p);
    out.uv = float2(0.0, 0.0);
    out.normal = normalize(normalize(placed.xAxis) * point.z + float3(0.0, 1.0, 0.0) * point.w);
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

    if (!isEdge) {
        float2 uv = in.uv;
        if (isBack) { uv.x = 1.0 - uv.x; }

        half4 tex = isBack ? backTexture.sample(textureSampler, uv)
                           : frontTexture.sample(textureSampler, uv);
        if (tex.a <= 0.004h) { discard_fragment(); }

        alpha = tex.a;
        base = half3(tex.rgb / max(tex.a, 0.002h));
    }

    float3 N = normalize(in.normal);
    float3 L = normalize(u.lightDir.xyz);
    float3 H = normalize(L + float3(0.0, 0.0, 1.0));

    float lambertFlat = 0.58 + 0.42 * clamp(L.z, 0.0, 1.0);
    float lambert = (0.58 + 0.42 * clamp(dot(N, L), 0.0, 1.0)) / max(lambertFlat, 0.001);

    float specFlat = pow(clamp(H.z, 0.0, 1.0), u.gloss) * u.sheen;
    float spec = max(pow(clamp(dot(N, H), 0.0, 1.0), u.gloss) * u.sheen - specFlat, 0.0);

    return half4(base * half(lambert) + half3(half(spec)), alpha);
}

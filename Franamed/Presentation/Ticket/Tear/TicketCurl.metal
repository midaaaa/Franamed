//
//  TicketCurl.metal
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.08.2026.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Perforation pattern

inline float hashCell(float n) {
    uint h = uint(max(n, 0.0));
    h ^= h >> 16;
    h *= 0x7feb352du;
    h ^= h >> 15;
    h *= 0x846ca68bu;
    h ^= h >> 16;
    return float(h >> 8) * (1.0 / 16777216.0);
}

inline float vnoise(float x) {
    float i = floor(x);
    float f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(hashCell(i), hashCell(i + 1.0), f) * 2.0 - 1.0;
}

inline float tearJitter(float a, float amp) {
    return amp * (0.55 * vnoise(a * 0.11)
                + 0.30 * vnoise(a * 0.37)
                + 0.15 * vnoise(a * 1.30));
}

inline float roundedSlotSD(float2 p, float2 halfExtent, float radius) {
    float rr = min(radius, min(halfExtent.x, halfExtent.y));
    float2 d = abs(p) - max(halfExtent - rr, 0.0);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - rr;
}

inline float perfSD(float a, float b, float pitch, float holeLen, float hw,
                    float strainCell, float strainAmt, float patternSign,
                    float neckFrac, float crackW, float corner) {
    float tabLen = max(pitch - holeLen, 0.01);
    float cell = floor(a / pitch);
    float sd = 1e9;

    for (int k = -1; k <= 1; ++k) {
        float ci = cell + float(k);
        float s = abs(ci - strainCell) < 0.5 ? strainAmt : 0.0;

        float amount = neckFrac * (0.94 + 0.12 * hashCell(ci + 4096.0));
        float neck = min(s * amount, 0.95) * tabLen;

        float c0 = ci * pitch + 0.5 * holeLen;
        sd = min(sd, roundedSlotSD(float2(a - c0, b), float2(0.5 * holeLen, hw), hw * corner));

        if (neck > 0.03) {
            float cw = max(hw * crackW, 0.15);
            float c1 = patternSign >= 0.0 ? ci * pitch + holeLen + 0.5 * neck
                                          : (ci + 1.0) * pitch - 0.5 * neck;
            sd = min(sd, roundedSlotSD(float2(a - c1, b), float2(0.5 * neck, cw), cw * corner));
        }
    }
    return sd;
}

// MARK: - Curl geometry

inline float3 coneRuling(float beta, float theta) {
    float st = sin(theta), ct = cos(theta);
    return float3(ct * ct + st * st * cos(beta),
                  st * sin(beta),
                  st * ct * (1.0 - cos(beta)));
}

inline float curlDepth(float height, float heightScale, float thickness) {
    float t = clamp((height + thickness) / (heightScale + 2.0 * thickness), 0.0, 1.0);
    return 0.999 - 0.99 * t;
}

// MARK: - Pipeline

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float2 uv;
    float2 paperAB;
    float  skin [[flat]];
};

struct EdgeOut {
    float4 position [[position]];
    float3 normal;
    float2 paperAB;
};

struct CurlUniforms {
    float4x4 projection;
    float4   lightDir;

    float perfOriginX;
    float perfOriginY;
    float perfDirX;
    float perfDirY;

    float stubNX;
    float stubNY;
    float offsetX;
    float offsetY;

    float ticketWidth;
    float ticketHeight;
    float apexA;
    float theta;

    float perfLength;
    float stubExtent;
    float canvasPadding;
    float colsA;

    float colsB;
    float opacity;
    float thickness;
    float _reserved;

    float front;
    float pitch;
    float holeLen;
    float holeHalfWidth;

    float jitterAmp;
    float strainCell;
    float strain;
    float neckFraction;

    float sheen;
    float patternOrigin;
    float patternSign;
    float patternInset;

    float crackWidth;
    float tornSoftness;
    float slotCorner;
    float tornGap;

    float4 paperBack;
};

struct CurlPoint {
    float2 flat;
    float3 position;
    float3 normal;
    float  radius;
};

inline CurlPoint curlPoint(float a, float b, constant CurlUniforms &u) {
    float2 perfOrigin = float2(u.perfOriginX, u.perfOriginY);
    float2 perfDir = float2(u.perfDirX, u.perfDirY);
    float2 stubN = float2(u.stubNX, u.stubNY);
    float2 canvasOffset = float2(u.canvasPadding, u.canvasPadding) + float2(u.offsetX, u.offsetY);

    CurlPoint p;
    p.flat = perfOrigin + perfDir * a + stubN * b;

    float theta = clamp(u.theta, 0.05, M_PI_F / 2.0);
    float da = a - u.apexA;
    p.radius = length(float2(da, b));

    if (p.radius < 0.0001) {
        p.position = float3(p.flat + canvasOffset, 0.0);
        p.normal = float3(0.0, 0.0, 1.0);
        return p;
    }

    float sinT = sin(theta);
    float beta = atan2(b, da) / sinT;
    float3 ruling = coneRuling(beta, theta);
    float3 dRulingDPhi = float3(-sin(beta) * sinT, cos(beta), sin(beta) * cos(theta));
    float3 nrm = normalize(cross(ruling, dRulingDPhi));

    float2 apex = perfOrigin + perfDir * u.apexA;
    float2 placed = apex + perfDir * (p.radius * ruling.x) + stubN * (p.radius * ruling.y);
    p.position = float3(placed + canvasOffset, p.radius * ruling.z);
    p.normal = float3(perfDir.x * nrm.x + stubN.x * nrm.y,
                      perfDir.y * nrm.x + stubN.y * nrm.y,
                      nrm.z);
    return p;
}

inline float3 skinPosition(CurlPoint p, float side, constant CurlUniforms &u) {
    float taper = smoothstep(0.0, max(6.0 * u.thickness, 0.001), p.radius);
    return p.position + p.normal * (side * 0.5 * u.thickness * taper);
}

inline float4 clipPosition(float3 p, constant CurlUniforms &u) {
    float heightScale = max(length(float2(u.perfLength, u.stubExtent)), 1.0);
    return u.projection * float4(p.xy, curlDepth(p.z, heightScale, u.thickness), 1.0);
}

inline float paperA(float aFixed, constant CurlUniforms &u) {
    return (aFixed - u.patternOrigin) * u.patternSign;
}

inline half3 shade(half3 base, float3 normal, float tint, constant CurlUniforms &u) {
    float3 N = normalize(normal);
    float3 L = normalize(u.lightDir.xyz);
    float3 H = normalize(L + float3(0.0, 0.0, 1.0));

    float lambertFlat = 0.58 + 0.42 * clamp(L.z, 0.0, 1.0);
    float lambert = (0.58 + 0.42 * clamp(dot(N, L), 0.0, 1.0)) / max(lambertFlat, 0.001);

    float specFlat = pow(clamp(H.z, 0.0, 1.0), 26.0) * u.sheen;
    float spec = max(pow(clamp(dot(N, H), 0.0, 1.0), 26.0) * u.sheen - specFlat, 0.0);

    return base * half(lambert * tint) + half3(half(spec * tint));
}

vertex VertexOut ticketCurlVertex(uint vid [[vertex_id]],
                                  constant CurlUniforms &u [[buffer(1)]],
                                  constant float &skin [[buffer(2)]]) {
    uint colsAi = uint(u.colsA);
    uint colsBi = uint(u.colsB);
    uint rowStride = colsAi + 1;
    uint i = vid % rowStride;
    uint j = vid / rowStride;

    float a = u.perfLength * float(i) / float(colsAi);
    if (u.apexA > 0.0 && u.apexA < u.perfLength && colsAi >= 2) {
        float snapF = clamp(round(u.apexA / u.perfLength * float(colsAi)),
                            1.0, float(colsAi - 1));
        if (i == uint(snapF)) { a = u.apexA; }
    }
    float b = u.stubExtent * float(j) / float(colsBi);

    CurlPoint p = curlPoint(a, b, u);

    VertexOut out;
    out.position = clipPosition(skinPosition(p, skin, u), u);
    out.normal = p.normal * skin;
    out.uv = float2(p.flat.x / u.ticketWidth, p.flat.y / u.ticketHeight);
    out.paperAB = float2(u.patternOrigin + u.patternSign * a, b);
    out.skin = skin;
    return out;
}

vertex EdgeOut ticketCurlEdgeVertex(uint vid [[vertex_id]],
                                    constant float4 *outline [[buffer(0)]],
                                    constant CurlUniforms &u [[buffer(1)]],
                                    constant float &edgeCount [[buffer(2)]]) {
    float4 point = outline[(vid / 2) % max(uint(edgeCount), 1u)];
    float side = (vid & 1u) == 0u ? 1.0 : -1.0;

    float a = paperA(point.x, u);
    float b = max(point.y, 0.0);
    float2 inward = -float2(point.z * u.patternSign, point.w) * 0.5;

    CurlPoint p = curlPoint(a, b, u);
    CurlPoint q = curlPoint(a + inward.x, max(b + inward.y, 0.0), u);

    EdgeOut out;
    out.position = clipPosition(skinPosition(p, side, u), u);
    out.normal = p.position - q.position;
    out.paperAB = float2(point.x, b);
    return out;
}

fragment half4 ticketCurlEdgeFragment(EdgeOut in [[stage_in]],
                                      constant CurlUniforms &u [[buffer(1)]]) {
    float a = paperA(in.paperAB.x, u);
    if (in.paperAB.y < 3.0 && a > u.front) { discard_fragment(); }

    half3 lit = shade(half3(u.paperBack.rgb) * 0.88h, in.normal, 1.0, u);
    half outA = half(u.opacity);
    return half4(lit * outA, outA);
}

fragment half4 ticketCurlFragment(VertexOut in [[stage_in]],
                                  texture2d<half> ticketTex [[texture(0)]],
                                  constant CurlUniforms &u [[buffer(1)]]) {
    constexpr sampler samp(filter::linear, mip_filter::linear, address::clamp_to_edge);
    half4 tex = ticketTex.sample(samp, in.uv);

    float pitch = max(u.pitch, 0.01);
    float aFixed = in.paperAB.x;
    float b = in.paperAB.y;
    float a = (aFixed - u.patternOrigin) * u.patternSign;
    float ap = aFixed - u.patternInset;

    float pf = perfSD(ap, b, pitch, u.holeLen, u.holeHalfWidth,
                      u.strainCell, u.strain, u.patternSign,
                      u.neckFraction, u.crackWidth, u.slotCorner);

    float holeFrac = clamp(u.holeLen / pitch, 0.0, 0.99);
    float tabT = saturate((fract(ap / pitch) - holeFrac) / (1.0 - holeFrac));
    float wander = tearJitter(aFixed, u.jitterAmp) * sin(M_PI_F * tabT);
    float fracture = b - max(u.tornGap + wander, 0.35);

    float torn = smoothstep(1.5, -1.5, a - u.front);
    float edge = mix(pf, min(pf, fracture), torn);

    float pointsPerPixel = clamp(max(length(float2(dfdx(aFixed), dfdy(aFixed))),
                                     length(float2(dfdx(b), dfdy(b)))), 0.002, 4.0);
    float aaPunch = 0.5 * pointsPerPixel;
    float aa = mix(aaPunch, max(aaPunch, u.tornSoftness), torn);

    float alpha = smoothstep(-aa, aa, edge) * float(tex.a) * u.opacity;
    if (alpha <= 0.004) { discard_fragment(); }

    bool backFace = in.skin < 0.0;
    half3 printed = tex.a > 0.002h ? half3(tex.rgb / tex.a) : half3(u.paperBack.rgb);
    half3 base = backFace ? half3(u.paperBack.rgb) : printed;

    float tornTint = mix(0.94, 1.0, smoothstep(0.0, max(3.0 * aaPunch, 0.5), edge));
    float edgeTint = mix(1.0, tornTint, torn);

    half3 lit = shade(base, in.normal, edgeTint, u);
    half outA = half(alpha);
    return half4(lit * outA, outA);
}

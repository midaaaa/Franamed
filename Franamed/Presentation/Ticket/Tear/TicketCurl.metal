//
//  TicketCurl.metal
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.08.2026.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Perforation pattern

inline float hash11(float n) {
    return fract(sin(n * 127.1) * 43758.5453123);
}

inline float vnoise(float x) {
    float i = floor(x);
    float f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(hash11(i), hash11(i + 1.0), f) * 2.0 - 1.0;
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

        float amount = neckFrac * (0.94 + 0.12 * hash11(ci * 1.37));
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

inline float curlDepth(float height, float heightScale) {
    float t = clamp(height / heightScale, 0.0, 1.0);
    return 0.999 - 0.99 * t;
}

// MARK: - Pipeline

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float2 uv;
    float2 paperAB;
    float  faceSign;
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
    float _reserved1;
    float _reserved2;

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

vertex VertexOut ticketCurlVertex(uint vid [[vertex_id]],
                                  constant CurlUniforms &u [[buffer(1)]]) {
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

    float2 perfOrigin = float2(u.perfOriginX, u.perfOriginY);
    float2 perfDir = float2(u.perfDirX, u.perfDirY);
    float2 stubN = float2(u.stubNX, u.stubNY);
    float2 canvasOffset = float2(u.canvasPadding, u.canvasPadding) + float2(u.offsetX, u.offsetY);

    float2 flat = perfOrigin + perfDir * a + stubN * b;
    float2 uv = float2(flat.x / u.ticketWidth, flat.y / u.ticketHeight);
    float aFixed = u.patternOrigin + u.patternSign * a;

    VertexOut out;
    out.uv = uv;
    out.paperAB = float2(aFixed, b);

    float theta = clamp(u.theta, 0.05, M_PI_F / 2.0);
    float heightScale = max(length(float2(u.perfLength, u.stubExtent)), 1.0);
    float da = a - u.apexA;
    float radius = length(float2(da, b));

    if (radius < 0.0001) {
        float2 atApex = flat + canvasOffset;
        out.position = u.projection * float4(atApex, curlDepth(0.0, heightScale), 1.0);
        out.normal = float3(0.0, 0.0, 1.0);
        out.faceSign = 1.0;
        return out;
    }

    float sinT = sin(theta);
    float beta = atan2(b, da) / sinT;
    float3 ruling = coneRuling(beta, theta);
    float3 dRulingDPhi = float3(-sin(beta) * sinT, cos(beta), sin(beta) * cos(theta));
    float3 nrm = cross(ruling, dRulingDPhi);

    float2 apex = perfOrigin + perfDir * u.apexA;
    float2 placed = apex + perfDir * (radius * ruling.x) + stubN * (radius * ruling.y);
    float2 onScreen = placed + canvasOffset;
    float height = radius * ruling.z;

    out.position = u.projection * float4(onScreen, curlDepth(height, heightScale), 1.0);
    out.normal = float3(perfDir.x * nrm.x + stubN.x * nrm.y,
                        perfDir.y * nrm.x + stubN.y * nrm.y,
                        nrm.z);
    out.faceSign = nrm.z >= 0.0 ? 1.0 : -1.0;
    return out;
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

    bool backFace = in.faceSign < 0.0;
    half3 printed = tex.a > 0.002h ? half3(tex.rgb / tex.a) : half3(u.paperBack.rgb);
    half3 base = backFace ? half3(u.paperBack.rgb) : printed;

    float3 N = normalize(in.normal) * (backFace ? -1.0 : 1.0);
    float3 L = normalize(u.lightDir.xyz);
    float3 H = normalize(L + float3(0.0, 0.0, 1.0));

    float lambertFlat = 0.58 + 0.42 * clamp(L.z, 0.0, 1.0);
    float lambert = (0.58 + 0.42 * clamp(dot(N, L), 0.0, 1.0)) / max(lambertFlat, 0.001);

    float specFlat = pow(clamp(H.z, 0.0, 1.0), 26.0) * u.sheen;
    float spec = max(pow(clamp(dot(N, H), 0.0, 1.0), 26.0) * u.sheen - specFlat, 0.0);

    float tornTint = mix(0.94, 1.0, smoothstep(0.0, max(3.0 * aaPunch, 0.5), edge));
    float edgeTint = mix(1.0, tornTint, torn);

    half3 lit = base * half(lambert * edgeTint) + half3(half(spec * edgeTint));
    half outA = half(alpha);
    return half4(lit * outA, outA);
}

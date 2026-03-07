// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// CRT Visual Effects Shader

#include <metal_stdlib>
using namespace metal;

struct CRTUniforms {
    float scanlineIntensity;
    float scanlineWidth;
    float blurRadius;
    float bloomIntensity;
    float bloomRadius;
    float afterglowStrength;
    float afterglowDecaySpeed;
    int tintMode;
    float tintStrength;
    int maskType;
    float maskIntensity;
    float curvatureAmount;
    float vignetteStrength;
    float dtMs;
    float outputWidth;
    float outputHeight;
    float sourceWidth;
    float sourceHeight;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut crtVertexShader(uint vertexID [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0),
    };
    float2 uvs[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0),
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

// Barrel distortion for screen curvature
float2 applyCurvature(float2 uv, float amount) {
    float2 centered = uv * 2.0 - 1.0;
    float r2 = dot(centered, centered);
    float k = amount * 0.2;
    centered *= 1.0 + k * r2;
    return centered * 0.5 + 0.5;
}

// 9-tap blur sampling from source texture
float4 sampleBlurred(float2 uv, texture2d<float> src, float blurRadius,
                     float sourceWidth, float sourceHeight) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);

    float2 texelSize = float2(1.0 / sourceWidth, 1.0 / sourceHeight);
    float2 offset = texelSize * blurRadius * 2.0;

    float4 color = src.sample(linearSampler, uv) * 0.25;
    color += src.sample(linearSampler, uv + float2(offset.x, 0.0)) * 0.125;
    color += src.sample(linearSampler, uv - float2(offset.x, 0.0)) * 0.125;
    color += src.sample(linearSampler, uv + float2(0.0, offset.y)) * 0.125;
    color += src.sample(linearSampler, uv - float2(0.0, offset.y)) * 0.125;
    color += src.sample(linearSampler, uv + offset) * 0.0625;
    color += src.sample(linearSampler, uv - offset) * 0.0625;
    color += src.sample(linearSampler, uv + float2(-offset.x, offset.y)) * 0.0625;
    color += src.sample(linearSampler, uv + float2(offset.x, -offset.y)) * 0.0625;

    return color;
}

// 13-tap bloom with luminance weighting
float3 computeBloom(float2 uv, texture2d<float> src, float3 baseColor,
                    float bloomIntensity, float bloomRadius,
                    float sourceWidth, float sourceHeight) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);

    float2 texelSize = float2(1.0 / sourceWidth, 1.0 / sourceHeight);
    float2 near = texelSize * bloomRadius * 3.0;
    float2 far = near * 2.0;
    float diag = 0.707;

    // 13 taps: center + 4 near cardinal + 4 diagonal + 4 far cardinal
    float3 bloom = baseColor * 0.16;
    bloom += src.sample(linearSampler, uv + float2(near.x, 0.0)).rgb * 0.10;
    bloom += src.sample(linearSampler, uv - float2(near.x, 0.0)).rgb * 0.10;
    bloom += src.sample(linearSampler, uv + float2(0.0, near.y)).rgb * 0.10;
    bloom += src.sample(linearSampler, uv - float2(0.0, near.y)).rgb * 0.10;
    bloom += src.sample(linearSampler, uv + float2(near.x * diag, near.y * diag)).rgb * 0.06;
    bloom += src.sample(linearSampler, uv + float2(-near.x * diag, near.y * diag)).rgb * 0.06;
    bloom += src.sample(linearSampler, uv + float2(near.x * diag, -near.y * diag)).rgb * 0.06;
    bloom += src.sample(linearSampler, uv - float2(near.x * diag, near.y * diag)).rgb * 0.06;
    bloom += src.sample(linearSampler, uv + float2(far.x, 0.0)).rgb * 0.05;
    bloom += src.sample(linearSampler, uv - float2(far.x, 0.0)).rgb * 0.05;
    bloom += src.sample(linearSampler, uv + float2(0.0, far.y)).rgb * 0.05;
    bloom += src.sample(linearSampler, uv - float2(0.0, far.y)).rgb * 0.05;

    // Luminance-weighted intensity (Rec.709)
    float luma = dot(baseColor, float3(0.2126, 0.7152, 0.0722));
    float weight = smoothstep(0.1, 0.8, luma) * bloomIntensity;

    float3 result = baseColor + bloom * weight;
    // Shoulder compression: only compress values above 0.8 to prevent blowout
    // while preserving mids and darks fully
    float3 threshold = float3(0.8);
    float3 over = max(result - threshold, float3(0.0));
    result = min(result, threshold) + over / (1.0 + over * 2.5);
    return result;
}

// Sinusoidal scanlines mapped to source lines
float computeScanline(float2 uv, float sourceHeight, float intensity, float width) {
    float sourceLine = uv.y * sourceHeight;
    float frac = fract(sourceLine);
    float exponent = mix(1.0, 8.0, width);
    float scanline = pow(sin(frac * M_PI_F), exponent);
    return mix(1.0, scanline, intensity);
}

// Phosphor mask patterns
float3 applyMask(float2 pixelCoord, int maskType, float maskIntensity) {
    float3 mask = float3(1.0);
    float dim = 1.0 - maskIntensity * 0.4;

    if (maskType == 1) {
        // Aperture grille: vertical RGB stripes
        int col = int(pixelCoord.x) % 3;
        if (col == 0) mask = float3(1.0, dim, dim);
        else if (col == 1) mask = float3(dim, 1.0, dim);
        else mask = float3(dim, dim, 1.0);
    } else if (maskType == 2) {
        // Shadow mask: row-offset triads
        int row = int(pixelCoord.y);
        int col = (int(pixelCoord.x) + (row % 2) * 2) % 3;
        if (col == 0) mask = float3(1.0, dim, dim);
        else if (col == 1) mask = float3(dim, 1.0, dim);
        else mask = float3(dim, dim, 1.0);
    } else if (maskType == 3) {
        // Slot mask: triads with horizontal gaps every 3rd row
        int row = int(pixelCoord.y);
        int col = (int(pixelCoord.x) + (row / 3 % 2) * 2) % 3;
        if (row % 3 == 2) {
            mask = float3(dim);
        } else {
            if (col == 0) mask = float3(1.0, dim, dim);
            else if (col == 1) mask = float3(dim, 1.0, dim);
            else mask = float3(dim, dim, 1.0);
        }
    }
    return mask;
}

// Tint color grading
float3 applyTint(float3 color, int tintMode, float tintStrength) {
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));

    if (tintMode == 1) {
        // Amber
        float3 tinted = float3(luma, luma * 0.75, luma * 0.3);
        return mix(color, tinted, tintStrength);
    } else if (tintMode == 2) {
        // Green
        float3 tinted = float3(luma * 0.3, luma * 0.95, luma * 0.25);
        return mix(color, tinted, tintStrength);
    } else if (tintMode == 3) {
        // Monochrome
        return mix(color, float3(luma), tintStrength);
    }
    return color;
}

// Vignette: radial corner darkening
float computeVignette(float2 uv, float strength) {
    float2 centered = uv * 2.0 - 1.0;
    float dist2 = dot(centered, centered);
    return smoothstep(0.0, 1.0, 1.0 - dist2 * strength * 0.35);
}

// Afterglow with per-channel P22 phosphor decay
float3 applyAfterglow(float3 current, float4 previous, float strength,
                      float decaySpeed, float dtMs) {
    float dt_s = dtMs / 1000.0;

    // P22 phosphor: red persists longest, blue fades fastest
    float3 channelRates = float3(0.8, 1.0, 1.5) * decaySpeed;
    float3 decay = exp(-channelRates * dt_s);

    float3 persisted = previous.rgb * decay;

    // max() blend: current content is never dimmed by afterglow
    float3 result = max(current, persisted * strength);
    return result;
}

fragment float4 crtFragmentShader(VertexOut in [[stage_in]],
                                   texture2d<float> sourceTexture [[texture(0)]],
                                   texture2d<float> prevAccum [[texture(1)]],
                                   constant CRTUniforms &u [[buffer(0)]]) {
    constexpr sampler pointSampler(filter::nearest, address::clamp_to_edge);

    float2 uv = in.uv;
    float2 straightUV = uv;

    // 1. Curvature
    if (u.curvatureAmount > 0.0) {
        uv = applyCurvature(uv, u.curvatureAmount);
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }
    }

    // 2. Sample source (blur or sharp with UV snap)
    float3 color;
    if (u.blurRadius > 0.0) {
        color = sampleBlurred(uv, sourceTexture, u.blurRadius,
                              u.sourceWidth, u.sourceHeight).rgb;
    } else {
        // Snap to source pixel centers for sharp rendering
        float2 snapped;
        snapped.x = (floor(uv.x * u.sourceWidth) + 0.5) / u.sourceWidth;
        snapped.y = (floor(uv.y * u.sourceHeight) + 0.5) / u.sourceHeight;
        color = sourceTexture.sample(pointSampler, snapped).rgb;
    }

    // 3. Bloom
    if (u.bloomIntensity > 0.0) {
        color = computeBloom(uv, sourceTexture, color,
                             u.bloomIntensity, u.bloomRadius,
                             u.sourceWidth, u.sourceHeight);
    }

    // 4. Scanlines
    if (u.scanlineIntensity > 0.0) {
        float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
        float scanMul = computeScanline(straightUV, u.sourceHeight,
                                        u.scanlineIntensity, u.scanlineWidth);
        // Bright pixels resist scanlines more to preserve vibrancy
        float resist = luma * 0.5;
        scanMul = mix(scanMul, 1.0, resist);
        color *= scanMul;
    }

    // 5. Phosphor mask
    if (u.maskType > 0) {
        float3 mask = applyMask(in.position.xy, u.maskType, u.maskIntensity);
        color *= mask;
    }

    // 6. Tint
    if (u.tintMode > 0) {
        color = applyTint(color, u.tintMode, u.tintStrength);
    }

    // 7. Vignette
    if (u.vignetteStrength > 0.0) {
        color *= computeVignette(uv, u.vignetteStrength);
    }

    // 8. Afterglow
    if (u.afterglowStrength > 0.0) {
        constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
        // Sample from accumulation texture at CRT resolution UV
        float4 prev = prevAccum.sample(linearSampler, in.uv);
        color = applyAfterglow(color, prev, u.afterglowStrength,
                               u.afterglowDecaySpeed, u.dtMs);
    }

    return float4(saturate(color), 1.0);
}

// Simple passthrough for blitting accumulation texture to screen
fragment float4 blitFragmentShader(VertexOut in [[stage_in]],
                                    texture2d<float> texture [[texture(0)]]) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    return texture.sample(linearSampler, in.uv);
}

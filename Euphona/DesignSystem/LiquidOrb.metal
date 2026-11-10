#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The voice orb: liquid pink and blue light flowing inside a clear glass sphere.

namespace {

float hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + float2(1, 0)), u.x),
               mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
}

float fbm(float2 p) {
    float value = 0.0, amplitude = 0.5;
    for (int octave = 0; octave < 4; octave++) {
        value += amplitude * noise(p);
        p = float2x2(1.6, 1.2, -1.2, 1.6) * p;
        amplitude *= 0.5;
    }
    return value;
}

}  // namespace

/// `size` is the view's size in points, `time` drives the flow, `balance` runs from 0 (blue,
/// masculine) to 1 (pink, feminine) and `energy` (0...1) is the live loudness.
[[ stitchable ]] half4 liquidOrb(float2 position, half4 color, float2 size, float time, float balance, float energy, half4 theme, float harmony) {
    float diameter = min(size.x, size.y);
    float2 uv = (position - size * 0.5) / (diameter * 0.5);
    float r = length(uv);
    float edge = 1.5 / (diameter * 0.5);
    float alpha = 1.0 - smoothstep(1.0 - edge, 1.0, r);
    if (alpha <= 0.0) return half4(0);

    // The sphere: its depth at this point, and a lens that bends the light inside toward the rim.
    float z = sqrt(max(0.0, 1.0 - r * r));
    float3 normal = float3(uv, z);
    float2 inside = uv * (1.0 + 0.45 * (1.0 - z));

    // Light inside: two warped noise fields marble the sphere. One decides pink or blue around the
    // balance, the other light or deep, so the colors flow through each other like liquid.
    float t = time * (0.2 + 0.3 * energy);
    float2 warp = float2(fbm(inside * 0.7 + float2(t, -t * 0.7)), fbm(inside * 0.7 + float2(-t * 0.6, t * 0.9) + 5.2));
    float2 p = inside * 0.75 + (warp - 0.5) * 1.1;
    float hue = fbm(p + float2(t * 0.35, -t * 0.2));
    float depth = fbm(p * 1.1 + float2(-t * 0.25, t * 0.3) + 3.7);

    float share = smoothstep(0.0, 1.0, clamp(balance + (hue - 0.5) * 1.5, 0.0, 1.0));
    float3 pink = mix(float3(1.00, 0.72, 0.84), float3(0.95, 0.38, 0.60), smoothstep(0.2, 0.85, depth));
    float3 blue = mix(float3(0.64, 0.80, 1.00), float3(0.32, 0.47, 0.98), smoothstep(0.2, 0.85, depth));
    float3 light = mix(blue, pink, share);
    // A violet seam where the two colors meet, as when two dyes flow together.
    light = mix(light, float3(0.70, 0.52, 1.00), 0.35 * (1.0 - abs(share * 2.0 - 1.0)));
    // Lean toward the theme color, as ThemeColors does for every other voice color.
    light = mix(light, float3(theme.rgb), harmony);
    // Bright veins brighten with the voice.
    float vein = smoothstep(0.58, 0.85, fbm(p * 1.4 - warp + float2(-t * 0.5, t * 0.3) + 9.1));
    light = mix(light, float3(1.0, 0.97, 1.0), vein * (0.22 + 0.4 * energy));
    // Lit from within: a soft glow toward the centre, stronger while the voice is loud.
    light = mix(light, float3(1.0, 0.96, 1.0), z * z * (0.14 + 0.18 * energy));
    light *= 0.88 + 0.12 * z;

    // Glass: a fresnel rim, a soft sheen and a small bright highlight up and to the left, and a
    // caustic where light gathers at the bottom.
    float rim = pow(1.0 - z, 2.2);
    float3 toLight = normalize(float3(-0.45, -0.6, 0.66));
    float facing = max(dot(normal, toLight), 0.0);
    float caustic = smoothstep(0.6, 0.97, r) * smoothstep(0.15, 0.85, uv.y);
    float3 result = light;
    result = mix(result, float3(1.0), rim * 0.35);
    result += float3(1.0) * pow(facing, 8.0) * 0.08;
    result += float3(1.0) * pow(facing, 120.0) * 0.6;
    result = mix(result, float3(1.0), caustic * 0.25);
    result = clamp(result, 0.0, 1.0);

    return half4(half3(result) * half(alpha), half(alpha));
}

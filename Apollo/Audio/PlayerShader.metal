#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Subtle organic wave for the player's blurred cover backdrop. Driven by
// TimelineView time so it keeps flowing while the track plays.
[[stitchable]] float2 playerWarp(float2 position, float time, float2 size, float amplitude) {
    float2 uv = position / max(size, float2(1.0));
    float wave = sin(uv.y * 12.0 + time * 0.6) * 0.6
               + sin(uv.x * 9.0 - time * 0.45) * 0.4;
    return position + float2(0.0, wave * amplitude);
}

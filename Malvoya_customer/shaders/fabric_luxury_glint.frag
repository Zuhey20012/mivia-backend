#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uResolution;
uniform vec2 uGyroOffset; // Physical tilt offset (-1.0 to 1.0)
uniform float uTime;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uResolution;
    vec4 baseColor = texture(uTexture, uv);

    // Light vector driven by device gyroscope
    vec2 lightPos = vec2(0.5, 0.5) + (uGyroOffset * 0.4);
    float dist = length(uv - lightPos);

    // Specular weave highlight wave
    float weaveGlint = sin((uv.x + uv.y) * 45.0 + uTime * 2.5) * 0.5 + 0.5;
    float specular = smoothstep(0.40, 0.0, dist) * weaveGlint * 0.32;

    vec3 result = baseColor.rgb + vec3(specular * 0.92, specular * 0.96, specular * 1.0);
    fragColor = vec4(result, baseColor.a);
}

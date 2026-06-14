shader_type canvas_item;

// Slow swirling vortex — time-passes mood for the End Turn button.
// Polar-domain spiral arms warped by fbm noise, color-ramped cool blue to
// soft white at the core. Same uniform contract as the fire shader for the
// `_push()` symmetry.

uniform vec2 mouse_uv;
uniform vec2 texture_size = vec2(1.0);
uniform vec3 tint : source_color = vec3(0.35, 0.55, 0.95);
uniform vec3 hot_color : source_color = vec3(0.85, 0.95, 1.0);
uniform float glow_strength : hint_range(0.0, 1.0) = 0.0;
uniform float active_strength : hint_range(0.0, 1.0) = 0.0;
uniform float disabled_strength : hint_range(0.0, 1.0) = 0.0;

const float CORNER_RADIUS = 0.14;
const float RIM_WIDTH = 0.04;


float sdf_rrect(vec2 p, vec2 b, float r) {
    vec2 d = abs(p) - b + r;
    return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - r;
}

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * value_noise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}


void fragment() {
    float aspect = texture_size.x / texture_size.y;
    vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
    vec2 mp = (mouse_uv - 0.5) * vec2(aspect, 1.0);

    float dist = sdf_rrect(p, vec2(0.5 * aspect, 0.5), CORNER_RADIUS);
    float aa = length(vec2(dFdx(dist), dFdy(dist)));
    float shape = 1.0 - smoothstep(-aa, aa, dist);
    if (shape < 0.001) discard;

    // Polar domain. Spiraling arms: angle modulated by radius gives the
    // logarithmic-spiral look; TIME advances the whole pattern.
    float r = length(p);
    float a = atan(p.y, p.x);
    float swirl_a = a - r * 5.0 + TIME * 0.9;

    float arms = sin(swirl_a * 3.0) * 0.5 + 0.5;
    float noise_warp = fbm(vec2(swirl_a * 0.5, r * 2.5) + TIME * 0.15);
    arms = arms * 0.6 + noise_warp * 0.4;

    // Wide buttons: fade by an elongated radial so the arms taper into the
    // dark background near the edges instead of just clipping.
    float radial = smoothstep(0.6, 0.1, length(p * vec2(0.7, 1.0)));
    arms *= radial;

    vec3 col = vec3(0.03, 0.04, 0.10);
    col = mix(col, tint, arms * active_strength);
    col = mix(col, hot_color, pow(arms, 3.0) * active_strength);

    // Bright core
    float core = smoothstep(0.30, 0.0, r);
    col += hot_color * core * active_strength * 0.25;

    // Mouse hot spot
    float md = distance(p, mp);
    float mouse_spot = 1.0 - smoothstep(0.0, 0.5, md);
    col += hot_color * mouse_spot * glow_strength * 0.35;

    // Rim
    float rim = shape * smoothstep(RIM_WIDTH, 0.0, -dist);
    col += mix(tint, hot_color, 0.4) * rim * (0.22 + active_strength * 0.5 + glow_strength * 0.4);

    vec2 noise_cell = floor(UV * texture_size * 0.3);
    col += (hash21(noise_cell) - 0.5) * 0.01;

    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, vec3(luma * 0.30), disabled_strength * 0.85);
    float alpha = shape * (1.0 - disabled_strength * 0.55);

    COLOR = vec4(col, alpha);
}

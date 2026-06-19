shader_type canvas_item;

// Slow swirling vortex — time-passes mood for the End Turn button.
// Polar-domain spiral arms warped by fbm noise, color-ramped per turn phase.
// phase_blend: 0=CONTRACT (blue, calm), 1=EXPAND (green, growing), 2=BATTLE (orange, fast).
// Same uniform contract as the fire shader for the `_push()` symmetry.

uniform vec2 mouse_uv;
uniform vec2 texture_size = vec2(1.0);
uniform vec3 tint : source_color = vec3(0.35, 0.55, 0.95);
uniform vec3 hot_color : source_color = vec3(0.85, 0.95, 1.0);
uniform float glow_strength : hint_range(0.0, 1.0) = 0.0;
uniform float active_strength : hint_range(0.0, 1.0) = 0.0;
uniform float disabled_strength : hint_range(0.0, 1.0) = 0.0;
uniform float phase_blend : hint_range(0.0, 2.0) = 0.0;

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

    // Phase-derived tint and swirl speed.
    // CONTRACT=0: cool blue, relaxed cadence.
    // EXPAND=1:   teal-green, growing drift.
    // BATTLE=2:   orange-red, quick spiral.
    float p01 = clamp(phase_blend, 0.0, 1.0);
    float p12 = clamp(phase_blend - 1.0, 0.0, 1.0);
    vec3 tint_contract = vec3(0.28, 0.48, 0.92);
    vec3 tint_expand   = vec3(0.18, 0.72, 0.52);
    vec3 tint_battle   = vec3(0.88, 0.32, 0.10);
    vec3 phase_tint = mix(mix(tint_contract, tint_expand, p01), tint_battle, p12);
    vec3 phase_hot  = mix(mix(vec3(0.85, 0.95, 1.0), vec3(0.60, 1.0, 0.78), p01),
                          vec3(1.0, 0.72, 0.35), p12);
    // Contract=0.55, Expand=0.85, Battle=1.6
    float swirl_speed = mix(mix(0.55, 0.85, p01), 1.6, p12);

    // Polar domain. Spiral arms: angle modulated by radius gives the
    // logarithmic-spiral look; TIME * swirl_speed drives the rotation.
    float r = length(p);
    float a = atan(p.y, p.x);
    float swirl_a = a - r * 5.0 + TIME * swirl_speed;

    float arms = sin(swirl_a * 3.0) * 0.5 + 0.5;
    float noise_warp = fbm(vec2(swirl_a * 0.5, r * 2.5) + TIME * 0.15);
    arms = arms * 0.6 + noise_warp * 0.4;

    // Taper toward the edges; also scale down overall so text stays legible.
    float radial = smoothstep(0.6, 0.1, length(p * vec2(0.7, 1.0)));
    arms = arms * radial * 0.55;

    vec3 col = vec3(0.03, 0.04, 0.10);
    col = mix(col, phase_tint, arms * active_strength * 0.85);
    col = mix(col, phase_hot, pow(arms, 3.0) * active_strength * 0.85);

    // Subtle core — kept dim so text is not washed out.
    float core = smoothstep(0.30, 0.0, r);
    col += phase_hot * core * active_strength * 0.12;

    // Mouse hot spot
    float md = distance(p, mp);
    float mouse_spot = 1.0 - smoothstep(0.0, 0.5, md);
    col += phase_hot * mouse_spot * glow_strength * 0.30;

    // Rim
    float rim = shape * smoothstep(RIM_WIDTH, 0.0, -dist);
    col += mix(phase_tint, phase_hot, 0.4) * rim * (0.22 + active_strength * 0.5 + glow_strength * 0.4);

    vec2 noise_cell = floor(UV * texture_size * 0.3);
    col += (hash21(noise_cell) - 0.5) * 0.01;

    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, vec3(luma * 0.30), disabled_strength * 0.85);
    float alpha = shape * (1.0 - disabled_strength * 0.55);

    COLOR = vec4(col, alpha);
}

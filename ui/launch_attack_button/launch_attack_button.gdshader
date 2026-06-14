shader_type canvas_item;

// Procedural fire that fills a rounded-rect button. Two-octave value-noise
// fbm, vertically advected to give "rising flame" motion, color-ramped from
// dark red → tint orange → hot yellow-white. Bright ember sparks pepper the
// surface when active. Cools to grey-and-dim when disabled.
//
// Uniform contract matches attack_mode_button.gdshader so a single _push()
// in GDScript drives both the bg and text materials.

uniform vec2 mouse_uv;
uniform vec2 texture_size = vec2(1.0);
uniform vec3 tint : source_color = vec3(1.0, 0.55, 0.1);
uniform vec3 hot_color : source_color = vec3(1.0, 1.0, 0.7);
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
    for (int i = 0; i < 5; i++) {
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

    // Two flow layers — slower wide base, faster jittered overlay — combined
    // to break up obvious vertical streaks. UV.y grows downward in
    // canvas_item, so +TIME on Y makes the sampled noise rise on screen.
    vec2 base_uv = vec2(UV.x * aspect * 2.2, UV.y * 1.6);
    vec2 flow1 = base_uv + vec2(0.0, TIME * 1.1);
    vec2 flow2 = base_uv * 1.7 + vec2(TIME * 0.2, TIME * 0.7);
    float n = fbm(flow1) * 0.65 + fbm(flow2) * 0.35;

    // Flame envelope: bottom-heavy (UV.y=1 is the bottom edge in
    // canvas_item), horizontally narrowed at edges so the fire reads as a
    // column rather than a uniform wash.
    float u_centered = (UV.x - 0.5) * 2.0;
    float horiz_falloff = 1.0 - smoothstep(0.7, 1.0, abs(u_centered));
    float vertical_mask = pow(UV.y, 1.4);
    float fire = n * vertical_mask * horiz_falloff;
    fire = pow(fire, 1.3);

    vec3 deep = vec3(0.55, 0.05, 0.0);
    vec3 col_fire = mix(deep, tint, smoothstep(0.05, 0.35, fire));
    col_fire = mix(col_fire, hot_color, smoothstep(0.45, 0.85, fire));
    float vis = smoothstep(0.08, 0.22, fire);

    vec3 col = vec3(0.06, 0.02, 0.01) * (1.0 - UV.y * 0.4);
    col = mix(col, col_fire, vis * active_strength);

    // Mouse hot spot — hovering melts the cursor area brighter.
    float md = distance(p, mp);
    float mouse_spot = 1.0 - smoothstep(0.0, 0.5, md);
    col += hot_color * mouse_spot * glow_strength * 0.45;

    // Embers — high-frequency sparkles riding the same upward current.
    float spark = fbm(base_uv * 3.0 + vec2(TIME * 0.3, TIME * 2.5));
    spark = smoothstep(0.78, 0.92, spark) * vertical_mask;
    col += hot_color * spark * active_strength * 1.6;

    // Rim: always faintly present; flares with active + hover.
    float rim = shape * smoothstep(RIM_WIDTH, 0.0, -dist);
    float rim_bright = 0.20 + active_strength * 0.6 + glow_strength * 0.4;
    col += mix(tint, hot_color, 0.4) * rim * rim_bright;

    // Subtle dither so flat regions don't band.
    vec2 noise_cell = floor(UV * texture_size * 0.3);
    col += (hash21(noise_cell) - 0.5) * 0.012;

    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, vec3(luma * 0.30), disabled_strength * 0.85);
    float alpha = shape * (1.0 - disabled_strength * 0.55);

    COLOR = vec4(col, alpha);
}

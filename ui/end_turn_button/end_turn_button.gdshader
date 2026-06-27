shader_type canvas_item;

// Forward-scrolling chevrons. Phases are gone (single-phase turn), so the
// count + tint are fixed; the chevrons just give the button life. Hover speeds
// the scroll.

uniform vec2 mouse_uv;
uniform vec2 texture_size = vec2(1.0);
uniform vec3 tint : source_color = vec3(0.55, 0.7, 1.0);
uniform vec3 hot_color : source_color = vec3(0.85, 0.95, 1.0);
uniform float glow_strength : hint_range(0.0, 1.0) = 0.0;
uniform float active_strength : hint_range(0.0, 1.0) = 0.0;
uniform float disabled_strength : hint_range(0.0, 1.0) = 0.0;
uniform int chevron_count : hint_range(1, 3) = 1;
// Driven from EndTurnButton.gd: accumulates `delta * current_speed` per frame.
// Doing the integration in script means a hover-driven speed bump doesn't
// reproject all of TIME through the new multiplier (which jumps the pattern
// hard at large TIME).
uniform float scroll_offset = 0.0;

const float CORNER_RADIUS = 0.14;

const float CHEVRON_THICKNESS = 0.25; // was: 0.055
const float GLOW_INTENSITY = 0.35;

float sdf_rrect(vec2 p, vec2 b, float r) {
    vec2 d = abs(p) - b + r;
    return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - r;
}

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


void fragment() {
    float aspect = texture_size.x / texture_size.y;
    vec2 p = (UV - 0.5) * vec2(aspect, 1.0);

    float dist = sdf_rrect(p, vec2(0.5 * aspect, 0.5), CORNER_RADIUS);
    float aa = length(vec2(dFdx(dist), dFdy(dist)));
    float shape = 1.0 - smoothstep(-aa, aa, dist);
    if (shape < 0.001) discard;

    // Background — slight tint wash for ambient "this is alive."
    vec3 bg = mix(vec3(0.02, 0.03, 0.06), tint * 0.18, 0.45);

    // Chevron pattern. Apex-right ">" — level-set coord is x + |y|/slope, so
    // each chevron is a constant-c curve x = c - |y|/slope (apex at +x). The
    // scroll_offset uniform is integrated in script; here we only translate.
    // Spacing shrinks as count grows so 3 fit comfortably; thickness scales
    // inversely so each chevron stays crisp.
    float slope = 1.55;
    float count = float(chevron_count);
    float spacing = 0.78 / count;          // 0.78 / 1 .. 0.78 / 3
    float thickness = CHEVRON_THICKNESS / sqrt(count); // 0.055 .. 0.032

    float apex_coord = (p.x + abs(p.y) / slope) / spacing;
    float scrolled = apex_coord - scroll_offset / spacing;
    float stripe = fract(scrolled);
    float band = smoothstep(thickness, 0.0, abs(stripe - 0.5) * spacing);

    // Edge taper — keep chevrons inside the rounded body.
    float inset = smoothstep(-0.02, 0.10, -dist);
    band *= inset * GLOW_INTENSITY;

    vec3 col = bg;
    col = mix(col, tint, band * (0.45 + active_strength * 0.45));
    col = mix(col, hot_color, band * band * (0.5 + glow_strength * 0.55) * active_strength);

    // Mouse hot spot
    vec2 mp = (mouse_uv - 0.5) * vec2(aspect, 1.0);
    float md = distance(p, mp);
    float mouse_spot = 1.0 - smoothstep(0.0, 0.5, md);
    col += hot_color * mouse_spot * glow_strength * 0.28;

    // Rim
    float rim = shape * smoothstep(0.04, 0.0, -dist);
    col += mix(tint, hot_color, 0.4) * rim * (0.25 + active_strength * 0.35 + glow_strength * 0.4);

    // Static grain
    vec2 noise_cell = floor(UV * texture_size * 0.3);
    col += (hash21(noise_cell) - 0.5) * 0.012;

    // Disabled desat
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, vec3(luma * 0.30), disabled_strength * 0.85);
    float alpha = shape * (1.0 - disabled_strength * 0.55);

    COLOR = vec4(col, alpha);
}

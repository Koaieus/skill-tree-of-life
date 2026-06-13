shader_type canvas_item;

uniform vec2 mouse_uv;
uniform ivec2 texture_size = ivec2(1);
uniform vec3 tint : source_color;
uniform float glow_radius : hint_range(0.0, 1.0) = 0.3;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.0;
uniform float active_strength : hint_range(0.0, 1.0) = 0.0;
uniform float disabled_strength : hint_range(0.0, 1.0) = 0.0;

const float CORNER_RADIUS = 0.12; // fraction of button height
const float RIM_WIDTH     = 0.04;
const float ARC_ANGULAR_SPEED = .28;  //  0.28
const float BREATHING_SPEED = 3.;
const float BREATHING_AMP = 0.5;

// Rounded-rect SDF: p centered at origin, b = full half-extents, r = corner radius.
float sdf_rrect(vec2 p, vec2 b, float r) {
    vec2 d = abs(p) - b + r;
    return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - r;
}

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    float aspect = float(texture_size.x) / float(texture_size.y);

    // Aspect-corrected, origin-centred space (y: -0.5..0.5, x: -0.5*aspect..0.5*aspect)
    vec2 p  = (UV - 0.5) * vec2(aspect, 1.0);
    vec2 mp = (mouse_uv - 0.5) * vec2(aspect, 1.0);

    float dist = sdf_rrect(p, vec2(0.5 * aspect, 0.5), CORNER_RADIUS);

    // Pixel-AA shape mask — discard empty corners
    float aa    = length(vec2(dFdx(dist), dFdy(dist)));
    float shape = 1.0 - smoothstep(-aa, aa, dist);
    if (shape < 0.001) discard;

    // Rim mask: 1 at border, fades inward over RIM_WIDTH
    float rim = shape * smoothstep(RIM_WIDTH, 0.0, -dist);

    // ── Base fill ─────────────────────────────────────────────────────────────
    // Dark tint; top-lit gradient simulates a convex surface.
    float top_light = 1.0 - UV.y * 0.5;
    vec3 col = tint * 0.10 * top_light;

    // Bevel: thin bright strip at the top edge (light source above)
    float bevel = smoothstep(0.22, 0.0, UV.y) * 0.07;
    col += tint * bevel + vec3(bevel * 0.35);

    // ── Mouse proximity glow ──────────────────────────────────────────────────
    float md         = distance(p, mp);
    float mouse_spot = 1.0 - smoothstep(0.0, glow_radius * 0.5, md);
    col += tint * mouse_spot * glow_strength * 0.30;

    // ── Active fill: breathing tint pulse ─────────────────────────────────────
    float pulse = sin(TIME * 2.8 * BREATHING_SPEED) * BREATHING_AMP + 0.5;
    col += tint * active_strength * (0.12 + pulse * 0.06);

    // ── Rim layer ─────────────────────────────────────────────────────────────
    // Always dimly present; brightened by hover and active.
    float rim_bright = 0.20 + glow_strength * 0.45 + active_strength * 0.65;
    col += mix(tint, vec3(1.0), 0.22) * rim_bright * rim;

    // Mouse also brightens the rim near the cursor
    col += tint * rim * mouse_spot * glow_strength * 0.55;

    // ── Orbit arc: glowing spark sweeping around the rim when active ──────────
    // atan gives angle around center; fract makes it a 0..1 position that
    // advances with TIME. The spark is a smooth arc ~30 % of perimeter wide.
    float angle  = atan(p.y, p.x);
    float flow_t = fract(angle / TAU - TIME * ARC_ANGULAR_SPEED);
    float flow   = smoothstep(0.0, 0.12, flow_t) * smoothstep(0.32, 0.12, flow_t);
    col += mix(vec3(1.0), tint, 0.15) * rim * flow * active_strength * 1.8;

    // ── Subtle dithered noise ─────────────────────────────────────────────────
    vec2 noise_cell = floor(UV * vec2(float(texture_size.x), float(texture_size.y)) * 0.3);
    col += (hash21(noise_cell) - 0.5) * 0.015;

    // ── Disabled: desaturate to dim luma, reduce alpha ────────────────────────
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col   = mix(col, vec3(luma * 0.30), disabled_strength * 0.85);
    float alpha = shape * (1.0 - disabled_strength * 0.55);

    COLOR = vec4(col, alpha);
}

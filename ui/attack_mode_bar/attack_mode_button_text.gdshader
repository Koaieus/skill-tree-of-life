shader_type canvas_item;

// Only the subset of params this shader uses; the rest pushed by GDScript are ignored.
uniform vec3 tint : source_color;
uniform float glow_strength   : hint_range(0.0, 1.0) = 0.0;
uniform float active_strength : hint_range(0.0, 1.0) = 0.0;
uniform float disabled_strength : hint_range(0.0, 1.0) = 0.0;

// Emissive.at()'s tier vocabulary, in the shader's own colour space.
//
// `Emissive.at()` does an sRGB->linear->sRGB round trip because it hands a
// `Color` to `modulate` / a theme, which the renderer converts on the way in.
// A `source_color` uniform has ALREADY been converted — under HDR 2D the
// renderer works in linear space and converts these on upload — so the lift
// here is a plain multiply. Running the round trip on an already-linear base
// (as `ui/theme/fused_panel.gdshader` still does) double-converts and costs
// ~5x the energy, landing the glyph just under the bright-pass: probed
// side-by-side on the real Vulkan backend 2026-09-01, the round-trip version
// does not bloom at ANY tier while this one matches a `modulate`-lifted Label.
//
// ALERT, not VALUE: a glyph stroke at VALUE barely crosses the bright-pass and
// reads flat — text is thin, and the level weights in `default_game_env.tres`
// are deliberately tuned onto the tightest mips. ALERT is the lowest named
// tier that reads as lit on type; PEAK is documented as a momentary overshoot,
// and an active tab is a resting state.
const float TIER_ALERT = 2.0;

vec3 emissive_at(vec3 base_linear, float stops) {
    return base_linear * exp2(stops);
}

void fragment() {
    vec4 glyph = texture(TEXTURE, UV);

    // 4-tap halo: sample ±1.5 px outside the glyph for a soft glow corona.
    float halo_px = 1.5;
    float halo = 0.0;
    halo += texture(TEXTURE, UV + TEXTURE_PIXEL_SIZE * vec2( halo_px, 0.0)).a;
    halo += texture(TEXTURE, UV + TEXTURE_PIXEL_SIZE * vec2(-halo_px, 0.0)).a;
    halo += texture(TEXTURE, UV + TEXTURE_PIXEL_SIZE * vec2(0.0,  halo_px)).a;
    halo += texture(TEXTURE, UV + TEXTURE_PIXEL_SIZE * vec2(0.0, -halo_px)).a;
    // Only let halo spill outside the glyph itself
    halo = halo * 0.25 * (1.0 - glyph.a);

    float glow_power = active_strength * 0.7 + glow_strength * 0.25;
    float color_t    = active_strength * 0.8 + glow_strength * 0.35;

    // Text: off-white baseline → emissive tint when active/hovered — ALERT tier
    // at full activation, so the label itself crosses the bloom threshold.
    vec3 text_col = mix(vec3(0.82), emissive_at(tint, TIER_ALERT), clamp(color_t, 0.0, 1.0));

    // Disabled: desaturate and dim
    float luma = dot(text_col, vec3(0.299, 0.587, 0.114));
    text_col = mix(text_col, vec3(luma * 0.35), disabled_strength * 0.85);

    // Composite: halo behind glyph, text_col on top — weighted by alpha contribution.
    vec3 halo_col = mix(vec3(1.0), tint, 0.25) * glow_power;
    float alpha = clamp(glyph.a + halo * glow_power, 0.0, 1.0);
    vec3 col = mix(halo_col, text_col, glyph.a / max(alpha, 0.001));

    COLOR = vec4(col, alpha * (1.0 - disabled_strength * 0.5));
}

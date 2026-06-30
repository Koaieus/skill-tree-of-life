shader_type canvas_item;
// Applied to the SubViewportContainer that renders the toast label.
// TEXTURE is the SubViewport's output (220×32, transparent background).

// 0 = original colour → 1 = fully desaturated. Tweened simultaneously during
// the strike so the whole label greys at once (not left-to-right).
uniform float gray_amount     : hint_range(0.0, 1.0)  = 0.0;
// Leading-edge X position in UV space (0→1). Drives glow + line growth.
uniform float strike_x        : hint_range(0.0, 1.0)  = 0.0;
// 0 = no split → 1 = halves fully apart. Drives the unzip phase.
uniform float split_open      : hint_range(0.0, 1.0)  = 0.0;
// Cut height in UV space — set once from strike_y_frac, never tweened.
uniform float split_y         : hint_range(0.0, 1.0)  = 0.46;
// Scene-tunable colours and sizes (inspector on SubViewportContainer material).
uniform vec4  hot_color       : source_color = vec4(1.0, 0.65, 0.1,  1.0);
uniform vec4  line_color      : source_color = vec4(0.55, 0.55, 0.55, 1.0);
// Glow half-width in UV space: 0.06 ≈ 13px glow at 220px wide.
uniform float tip_radius      : hint_range(0.01, 0.3)  = 0.06;
// Strike-line half-thickness: 0.035 ≈ 1.1px at 32px tall.
uniform float line_half_thick : hint_range(0.005, 0.1) = 0.035;

void fragment() {
    vec2 uv = UV;

    // --- Unzip: UV displacement so each half slides away from the cut line ---
    // Top half content (uv.y < split_y) slides up: screen pixel at y samples
    // from y + offset (content that was deeper in the top zone).  When that
    // source crosses split_y the gap has opened → transparent.
    if (split_open > 0.0) {
        if (uv.y < split_y) {
            float src_y = uv.y + split_open * split_y;
            if (src_y >= split_y) { COLOR = vec4(0.0); discard; }
            uv.y = src_y;
        } else {
            float src_y = uv.y - split_open * (1.0 - split_y);
            if (src_y <= split_y) { COLOR = vec4(0.0); discard; }
            uv.y = src_y;
        }
    }

    vec4  tex       = texture(TEXTURE, uv);
    float heat_norm = 1.0 - smoothstep(0.0, tip_radius,      abs(uv.x - strike_x));
    float on_line   = 1.0 - smoothstep(0.0, line_half_thick, abs(uv.y - split_y));
    float struck    = step(uv.x, strike_x);

    // Transparent glyph gaps: only the strike line is drawn there, so the cut
    // reads as a continuous beam rather than a dotted line between letters.
    if (tex.a < 0.005) {
        float line_a = on_line * struck * gray_amount;
        if (line_a < 0.005) { COLOR = vec4(0.0); discard; }
        COLOR = vec4(mix(line_color.rgb, hot_color.rgb, heat_norm), line_a);
        discard;
    }

    // Greyscale — whole label simultaneously (gray_amount is NOT per-pixel).
    float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
    vec3  col = mix(tex.rgb, vec3(lum), gray_amount);

    // Hot tip glow on glyph pixels.
    col = mix(col, hot_color.rgb, heat_norm);

    // Strike line overlaid on glyph pixels at split_y.
    col = mix(col,
              mix(line_color.rgb, hot_color.rgb, heat_norm),
              on_line * struck * gray_amount);

    COLOR = vec4(col, tex.a);
}

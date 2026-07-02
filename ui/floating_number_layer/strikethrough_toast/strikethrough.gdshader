shader_type canvas_item;
// Applied to the SubViewportContainer that renders the toast label.
// TEXTURE is the SubViewport's output (220×32, transparent background).

uniform vec2 label_size; 
varying vec2 text_uv;

// 0 = original colour → 1 = fully desaturated. Tweened simultaneously during
// the strike so the whole label greys at once (not left-to-right).
uniform float gray_amount     : hint_range(0.0, 1.0)  = 0.0;
// Leading-edge X position in UV space (0→1). Drives glow + line growth.
uniform float strike_x        : hint_range(0.0, 1.0)  = 0.0;
// 0 = no split → 1 = halves fully apart. Drives the unzip phase.
uniform float split_open      : hint_range(0.0, 1.0)  = 0.0;
// Diagonal cut endpoints in UV space (y at x=0 and y at x=1).
// split_y_start > split_y_end → line goes bottom-left to top-right.
// Set once from font metrics in _ready(), never tweened.
uniform float split_y_start   : hint_range(0.0, 1.0)  = 0.85;
uniform float split_y_end     : hint_range(0.0, 1.0)  = 0.15;
// Scene-tunable colours and sizes (inspector on SubViewportContainer material).
uniform vec4  hot_color       : source_color = vec4(1.0, 0.65, 0.1,  1.0);
uniform vec4  line_color      : source_color = vec4(0.55, 0.55, 0.55, 1.0);
// Glow half-width in UV space: 0.06 ≈ 13px glow at 220px wide.
uniform float tip_radius      : hint_range(0.01, 0.3)  = 0.06;
// Strike-line half-thickness: 0.035 ≈ 1.1px at 32px tall.
uniform float line_half_thick : hint_range(0.005, 0.1) = 0.035;

void vertex() {
    // Reconstructs clean 0.0 to 1.0 UVs across the entire label bounding box
    text_uv = VERTEX / label_size;
}

void fragment() {
    vec2 uv = text_uv;
	vec2 letter_uv = UV;
	// Glyph colour lives in the incoming vertex COLOR, not in TEXTURE. On a Label
	// canvas material TEXTURE is the font atlas — coverage in .a, RGB is white —
	// so the letters must be tinted by COLOR (font_color on the main pass,
	// outline_color on the outline pass) or they render all-white with no outline.
	// COLOR.a also carries modulate:a, which drives the _animate_out fade.
	vec4 base_col = COLOR;

    // Cut line position at this x — linear interpolation gives the diagonal.
    // Endpoints are set once from font metrics (StrikethroughToast.strike_endpoints).
    float local_split_y = mix(split_y_start, split_y_end, uv.x);

    // --- Unzip: UV displacement so each half slides away from the cut line ---
    // Top half content (uv.y < local_split_y) slides up: screen pixel at y
    // samples from deeper in the top zone.  When source crosses local_split_y
    // the gap has opened → transparent.
    if (split_open > 0.0) {
        if (uv.y < local_split_y) {
            float src_y = uv.y + split_open * local_split_y;
            if (src_y >= local_split_y) { COLOR = vec4(0.0); discard; }
            //uv.y = src_y;
			letter_uv.y += split_open * local_split_y / label_size.y;
        } else {
            float src_y = uv.y - split_open * (1.0 - local_split_y);
            if (src_y <= local_split_y) { COLOR = vec4(0.0); discard; }
            //uv.y = src_y;
			letter_uv.y -= split_open * local_split_y / label_size.y;
        }
    }


    vec4  tex       = texture(TEXTURE, letter_uv);
    // Hot tip is a laser DOT travelling along the cut, not a vertical column:
    // distance to the point where the leading edge meets the diagonal, measured
    // in height-normalised units (x scaled by W/H) so the glow reads round.
    float tip_y     = mix(split_y_start, split_y_end, strike_x);
    vec2  aspect    = vec2(label_size.x / max(label_size.y, 1.0), 1.0);
    float heat_norm = 1.0 - smoothstep(0.0, tip_radius, length((uv - vec2(strike_x, tip_y)) * aspect));
    float on_line   = 1.0 - smoothstep(0.0, line_half_thick, abs(uv.y - local_split_y));
    float struck    = step(uv.x, strike_x);

    if (tex.a < 0.005) {
        // Transparent glyph gap: only the strike beam is drawn there, so the cut
        // reads as a continuous line rather than a dotted one between letters.
        // (`return` is illegal in fragment(), so the glyph path is the else arm.)
        float line_a = on_line * struck * gray_amount * base_col.a;
        if (line_a < 0.005) { discard; }
        COLOR = vec4(mix(line_color.rgb, hot_color.rgb, heat_norm), line_a);
    } else {
        // Letter colour comes from base_col (font_color / outline_color), NOT
        // tex.rgb. Greyscale is whole-label simultaneous (gray_amount is uniform).
        float lum = dot(base_col.rgb, vec3(0.299, 0.587, 0.114));
        vec3  col = mix(base_col.rgb, vec3(lum), gray_amount);
        // Hot tip glow on glyph pixels.
        col = mix(col, hot_color.rgb, heat_norm);
        // Strike line overlaid on glyph pixels at the diagonal.
        col = mix(col,
                  mix(line_color.rgb, hot_color.rgb, heat_norm),
                  on_line * struck * gray_amount);
        COLOR = vec4(col, tex.a * base_col.a);
    }
	//COLOR = mix(COLOR, vec4(1.,0,0,1), float(abs(text_uv.y - local_split_y) < 0.05));
}

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
    float heat_norm = 1.0 - smoothstep(0.0, tip_radius,      abs(uv.x - strike_x));
    float on_line   = 1.0 - smoothstep(0.0, line_half_thick, abs(uv.y - local_split_y));
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

    // Strike line overlaid on glyph pixels at the diagonal.
    col = mix(col,
              mix(line_color.rgb, hot_color.rgb, heat_norm),
              on_line * struck * gray_amount);

    COLOR = vec4(col, tex.a);
	//COLOR = mix(COLOR, vec4(1.,0,0,1), float(abs(text_uv.y - local_split_y) < 0.05));
}

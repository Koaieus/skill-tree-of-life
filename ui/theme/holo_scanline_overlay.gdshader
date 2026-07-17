shader_type canvas_item;

// Hologram scanline overlay (the picked "FILTER" foreground treatment): a
// semi-transparent sheet drawn ON TOP of crisp content, adding only animated
// scanlines. It does NOT read or recolor the pixels beneath — text/icons keep
// their own color and contrast — so it's cheap and legible, the "UI behind
// CRT glass" look. The crisp card edge is owned by HoloPanel (glow_edges), not
// here, so a HoloPanel + this overlay compose without a double border.
//
// Host on a ColorRect sized to the panel, drawn as the LAST child so it sits
// above the content. `size` is pushed by the host so the rounded mask matches
// the panel rect.
uniform vec2 size = vec2(220.0, 160.0);
uniform float corner_radius = 13.0;
uniform vec4 line_color : source_color = vec4(0.4, 0.95, 1.0, 1.0);
uniform float scanline_count = 90.0;
uniform float scanline_speed = 0.4;
uniform float scanline_intensity = 0.22;

float sd_round_rect(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 px = UV * size;
	float d = sd_round_rect(px - size * 0.5, size * 0.5, corner_radius);
	float shape_alpha = 1.0 - smoothstep(-1.0, 1.0, d);

	// Additive scanlines drifting downward, clipped to the rounded rect.
	float scan = smoothstep(0.6, 1.0,
		sin(UV.y * scanline_count * TAU - TIME * scanline_speed * TAU));
	vec3 add = line_color.rgb * scan * scanline_intensity;
	float add_a = scan * scanline_intensity;

	COLOR = vec4(add, add_a * shape_alpha);
}

shader_type canvas_item;
// Cylinder shading for the volley bar's arrow shafts. Every draw_texture_rect
// of the 1x1 white texture spans UV 0..1 across its own width, so UV.x is the
// position across one shaft; the per-type colour arrives as vertex colour.

void fragment() {
	float across = UV.x * 2.0 - 1.0;
	float lit = sqrt(max(1.0 - across * across, 0.0));
	float shade = mix(0.55, 1.15, lit);
	vec4 base = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(base.rgb * shade, base.a);
}

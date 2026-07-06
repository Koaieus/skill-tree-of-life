shader_type canvas_item;

// #125 — the crest->rim bevel as a REAL height(radius) bumpmap, lit the same
// way as inner_disk.gdshader (shared LIGHT_DIR) so the disk and its rim read
// as lit from one source. The 4 locked presets (level/terrace/smooth/
// sharpen) are closed-form functions of the normalized radial domain `t`,
// selected by `height_preset` — that keeps them out of a Curve resource
// entirely, so every ring_wall on a built-in preset shares ONE
// ShaderMaterial via `instance uniform`s (batches into one draw call).
//
// A genuinely custom (5th/6th profile) Curve can't ride an instance
// uniform — samplers aren't allowed there — so ring_wall.gd falls back to a
// per-instance material + a small baked LUT texture for that case
// (height_preset == 4), an intentional, documented, opt-in cost. See
// skill_node/visuals/ring_wall.gd.

instance uniform float crest_r = 28.0;
instance uniform float rim_r = 32.0;
instance uniform vec4 wall_tint : source_color = vec4(0.65, 0.67, 0.72, 1.0);
instance uniform int height_preset = 0; // 0 level, 1 terrace, 2 smooth, 3 sharpen, 4 custom (height_lut)

// Only bound (and only sampled) for height_preset == 4, on that instance's
// own per-instance material — see ring_wall.gd::_sync_material.
uniform sampler2D height_lut;

const vec3 LIGHT_DIR = vec3(-0.35, -0.35, 0.65);

float height_level(float t) {
	return t;
}

float height_terrace(float t) {
	return clamp((floor(t * 3.0) + 1.0) / 3.0, 0.0, 1.0);
}

float height_smooth(float t) {
	return smoothstep(0.0, 1.0, t);
}

float height_sharpen(float t) {
	return t * t * t;
}

float sample_height(float t) {
	t = clamp(t, 0.0, 1.0);
	float h = height_level(t);
	h = mix(h, height_terrace(t), float(height_preset == 1));
	h = mix(h, height_smooth(t), float(height_preset == 2));
	h = mix(h, height_sharpen(t), float(height_preset == 3));
	h = mix(h, texture(height_lut, vec2(t, 0.5)).r, float(height_preset == 4));
	return h;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * rim_r;
	float r = length(p);
	float span = max(rim_r - crest_r, 0.0001);
	float t = clamp((r - crest_r) / span, 0.0, 1.0);

	float eps = 0.015;
	float h0 = sample_height(t - eps);
	float h1 = sample_height(t + eps);
	float slope = (h1 - h0) / (2.0 * eps);

	vec2 radial_dir = r > 0.0001 ? p / r : vec2(0.0, 1.0);
	vec3 normal = normalize(vec3(-radial_dir * slope, 1.0));
	float diffuse = max(dot(normal, normalize(LIGHT_DIR)), 0.0);
	vec3 shaded = wall_tint.rgb * (0.35 + 0.65 * diffuse);

	float inside = step(crest_r, r) * step(r, rim_r);
	float edge_soft = smoothstep(crest_r - 0.75, crest_r + 0.75, r) * (1.0 - smoothstep(rim_r - 0.75, rim_r + 0.75, r));
	COLOR = vec4(shaded, wall_tint.a * edge_soft * inside);
}

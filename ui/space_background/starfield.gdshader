shader_type canvas_item;
render_mode blend_add;

// One tileable star layer, drawn transparent-with-additive so several of these
// stack over the nebula/base without occluding each other. It draws in its own
// local UV (0..1 across the host rect) and emits identical output for every
// copy, so the Parallax2D that hosts it can `repeat_size`-tile it across the
// screen seamlessly and scroll it for parallax — no camera uniforms here, the
// parallax lives entirely in the Parallax2D node. Twinkle animates in-editor.

// Star grid cells across the tile. Higher = denser/smaller stars.
uniform float cells_across : hint_range(4.0, 64.0) = 22.0;
// Fraction of cells that actually hold a star.
uniform float density : hint_range(0.0, 1.0) = 0.5;
uniform vec4 star_color : source_color = vec4(1.0, 0.98, 0.94, 1.0);
uniform float brightness : hint_range(0.0, 3.0) = 1.0;
uniform float twinkle_speed : hint_range(0.0, 4.0) = 0.8;
// Decorrelates twinkle + star pattern between stacked layers.
uniform float seed = 0.0;

float hash21(vec2 p) {
	p += seed;
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash22(vec2 p) {
	p += seed;
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

void fragment() {
	vec2 cell_pos = UV * cells_across;
	vec2 id = floor(cell_pos);
	vec2 gv = fract(cell_pos) - 0.5;

	float present = hash21(id);
	if (present > density) {
		COLOR = vec4(0.0);
	} else {
		vec2 star_pos = (hash22(id + 3.7) - 0.5) * 0.7; // jitter within the cell
		float d = length(gv - star_pos);
		// Skew toward dim so a few stars read as bright standouts, not a uniform field.
		float mag = mix(0.35, 1.0, pow(hash21(id + 7.3), 2.0));
		float size = mix(0.03, 0.1, mag);

		float core = smoothstep(size, 0.0, d);
		float halo = smoothstep(size * 5.0, 0.0, d) * 0.25;
		float twinkle = 0.7 + 0.3 * sin(TIME * twinkle_speed + present * 6.2831);
		float a = clamp((core + halo) * mag * twinkle * brightness, 0.0, 1.0);
		COLOR = vec4(star_color.rgb, 1.0) * a;
	}
}

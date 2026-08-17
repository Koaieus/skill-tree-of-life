shader_type canvas_item;
render_mode blend_add;

// One tileable star layer, drawn transparent-with-additive so several of these
// stack over the nebula/base without occluding each other. It draws in its own
// local UV (0..1 across the host tile) and emits identical output for every
// copy, so the Parallax2D that hosts it can `repeat_size`-tile it across the
// screen seamlessly and scroll it for parallax — no camera uniforms here, the
// parallax lives entirely in the Parallax2D node.
//
// NOTE: the host Sprite2D must use a REAL texture (GradientTexture2D), not a
// PlaceholderTexture2D — a placeholder has no image data and collapses the
// sprite's UVs to a constant, which starves this shader of its UV gradient and
// renders the whole field as sub-pixel moiré dust (issue #157).
//
// Stars emit real HDR color (rgb can exceed 1.0) and let the shared root
// WorldEnvironment's bloom pass (ui/theme/default_game_env.tres) build the
// aura — no hand-faked wide-radius smoothstep here. `brightness` is EV stops,
// same `pow(2.0, stops)` lift as ui/tooltip_fan/slab_panel.gdshader's
// hot_tint (see docs/domain/hdr-color.md); star_color should stay near-white
// so the lift reads as a clean magnitude, not a hue shift.

// Star grid cells across the tile. Higher = denser/smaller-spaced stars.
// Must be a whole number — the 3x3 neighbor wrap below assumes integer cells.
uniform float cells_across : hint_range(4.0, 64.0) = 24.0;
// Fraction of cells that actually hold a star.
uniform float density : hint_range(0.0, 1.0) = 0.13;
uniform vec4 star_color : source_color = vec4(1.0, 0.98, 0.94, 1.0);
// EV stops the star's peak color is lifted by (linear rgb *= 2^stops). >0
// pushes a near-white star's rgb above 1.0 so it actually clears the shared
// glow_hdr_threshold; a value of 0 is SDR and will never bloom.
uniform float brightness : hint_range(0.0, 8.0) = 2.0;
uniform float twinkle_speed : hint_range(0.0, 4.0) = 0.8;
// Decorrelates twinkle + star pattern between stacked layers.
uniform float seed = 0.0;
// Star core radius in UV-space (0..1 across the tile). On a 1024 px tile
// 0.001 ≈ 1 px. `mag` interpolates between min (dim, common) and max (bright
// standouts). Keep these small: at cells_across=24 a cell is ~43 px, so a star
// should be a few px, well under the ~21 px half-cell.
uniform float star_size_min : hint_range(0.0005, 0.02) = 0.0012;
uniform float star_size_max : hint_range(0.0005, 0.02) = 0.0035;
// Diffraction-spike glint on the brightest standout stars only (mag above
// this fraction of the 0..1 range) — a thin cross rotated to a per-star
// random angle, on its own twinkle rate/phase so it reads as a directional
// glint rather than the core's uniform radial breathing. Deliberately rare:
// spiking every star reads as noise, not standouts.
uniform float spike_threshold : hint_range(0.0, 1.0) = 0.85;
uniform float spike_length_mult : hint_range(1.0, 40.0) = 16.0;
uniform float spike_width_mult : hint_range(0.1, 2.0) = 0.6;

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
	vec2 base_id = floor(cell_pos);

	vec3 rgb_accum = vec3(0.0);
	float a_accum = 0.0;

	// A star's halo can reach into a neighboring cell (and, at the tile's
	// edge, into the cell that wraps to the far side), so sample the full 3x3
	// neighborhood instead of only the fragment's own cell — otherwise every
	// halo gets hard-clipped at its cell wall, which is what read as a
	// tiling/corner cutoff (it's a cell-boundary artifact, not a tile-edge
	// one; it only *looked* corner-specific because identical adjacent tiles
	// repeat the same clipped seam).
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 offset = vec2(float(ox), float(oy));
			// Position stays in the fragment's own continuous space (so
			// distance-to-star is correct across the wrap); the hash lookup
			// wraps the id so the star's identity/jitter/mag are identical
			// no matter which side of the seam it's approached from.
			vec2 cell = base_id + offset;
			vec2 wrapped_id = mod(cell, cells_across);

			float present = hash21(wrapped_id);
			if (present > density) {
				continue;
			}

			vec2 jitter = (hash22(wrapped_id + 3.7) - 0.5) * 0.7;
			vec2 star_uv = (cell + 0.5 + jitter) / cells_across;
			vec2 rel = UV - star_uv;
			float d = length(rel);

			// Skew toward dim so a few stars read as bright standouts, not a
			// uniform field.
			float mag_roll = pow(hash21(wrapped_id + 7.3), 2.0);
			float mag = mix(0.35, 1.0, mag_roll);
			float size = mix(star_size_min, star_size_max, mag);
			float spike_on = step(spike_threshold, mag_roll);
			float spike_reach = size * spike_length_mult * spike_on;
			if (d > max(size, spike_reach)) {
				continue;
			}

			float core = smoothstep(size, 0.0, d);

			// Shimmer rides the HDR magnitude, not alpha — alpha is the fade
			// channel (docs/domain/hdr-color.md), and bloom only reshapes
			// around a pixel's *value*. Animating value here is what lets
			// the bloom aura itself visibly breathe.
			float twinkle = 0.7 + 0.3 * sin(TIME * twinkle_speed + present * 6.2831);
			float magnitude = pow(2.0, brightness) * mag * twinkle;

			// Diffraction spike: a thin cross rotated to a per-star random
			// angle, reaching well past the core. Its own twinkle rate/phase
			// (offset from the core's) makes it flare and fade
			// asymmetrically instead of breathing in lockstep with the disk.
			float spike = 0.0;
			if (spike_on > 0.5) {
				float ang = hash21(wrapped_id + 9.4) * 6.2831;
				float ca = cos(ang);
				float sa = sin(ang);
				vec2 rel_rot = vec2(rel.x * ca + rel.y * sa, -rel.x * sa + rel.y * ca);
				float spike_width = size * spike_width_mult;
				float bar_a = smoothstep(spike_width, 0.0, abs(rel_rot.x)) * smoothstep(spike_reach, 0.0, abs(rel_rot.y));
				float bar_b = smoothstep(spike_width, 0.0, abs(rel_rot.y)) * smoothstep(spike_reach, 0.0, abs(rel_rot.x));
				float spike_twinkle = 0.5 + 0.5 * sin(TIME * twinkle_speed * 1.7 - present * 11.3);
				spike = max(bar_a, bar_b) * spike_twinkle;
			}

			float shape = max(core, spike);
			rgb_accum += star_color.rgb * magnitude * shape;
			a_accum += shape;
		}
	}

	COLOR = vec4(rgb_accum, clamp(a_accum, 0.0, 1.0));
}

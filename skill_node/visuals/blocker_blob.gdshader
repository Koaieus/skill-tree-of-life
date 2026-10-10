shader_type canvas_item;

// Dormant Core null-field blob (#1526): tar-black metaball lobes whose edge
// deforms slowly on TIME (it is dormant), with drifting texture layers and a
// scanline-tear / channel-jitter glitch inside. BlockerVisual draws one quad
// under ONE shared material; per-core values are instance uniforms, so every
// blob batches. Design: docs/domain/dormant-core.md "The look".
//
// The interior layers are plain sampler2D slots read as LUMINANCE masks and
// tinted here, never by their raw colour, so swapping a slot's texture (any
// seamless greyscale or colour texture) needs no code change.

// Quad half-size in blob units (1.0 = the rest blob radius). Must match
// BlockerVisual.QUAD_EXTENT.
const float QUAD_EXTENT = 1.6;
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

// Fused lobes: the tier tell (BlockerVisual.tier_lobes).
instance uniform int lobes = 1;
// Per-node variant in [0, 1): BlockerVisual.seed_for(stable_id).
instance uniform float seed = 0.0;
// Crack stage 0 intact / 1 cracked / 2 shattered (BlockerVisual.CrackStage).
instance uniform float damage = 0.0;

uniform sampler2D layer_a : repeat_enable, filter_linear;
uniform sampler2D layer_b : repeat_enable, filter_linear;
uniform vec4 layer_a_tint : source_color = vec4(0.30, 0.20, 0.55, 1.0);
uniform vec4 layer_b_tint : source_color = vec4(0.08, 0.40, 0.48, 1.0);
uniform float layer_a_scale = 0.7;
uniform float layer_b_scale = 1.3;
uniform vec2 layer_a_scroll = vec2(0.012, 0.005);
uniform vec2 layer_b_scroll = vec2(-0.008, 0.011);
uniform vec4 tar_color : source_color = vec4(0.02, 0.015, 0.035, 1.0);

// Edge deformation: speed of the lobes' drift and how far the rim wobbles.
uniform float deform_speed : hint_range(0.0, 1.0) = 0.15;
uniform float edge_wobble : hint_range(0.0, 0.4) = 0.12;
// Scanline tears + RGB jitter; damage multiplies it.
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.35;
uniform float glitch_rate : hint_range(0.0, 12.0) = 3.0;
// How far lobes drift apart per crack stage (fraction of their rest ring).
uniform float damage_spread : hint_range(0.0, 1.0) = 0.4;
// HDR bleed light, written by BlockerVisual from a named Emissive tier.
uniform vec4 bleed_color : source_color = vec4(0.9, 0.7, 1.4, 1.0);

float hash21(vec2 q) {
	return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453);
}

float lum(vec4 c) {
	return dot(c.rgb, LUMA);
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-5), 0.0, 1.0);
	return length(p - a - ab * h);
}

void fragment() {
	vec4 vcol = COLOR;
	vec2 p = (UV * 2.0 - 1.0) * QUAD_EXTENT;
	float t = TIME * deform_speed;
	float ph = seed * TAU;
	int n = clamp(lobes, 1, 4);
	float nf = float(n);
	float dmg = clamp(damage, 0.0, 2.0);

	// Rest layout: one round lobe; two a peanut; three a trefoil.
	float lobe_r = n == 1 ? 0.9 : (n == 2 ? 0.6 : 0.52);
	float ring = n == 1 ? 0.06 : (n == 2 ? 0.45 : 0.5);
	ring *= 1.0 + dmg * damage_spread;
	lobe_r *= 1.0 - 0.1 * dmg;

	// Slow edge wobble from layer_b's luminance, scrolled on the drift clock.
	float wob = lum(texture(layer_b, p * 0.3 + vec2(t, -0.7 * t) + seed * 3.1)) - 0.5;

	float f = 0.0;
	vec2 centres[4];
	for (int i = 0; i < 4; i++) {
		if (i >= n) {
			break;
		}
		float fi = float(i);
		float ang = ph + TAU * fi / nf + 0.3 * sin(t * 1.3 + fi * 2.1 + ph);
		float rr = ring * (1.0 + 0.15 * sin(t * 0.9 + fi * 1.7 + ph));
		vec2 c = vec2(cos(ang), sin(ang)) * rr;
		centres[i] = c;
		float r = lobe_r * (1.0 + 0.06 * sin(t * 1.7 + fi * 1.3 + ph));
		vec2 d = p - c;
		f += r * r / max(dot(d, d), 1e-4);
	}
	f *= 1.0 + edge_wobble * 2.0 * wob;

	// Goo strands stretch between lobes once they drift apart.
	float strand = 0.0;
	if (n > 1 && dmg > 0.0) {
		for (int i = 0; i < 4; i++) {
			if (i >= n) {
				break;
			}
			int j = (i + 1) % n;
			if (n == 2 && i == 1) {
				break;
			}
			float w = 0.07 * (1.0 + 0.4 * sin(t * 2.3 + float(i) + ph)) / (0.6 + 0.4 * dmg);
			strand = max(strand, 1.0 - seg_dist(p, centres[i], centres[j]) / w);
		}
	}
	if (strand > 0.0) {
		f = max(f, 1.0 + strand * 0.6);
	}

	// Glitch: torn scanlines shift sideways on a stepped clock.
	float rows = 22.0;
	float row = floor(p.y * rows);
	float tick = floor(TIME * glitch_rate + seed * 17.0);
	float g = glitch_intensity * (1.0 + 0.6 * dmg);
	float tear = step(1.0 - 0.2 * g, hash21(vec2(row, tick)));
	vec2 gp = p;
	gp.x += tear * (hash21(vec2(row + 7.0, tick)) - 0.5) * 0.4;
	// Pixel-sort shimmer: a torn row smears into blocks.
	gp.x = mix(gp.x, floor(gp.x * 6.0) / 6.0, tear * step(0.5, hash21(vec2(tick, row))));

	vec2 uva = gp * layer_a_scale + layer_a_scroll * TIME + seed * 3.7;
	vec2 uvb = gp * layer_b_scale + layer_b_scroll * TIME + seed * 5.3;
	float jit = 0.015 * g;
	vec3 ma = vec3(
		lum(texture(layer_a, uva + vec2(jit, 0.0))),
		lum(texture(layer_a, uva)),
		lum(texture(layer_a, uva - vec2(jit, 0.0))));
	float mb = lum(texture(layer_b, uvb));

	vec3 col = tar_color.rgb;
	col += layer_a_tint.rgb * ma * ma * 1.4;
	col += layer_b_tint.rgb * smoothstep(0.55, 0.85, mb);
	col *= 0.88 + 0.12 * sin(p.y * 90.0 + TIME * 0.5);
	col = mix(col, layer_b_tint.rgb * 1.6, tear * 0.35);

	// Fractures: thin ridges of layer_a open on damage, bleeding light.
	float crack_n = lum(texture(layer_a, p * 0.45 + seed * 9.1));
	float crack = dmg > 0.0 ? 1.0 - smoothstep(0.0, 0.018 * dmg, abs(crack_n - 0.5)) : 0.0;
	// The rim glows faintly, more as it fractures.
	float rim = 1.0 - smoothstep(1.0, 1.6, f);
	col = mix(col, bleed_color.rgb, clamp(crack * 0.8 + rim * (0.08 + 0.12 * dmg), 0.0, 1.0));

	float aa = max(fwidth(f), 1e-4);
	float body = smoothstep(1.0 - aa, 1.0 + aa, f);
	// A fractured edge: cracks bite notches out of the silhouette.
	body *= 1.0 - crack * smoothstep(1.6, 1.0, f);
	// Bleed halo just outside the edge, only once damaged.
	float halo = dmg * 0.18 * smoothstep(0.55, 1.0, f) * (1.0 - body);
	col = mix(bleed_color.rgb, col, body / max(body + halo, 1e-4));

	COLOR = vec4(col * vcol.rgb, clamp(body + halo, 0.0, 1.0) * vcol.a);
}

shader_type canvas_item;

// #125 — the ring is drawn continuously from inner_r (pit/disc edge) to
// outer_r (rim): flat floor from inner_r up to crest_r, then a REAL
// height(radius) bumpmap bevel from crest_r to outer_r, lit the same way as
// inner_disk.gdshader (shared LIGHT_DIR) so the disk and its rim read as
// lit from one source. crest_r is an *interior* control point, not a draw
// boundary — RimRing knows nothing about the disk underneath it, just its
// own inner/outer band and where the bevel starts inside that band.
//
// The 4 locked presets (level/terrace/smooth/sharpen) are closed-form
// functions of the normalized bevel domain, selected by `height_preset` —
// that keeps them out of a Curve resource entirely, so every rim_ring on a
// built-in preset shares ONE ShaderMaterial via `instance uniform`s
// (batches into one draw call).
//
// A genuinely custom (5th/6th profile) Curve can't ride an instance
// uniform — samplers aren't allowed there — so rim_ring.gd falls back to a
// per-instance material + a small baked LUT texture for that case
// (height_preset == 4), an intentional, documented, opt-in cost. See
// skill_node/visuals/rim_ring.gd.
//
// Light math (sn_light_dir / sn_diffuse) is shared with inner_disk.gdshader via
// lighting.gdshaderinc so the disk and its rim can never drift onto two lights.
//
// #341 — the allocation dial, folded in as a 7th instance uniform. Reclaims
// the shelved RimBonuses stake-fill dial's SEMANTICS (current/max, evenly
// gapped slots, 0/* draws nothing, M==N==1 is one gapless ring) as a term in
// THIS shader rather than a separate CanvasItem, because at the ~99% common
// case (stake_level == allocation_level == 1) the dial's lit ring and this
// rim's own emissive band are literally the same pixels — see
// .claude/rules/skill-node-visuals.md. NO SPIN: the shelved version animated
// only to hide a parked asymmetric fixed-start-angle arc; anchoring the lit
// slots at 12 o'clock and growing them outward symmetrically (rim_fill_lit
// below) fixes that artifact directly, so there's nothing left for a clock to
// paper over. Do not reintroduce TIME/fill_spin here.

#include "res://skill_node/visuals/lighting.gdshaderinc"
// #414 — see the same block in inner_disk.gdshader. Alpha, not RGB: an alpha
// fade matches what `modulate.a` was reaching for AND leaves the fill dial's
// HDR emissive tier (`fill_glow_strength`, #389) above the 1.0 bloom
// threshold, which scaling the colour down would quietly extinguish.
#include "res://ui/vision_field.gdshaderinc"

varying vec2 world_pos;

instance uniform float inner_r = 24.0;
instance uniform float crest_r = 28.0;
instance uniform float outer_r = 32.0;
instance uniform vec4 ring_tint : source_color = vec4(0.65, 0.67, 0.72, 1.0);
instance uniform int height_preset = 0; // 0 level, 1 terrace, 2 smooth, 3 sharpen, 4 custom (height_lut), 5 mesa
// (fill_current, fill_max) — the ONE new instance uniform this fold adds
// (6 -> 7 of 16). Everything else the dial needs (gap width, glow strength,
// crest bias) is a plain global uniform below: no node varies them.
instance uniform vec2 fill_slots = vec2(0.0, 1.0);

// Only bound (and only sampled) for height_preset == 4, on that instance's
// own per-instance material — see rim_ring.gd::_sync_material.
uniform sampler2D height_lut;

// #130 — matches inner_disk.gdshader's highlight_position instance uniform
// (same xy, same fixed z=0.65) instead of a private hardcoded constant, so
// the composite can drive both from the ONE InnerDisk value and the disk +
// rim never drift onto two different light sources.
instance uniform vec2 light_dir_xy = vec2(-0.35, -0.35);

// #341 dial tuning — global, not per-node (no node varies these): the gap
// between slots, the additive glow's strength, and how sharply it favors the
// crest over the rest of the band.
uniform float fill_gap_deg : hint_range(0.0, 60.0) = 12.0;
uniform float fill_glow_strength : hint_range(0.0, 6.0) = 1.5; // was: 0.85;
uniform float fill_crest_bias : hint_range(0.25, 6.0) = .25; // was: 2.0;

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

// Rise, hold, fall — the bevel climbs to full height fast (~t 0.23), plateaus,
// then rolls back off to zero at the outer edge (~t 0.83), giving the rim a
// rounded outer lip instead of the hard shoulder every other preset ends on.
//
// This is the EXACT closed form of `rim_ring_curve.tres`, which every node in
// the game used to carry as a CUSTOM curve. That Curve is two points at y=0
// with tangents +5.5699086 / -5.8854437; expanding the cubic Hermite for
// p0 = p1 = 0 gives h(t) = m0*t + (-2*m0 - m1)*t^2 + (m0 + m1)*t^3, and
// `_bake_lut` clamps the result to [0,1] — hence the clamp here. Verified
// against `Curve.sample()` at 65 points: exact to float precision outside the
// clamped plateau, and better than the 64-texel LUT inside it.
//
// Baking it as a preset is what returns those nodes to the shared material:
// the CUSTOM path mints a private ShaderMaterial + ImageTexture per instance,
// which at 500-2500 nodes meant one draw call per rim. See rim_ring.gd.
float height_mesa(float t) {
	return clamp(t * (5.5699086 + t * (-5.2543735 + t * -0.3155351)), 0.0, 1.0);
}

float sample_bevel(float local_t) {
	local_t = clamp(local_t, 0.0, 1.0);
	float h = height_level(local_t);
	h = mix(h, height_terrace(local_t), float(height_preset == 1));
	h = mix(h, height_smooth(local_t), float(height_preset == 2));
	h = mix(h, height_sharpen(local_t), float(height_preset == 3));
	h = mix(h, texture(height_lut, vec2(local_t, 0.5)).r, float(height_preset == 4));
	h = mix(h, height_mesa(local_t), float(height_preset == 5));
	return h;
}

// Height across the WHOLE inner_r..outer_r band: flat floor up to the
// crest, then the bevel preset from crest to outer_r.
float sample_height(float t, float tc) {
	float span_after_crest = max(1.0 - tc, 0.0001);
	float local_t = (t - tc) / span_after_crest;
	return mix(0.0, sample_bevel(local_t), step(tc, t));
}

// Allocation dial (#341): additive lit-slot mask, computed directly from
// (fill_current, fill_max) — no CPU precompute, nothing beyond fill_slots
// itself. Slots are evenly gapped around the FULL circle with slot 0 CENTERED
// AT 12 O'CLOCK (p_ang == 0 there), so the layout is bilaterally symmetric
// about the vertical axis by construction — not filled contiguously from a
// fixed start angle (that was the shelved version's artifact).
//
// For odd N there's one slot exactly at top (self-mirrored) plus symmetric
// pairs either side of it. For even N there's ALSO one exactly at bottom
// (self-mirrored too — unavoidable once N is even, since top and bottom are
// always exactly N/2 slots apart on the grid) alongside its own symmetric
// pairs. That means realizing an arbitrary M (not just even M) while staying
// mirror-symmetric needs a small preference order over {top alone, pure
// pairs, both singles, bottom alone} rather than a single nested growth
// sequence — a strictly nested "add the next-nearest symmetric unit" walk
// provably skips some M for N >= 3 (e.g. N=3, prefix growth top(1)->pair(3)
// never passes through 2; N=4's top->pair->bottom prefix skips 2 the same
// way). The four combos below are searched in the order that keeps "M lit,
// centered up, growing outward" the visual read for the common small M, while
// still landing on SOME valid symmetric set for every M in [0, N]. See
// .claude/rules/skill-node-visuals.md for the worked derivation.
//
// `0/*` (p_slots.x < 1) returns 0 everywhere — no ring, no outline, nothing.
// `M == N == 1` is the gapless special case: one full unbroken lit ring.
float rim_fill_lit(float p_ang, vec2 p_slots, float p_gap_deg) {
	float m = p_slots.x;
	float n = p_slots.y;
	if (m < 0.5 || n < 0.5) {
		return 0.0;
	}
	if (n < 1.5) {
		return 1.0;
	}

	float w = TAU / n;
	float idx = round(p_ang / w);
	float delta = p_ang - idx * w;
	float gap_rad = radians(p_gap_deg);
	float half_body = max(w - gap_rad, 0.0) * 0.5;
	float in_body = 1.0 - smoothstep(half_body - 0.02, half_body + 0.02, abs(delta));
	if (in_body <= 0.0) {
		return 0.0;
	}

	float k = mod(idx, n);             // canonical slot index, 0..N-1
	float n_even = 1.0 - mod(n, 2.0);  // 1 if N even, 0 if odd
	float singles = 2.0 - mod(n, 2.0); // self-mirrored slots: 1 (odd N, top only) or 2 (even N, top+bottom)
	float pair_count = (n - singles) * 0.5;
	float rank = min(k, n - k);        // 0 = top; N/2 = bottom (even only); else a mirror-pair's shared rank

	float lit_top = 0.0;
	float lit_bot = 0.0;
	float lit_pairs = 0.0;
	float resolved = 0.0;

	// combo 1: top alone + p nearest pairs
	if (resolved < 0.5) {
		float rem = m - 1.0;
		float p_needed = rem * 0.5;
		if (rem > -0.5 && mod(rem, 2.0) < 0.5 && p_needed <= pair_count + 0.01) {
			lit_top = 1.0;
			lit_pairs = max(p_needed, 0.0);
			resolved = 1.0;
		}
	}
	// combo 2: no singles, p nearest pairs only
	if (resolved < 0.5) {
		float p_needed = m * 0.5;
		if (mod(m, 2.0) < 0.5 && p_needed <= pair_count + 0.01) {
			lit_pairs = p_needed;
			resolved = 1.0;
		}
	}
	// combo 3 (even N only): both singles + p nearest pairs
	if (resolved < 0.5 && n_even > 0.5) {
		float rem = m - 2.0;
		float p_needed = rem * 0.5;
		if (rem > -0.5 && mod(rem, 2.0) < 0.5 && p_needed <= pair_count + 0.01) {
			lit_top = 1.0;
			lit_bot = 1.0;
			lit_pairs = max(p_needed, 0.0);
			resolved = 1.0;
		}
	}
	// combo 4 (even N only): bottom alone + p nearest pairs — last resort
	if (resolved < 0.5 && n_even > 0.5) {
		float rem = m - 1.0;
		float p_needed = rem * 0.5;
		if (rem > -0.5 && mod(rem, 2.0) < 0.5 && p_needed <= pair_count + 0.01) {
			lit_bot = 1.0;
			lit_pairs = max(p_needed, 0.0);
			resolved = 1.0;
		}
	}

	bool is_top_slot = k < 0.5;
	bool is_bottom_slot = n_even > 0.5 && abs(k - n * 0.5) < 0.5;
	float lit;
	if (is_top_slot) {
		lit = lit_top;
	} else if (is_bottom_slot) {
		lit = lit_bot;
	} else {
		lit = step(rank, lit_pairs + 0.01);
	}
	return lit * in_body;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}


void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * outer_r;
	float r = length(p);
	float span = max(outer_r - inner_r, 0.0001);
	float t = clamp((r - inner_r) / span, 0.0, 1.0);
	float tc = clamp((crest_r - inner_r) / span, 0.0, 1.0);

	float eps = 0.015;
	float h0 = sample_height(t - eps, tc);
	float h1 = sample_height(t + eps, tc);
	float slope = (h1 - h0) / (2.0 * eps);

	vec2 radial_dir = r > 0.0001 ? p / r : vec2(0.0, 1.0);
	vec3 normal = normalize(vec3(-radial_dir * slope, 1.0));
	vec3 light_dir = sn_light_dir(light_dir_xy);
	float diffuse = sn_diffuse(normal, light_dir);
	// #341 — lifted ambient floor (was 0.35 + 0.65 * diffuse): the archetype
	// hue needs to survive even at low diffuse (unallocated, poorly lit
	// facets) to stay identifiable from the rim alone.
	// HDR-2D retune (2026-08-05): heavily lowered floor so the unallocated
	// neutral rim reads as a quiet muted-silver outline against the (now-HDR)
	// viewport — the inner disk is intentionally much darker than the rim,
	// so the silhouette still reads. Factor peaks at 0.16 (diffuse=1);
	// ring_tint is source_color-linearized (~0.48 for neutral silver) so
	// peak linear ≈0.077 → sRGB display ≈0.30. Allocated-arc additive
	// (`lit > 0.0` block below) is untouched.
	vec3 shaded = ring_tint.rgb * (0.08 + 0.08 * diffuse);

	// Allocation dial (#341): additive across the WHOLE band (inner_r ..
	// outer_r), strongest at the crest — not confined to the flat floor or
	// the bevel. Peaks at t == tc, falls off toward whichever band edge is
	// farther from the crest.
	float ang = atan(p.x, -p.y); // 0 == 12 o'clock, mirrors left/right by construction
	float lit = rim_fill_lit(ang, fill_slots, fill_gap_deg);
	if (lit > 0.0) {
		float dist_from_crest = abs(t - tc);
		float dist_max = max(max(tc, 1.0 - tc), 0.0001);
		float radial_w = pow(clamp(1.0 - dist_from_crest / dist_max, 0.0, 1.0), max(fill_crest_bias, 0.001));
		// #389 — alert-tier bloom (docs/domain/hdr-color.md). fill_glow_strength
		// (0..2) IS the stop count, so this is Emissive.at(ring_tint, stops) done
		// by hand: ring_tint.rgb arrives already srgb_to_linear()'d (the
		// `source_color` hint auto-decodes it), so multiplying by pow(2, stops)
		// reproduces that helper's `base.srgb_to_linear() * 2^stops` exactly —
		// COLOR is already linear here (hdr_2d=true), so no re-encode is needed.
		// At peak (lit==1, radial_w==1, fill_glow_strength==2.0/ALERT) a white
		// ring_tint lands at linear 4.0, i.e. Color(1.825, 1.825, 1.825) once the
		// renderer re-encodes it for display. lit * radial_w falls off to 0, so
		// an unlit or off-crest pixel gets none of this term — only the ambient
		// SDR floor above.
		shaded += ring_tint.rgb * (pow(2.0, fill_glow_strength) * lit * radial_w);
	}

	float inside = step(inner_r, r) * step(r, outer_r);
	float edge_soft = smoothstep(inner_r - 0.75, inner_r + 0.75, r) * (1.0 - smoothstep(outer_r - 0.75, outer_r + 0.75, r));
	COLOR = vec4(shaded, ring_tint.a * edge_soft * inside * vision_field_dim(world_pos));
}

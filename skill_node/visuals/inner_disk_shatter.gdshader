shader_type canvas_item;

// InnerDisk shatter shard (#257): the node-death fragmentation look for #835's
// `ShatterField`. Re-runs the SAME dome body the live node draws
// (`inner_disk_body.gdshaderinc`) inside each Voronoi cell #835 cuts the disc
// into, so there is no photographed texture to keep in sync — see #257's
// acceptance decision 2 ("there is NO texture capture, no SubViewport, and no
// cache").
//
// The crescendo (decision 1): every shard in one shatter shares an identical,
// UN-rotated quad until `shatter_flight_start` (p0) — see
// `shatter_motion.gdshaderinc`, spin/displacement are both zero pre-p0 — so
// while `prog < p0` every shard draws the SAME full intact dome on top of each
// other (deliberate overdraw, `.claude/rules/rendering-performance.md`) with
// glowing cracks overlaid at the seams. At p0 the render swaps to each shard's
// OWN Voronoi cell and the piece flies per `shatter_motion.gdshaderinc`'s
// curve, blooming at release and fizzling out (`shatter_fade`, #871).
// `shatter_seam_distance()` is the ONE seam authority for cracks, the cell
// split AND the beams, so the disc breaks along the cracks it was showing
// (#257 acceptance 4).
//
// The crescendo is an earth's-crust read (#871, reopened): the cracks light
// up (`crack_glow_stops`), their light bleeds across the dome around them
// (`crack_spill_width`), and LATE in the phase (`ray_onset`) light beams
// fire out of the cracks — rooted inside the disc on the seam
// (`ray_root`), through the rim, reaching `ray_length` past it at the burst.
// The beams are anchored to the cracks and gated off with the intact disc,
// so they never light the rim as a ring and never outlive the release —
// which is what #257's rim-anchored, flight-long "supernova rays" did (the
// "rim glows / ~10 bursts along the rim" read the first #871 fix removed).
// The rim is the live node's and stays itself; the beams simply draw over
// whatever surrounds the disc (`ZLayers.SPELL_VFX`).
#include "res://ui/vfx/shatter/shatter_motion.gdshaderinc"
#include "res://skill_node/visuals/inner_disk_body.gdshaderinc"

// --- Look, authored on this material (`inner_disk_shatter_material.tres`,
// which MUST be `resource_local_to_scene = true` — see ShatterField's class
// docs and `.claude/rules/hdr-color.md` for the tiers cited below) ---

// Disk-space half-width of a glowing crack seam, pre-explosion.
uniform float crack_width : hint_range(0.001, 0.3) = 0.06;
// EV stops a crack glows above its base tint at crescendo peak (the instant
// before the disc lets go). Emissive.ALERT (2.0) — "full neon", appropriate
// for a disc about to come apart.
uniform float crack_glow_stops : hint_range(0.0, 6.0) = 3.0;
// Disk-space reach of a lit crack's light bleeding across the dome around it
// at crescendo peak — the halo grows with the crescendo from nothing to this.
// Bloom alone can't supply it: at a live node's ~24px radius a `crack_width`
// seam is one pixel wide and throws no visible halo (#871, reopened).
uniform float crack_spill_width : hint_range(0.0, 1.0) = 0.25;

// --- Crack beams (#871, reopened) — pushed by AllocationVFX, see
// `shatter_ray_tier` / `shatter_ray_onset` there ---
//
// EV stops a beam peaks at, the instant before the disc lets go.
// Emissive.PEAK (3.0) — the ignition-flash read.
uniform float ray_stops : hint_range(0.0, 8.0) = 3.0;
// Fraction of the crack phase the cracks light on their own before beams
// start — `shatter_ray_ramp()`'s onset.
uniform float ray_onset : hint_range(0.0, 1.0) = 0.55;
// Angular tolerance (in the seed-distance units `shatter_seam_distance`
// returns, evaluated on the disc's rim) a beam fans out from its crack.
uniform float ray_angle_width : hint_range(0.01, 1.0) = 0.08;
// How far past the disc rim (disc-radius units) a beam reaches at its peak.
// The shard quad is `SHATTER_OVERSIZE` (2x) the disc, so at most 1.0.
uniform float ray_length : hint_range(0.1, 1.0) = 0.8;
// Disc radius a beam takes root at, inside the disc on its crack — it grows
// from here through the rim, so the beam visibly comes OUT of the crack.
uniform float ray_root : hint_range(0.0, 1.0) = 0.55;

// --- Identity tint rides COLOR, never a uniform ---
//
// #835 decision 6: per-shatter data that VARIES (different dying nodes have
// different owners) has to ride per-instance `COLOR`/`INSTANCE_CUSTOM`, never
// a material uniform — a MultiMesh's instances share one CanvasItem, and this
// field pools shatters from possibly-different-coloured nodes over time.
// `ShatterField.spawn_shatter` writes `COLOR = Emissive.at(tint, spawn_tier)`;
// AllocationVFX pins `spawn_tier` to `Emissive.Tier.INERT` (0 stops) so that
// lift is the identity and `COLOR` IS the node's plain SDR tint — which is
// what makes the intact-disc phase pixel-match `inner_disk.gdshader`'s own
// `instance uniform tint_color` (#257 acceptance 2). The crack-glow HDR boost
// below is applied explicitly on top via `exp2(...)`; the shards' own
// release bloom is `shatter_motion.gdshaderinc`'s `shard_bloom_stops`.

// --- Per-node dome look — PLAIN uniforms, not `instance uniform`s. A
// MultiMesh's instances share one CanvasItem (#835 decision 6), so nothing
// here CAN vary per shard — but one shatter is one dying node, so one look
// for the whole field is correct for everything that isn't identity tint.
// Same simplification `blade_shard.gdshader` makes for `inner_frac`: "most
// [source nodes] share one ratio, and there is no spare INSTANCE_CUSTOM
// channel to carry a per-shard one." Defaults mirror `inner_disk.gdshader`'s
// `instance uniform` set 1:1 — except the carve, which DOES vary per dying
// node (it is the node's glyph) and so rides the data texture below.
uniform float tint_mix : hint_range(0.0, 1.0) = 0.6;
// A force-deallocated node was, by definition, allocated — always true here,
// never pushed per-shard.
uniform bool allocated = true;
uniform vec2 highlight_position = vec2(-0.35, -0.35);
uniform float highlight_intensity : hint_range(0.0, 1.0) = 0.85;

// --- Per-shatter carve (#843) — a data texture read at INSTANCE_ID ---
//
// A dying node keeps its glyph: `ShatterField` writes each slot's
// `CarveParams` (the 7-tuple the live disc reads as instance uniforms) as two
// RGBAF texels at `x = INSTANCE_ID * 2 (+1)`, since INSTANCE_CUSTOM has no
// channel left. Layout is `CarveParams.to_texels()`'s; 32-bit floats, so the
// kind and slice integers are exact. Read once per vertex into flat varyings.
// The samplers the tuple indexes into — `gem_lut` and the one shared
// `carve_atlas` — stay plain uniforms, bound by AllocationVFX from InnerDisk's
// own shared ones. Still one draw call.
uniform sampler2D shatter_carve_tex : filter_nearest;
uniform sampler2D gem_lut : filter_linear_mipmap, hint_default_black;
uniform sampler2DArray carve_atlas : filter_linear_mipmap;

varying flat int v_carve_kind;
varying flat vec3 v_carve_shape; // sides, squish, radius
varying flat float v_well_depth;
varying flat ivec2 v_carve_slices; // slice, slice_b

void vertex() {
	SHATTER_VERTEX;
	vec4 carve_a = texelFetch(shatter_carve_tex, ivec2(INSTANCE_ID * 2, 0), 0);
	vec4 carve_b = texelFetch(shatter_carve_tex, ivec2(INSTANCE_ID * 2 + 1, 0), 0);
	v_carve_kind = int(round(carve_a.x));
	v_carve_shape = carve_a.yzw;
	v_well_depth = carve_b.x;
	v_carve_slices = ivec2(round(carve_b.yz));
}

// Crack glow, 0..1: 0 at spawn, rising to 1 as `prog` reaches p0 — and gone
// from p0 on, when the intact disc stops being drawn and only shards remain.
// `AllocationVFX.crack_glow_at` is the CPU reference of this exact formula;
// keep the two in lockstep (#871).
float shatter_crescendo(float prog) {
	float p0 = shatter_flight_start;
	if (prog >= p0) {
		return 0.0;
	}
	return clamp(prog / p0, 0.0, 1.0);
}

// Beam ramp, 0..1: 0 until the crescendo reaches `ray_onset`, smoothly up to
// 1 at p0, and gone from p0 on with the intact disc. The `crescendo` factor
// keeps it pointwise <= `shatter_crescendo` (a bare smoothstep overshoots a
// line near 1) — a beam never leads its own crack.
// `AllocationVFX.ray_glow_at` is the CPU reference of this exact formula;
// keep the two in lockstep (#871).
float shatter_ray_ramp(float prog) {
	float p0 = shatter_flight_start;
	if (prog >= p0) {
		return 0.0;
	}
	float crescendo = clamp(prog / p0, 0.0, 1.0);
	return crescendo * smoothstep(ray_onset, 1.0, crescendo);
}

// A crack's beam at `p`, 0..1: this fragment's angle projected onto the rim
// so a beam points straight out through its own crack (the seam it meets the
// rim at), rooted at `ray_root` inside the disc, at full strength on the rim,
// and fading to nothing `ray_length * ramp` past it — the beam grows OUT of
// the crack as the crescendo builds.
float shatter_ray(vec2 p, float r, ShatterShard s, float ramp) {
	if (ramp <= 0.0) {
		return 0.0;
	}
	vec2 rim_dir = p / max(r, 0.0001);
	float rim_seam = abs(shatter_seam_distance(rim_dir, s));
	float reach = 1.0 + ray_length * ramp;
	// 0 on the rim, 1 at the beam's tip.
	float out_t = clamp((r - 1.0) / max(reach - 1.0, 0.0001), 0.0, 1.0);
	// A needle, not a sausage: the beam narrows toward its tip and its
	// strength falls off quadratically, so the tip dissolves.
	float width = ray_angle_width * mix(1.0, 0.25, out_t);
	float shape = smoothstep(width, 0.0, rim_seam);
	float inner = smoothstep(ray_root, 1.0, r);
	float outer = (1.0 - out_t) * (1.0 - out_t);
	return shape * min(inner, outer) * ramp;
}

// A beam's colour at strength `ray`: the tint lifted toward `ray_stops` by
// the beam's own strength, so the root is the ignition flash and the tip
// relaxes back to the crack's own colour.
vec3 shatter_ray_color(vec4 tint, float ray) {
	return tint.rgb * exp2(ray_stops * ray);
}

vec3 shatter_dome(vec2 p, vec4 tint) {
	return sn_inner_disk_shade(p, tint, tint_mix, allocated, highlight_position,
			highlight_intensity, v_carve_kind, v_carve_shape.x, v_carve_shape.y,
			v_carve_shape.z, v_well_depth, v_carve_slices.x, v_carve_slices.y, gem_lut,
			carve_atlas);
}

void fragment() {
	// Captured before COLOR is overwritten below — see the "Identity tint"
	// header comment.
	vec4 tint = COLOR;
	ShatterShard s = shatter_shard();
	float prog = shatter_progress(s);
	bool intact = prog < shatter_flight_start;
	float crescendo = shatter_crescendo(prog);
	float ray_ramp = shatter_ray_ramp(prog);
	vec2 p = shatter_unspin(shatter_disc_point(), s, prog);
	float r = length(p);

	// Godot's canvas_item fragment() cannot `return` early (SHADER ERROR:
	// "Using 'return' in the 'fragment' processor function is incorrect."),
	// so the regions are one if/else-if chain rather than guard clauses —
	// see `.claude/rules/godot-shaders.md`.
	if (r <= 1.0 && intact) {
		// No shard has moved yet (#257 acceptance 3) — every shard's quad is
		// still the same un-rotated, un-displaced square, so drawing the
		// WHOLE dome here (not gated by this shard's own cell) is what makes
		// progress=0 read as one intact disc, indistinguishable from the
		// live InnerDisk (#257 acceptance 2).
		vec3 dome = shatter_dome(p, tint);
		float seam = abs(shatter_seam_distance(p, s));
		float glow = smoothstep(crack_width, 0.0, seam) * crescendo;
		// The crack's own light bleeding over the dome: a soft halo that
		// widens with the crescendo, quadratic so the seam core stays the
		// brightest line in it.
		float spill_reach = max(crack_spill_width * crescendo, crack_width);
		float spill = smoothstep(spill_reach, 0.0, seam);
		spill = spill * spill * spill * crescendo;
		vec3 rgb = mix(dome, tint.rgb * exp2(crack_glow_stops), max(glow, spill));
		// The beam's root, drawn over the dome from `ray_root` out to the rim.
		float ray = shatter_ray(p, r, s, ray_ramp);
		rgb = mix(rgb, shatter_ray_color(tint, ray), ray);
		float r2 = dot(p, p);
		float edge_alpha = 1.0 - smoothstep(0.96, 1.0, r2);
		COLOR = vec4(rgb, edge_alpha);
	} else if (r <= 1.0) {
		// Came apart: only this fragment's own Voronoi cell draws — same
		// seeds the crack above just showed (#257 acceptance 4).
		float margin = shatter_cell_margin(p, s);
		if (margin < 0.0) {
			discard;
		}
		// `shatter_fade` carries the release bloom (#871): the piece lights
		// up as it lets go, then dims and fades out across its flight.
		vec3 dome = shatter_dome(p, tint);
		float seam_aa = max(fwidth(margin), 0.0001);
		float rim_aa = max(fwidth(r), 0.0001);
		float shape = smoothstep(0.0, seam_aa, margin) * (1.0 - smoothstep(1.0 - rim_aa, 1.0, r));
		COLOR = shatter_fade(vec4(dome, shape), prog);
	} else if (intact && s.cell == 0) {
		// Outside the disc, still intact: only a crack's beam, firing out
		// through the seam it meets the rim at — nothing else, and nothing
		// at all once the disc has let go. The rim is the live node's own
		// and stays as it was (#871); the beam just draws over it.
		// Drawn by ONE shard only: pre-p0 every shard's quad covers the same
		// area and sees every seed, and the beam's alpha is its falloff —
		// N shards alpha-blending the same beam would compound it to
		// `1 - (1 - ray)^N` and re-grow the fat rim halo (the inside-the-disc
		// overdraw is harmless, it is opaque over opaque).
		float ray = shatter_ray(p, r, s, ray_ramp);
		if (ray <= 0.0) {
			discard;
		}
		COLOR = vec4(shatter_ray_color(tint, ray), ray);
	} else {
		// Shards in flight draw nothing past the disc — no rays, no bursts.
		discard;
	}
}

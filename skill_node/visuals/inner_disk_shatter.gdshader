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
// `shatter_seam_distance()` is the ONE seam authority for cracks AND the cell
// split, so the disc breaks along the cracks it was showing (#257
// acceptance 4). Nothing draws outside the disc: #257's "supernova rays"
// past the rim were the rim-glow / rim-burst read #871 removed — the rim is
// the live node's, and it stays dark through a death.
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
uniform float crack_glow_stops : hint_range(0.0, 6.0) = 2.0;

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
// `instance uniform` set 1:1. `carve_kind` stays NONE (0) — the honest empty
// dome InnerDisk itself falls back to — because reaching a dying node's actual
// resolved carve would need a new accessor on `skill_node.gd` /
// `node_visuals_composite.gd`, neither of which #257 owns; noted as a
// follow-up, not silently dropped.
uniform float tint_mix : hint_range(0.0, 1.0) = 0.6;
// A force-deallocated node was, by definition, allocated — always true here,
// never pushed per-shard.
uniform bool allocated = true;
uniform vec2 highlight_position = vec2(-0.35, -0.35);
uniform float highlight_intensity : hint_range(0.0, 1.0) = 0.85;
uniform int carve_kind = 0;
uniform float carve_sides : hint_range(3.0, 16.0, 1.0) = 3.0;
uniform float carve_squish : hint_range(0.3, 1.0, 0.01) = 1.0;
uniform float carve_radius : hint_range(0.4, 1.15, 0.01) = 0.75;
uniform float well_depth : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform sampler2D gem_lut : filter_linear_mipmap, hint_default_black;
uniform sampler2DArray carve_atlas : filter_linear_mipmap;
uniform int carve_slice = -1;
uniform int carve_slice_b = -1;

void vertex() {
	SHATTER_VERTEX;
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

vec3 shatter_dome(vec2 p, vec4 tint) {
	return sn_inner_disk_shade(p, tint, tint_mix, allocated, highlight_position,
			highlight_intensity, carve_kind, carve_sides, carve_squish, carve_radius,
			well_depth, carve_slice, carve_slice_b, gem_lut, carve_atlas);
}

void fragment() {
	// Captured before COLOR is overwritten below — see the "Identity tint"
	// header comment.
	vec4 tint = COLOR;
	ShatterShard s = shatter_shard();
	float prog = shatter_progress(s);
	bool intact = prog < shatter_flight_start;
	float crescendo = shatter_crescendo(prog);
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
		vec3 rgb = mix(dome, tint.rgb * exp2(crack_glow_stops), glow);
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
	} else {
		// Outside the disc: nothing. The rim is the live node's own and stays
		// as it was (#871) — no rays, no bursts.
		discard;
	}
}

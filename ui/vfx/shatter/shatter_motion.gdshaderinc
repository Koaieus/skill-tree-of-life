// ShatterField's motion contract (#835) — the ONE implementation of how a
// shard moves, spins, fades and which piece of the source it is. Every
// consumer shader (#787's blade wedge, #257's InnerDisk shard,
// `shatter_shard.gdshader`'s flat-tint reference) `#include`s this and adds
// only what a fragment inside the cell LOOKS like. Do not fork-and-paste the
// motion: `ui/vfx/shatter/shatter_field.gd` is the CPU-side reference for
// the same curve (`progress_at` / `displacement_at` / `fade_alpha_at` /
// `radial_kick`) and the two must stay in lockstep.
//
// Per-instance data, packed by `ShatterField.spawn_shatter`:
//   COLOR (instance_color)         = the shard's tint, already lifted to its
//                                    spawn tier by `Emissive.at()` (HDR > 1.0
//                                    blooms; `.claude/rules/hdr-color.md`)
//   INSTANCE_CUSTOM (custom_data)  = .xy  velocity in world px/s (parent
//                                         momentum + this shard's radial kick,
//                                         folded on the CPU)
//                                    .z   spawn time, seconds since the
//                                         field's `time_base`
//                                    .w   cell + (cell_count-1)*32
//                                         (see `ShatterField.pack_shard`)
//   instance transform             = origin at the source, uniform scale
//                                    `2 * radius * SHATTER_OVERSIZE`, no
//                                    rotation — `shatter_disc_point()` reads
//                                    local VERTEX, not UV, so no Y-flip can
//                                    split the CPU kick angle from the cell.
//                                    The ORIGIN also seeds the fracture
//                                    pattern (`shatter_origin_seed`): every
//                                    shard of one shatter shares it, and it
//                                    costs no channel.
//
// Every value above is exact in a HALF float: the compatibility renderer
// stores a 2D MultiMesh's colour and custom data as 16-bit halves (probed
// 2026-09-10), which is what caps cells at 32 and keeps the seed out of the
// buffer. `ShatterField`'s class docs carry the full reasoning.
//
// Every shard is the same oversized unit quad. Its SHAPE is decided here per
// fragment: `cell_count` seed points are hashed from the seed, a fragment
// belongs to cell K iff seed K is its nearest (analytic Voronoi), and the
// consumer `discard`s the rest. Overdraw is deliberate — a full quad per
// shard is N-times fill of the disc, and at cascade scale (~1600 shards,
// ~96px bbox) that is ~15M fragment invocations of dome math. Fragment is
// the free resource at this scale; the draw call is not
// (`.claude/rules/rendering-performance.md`), and this is ONE draw call.
// Dead and unborn shards collapse to a zero quad in `shatter_vertex()` and
// cost nothing.
//
// Uniforms are declared HERE so `ShatterField` can push them onto any
// consumer's material by name. Per `ui/vision_field.gdshaderinc`'s header,
// Godot rewrites uniform tokens inside included function bodies, so no
// parameter or local below reuses a uniform's name.

// The consumer's clock (`ShatterField.elapsed`). Progress of a shard is
// `(shatter_elapsed - spawn_time) / shatter_window`; seeking backwards is just
// a smaller number. Nothing here accumulates.
uniform float shatter_elapsed = 0.0;
// Seconds from spawn to progress 1.
uniform float shatter_window = 0.25;
// Progress at which shards begin to move (`p0`): 0 for an immediate pop,
// ~0.6 for a crescendo drawn on the still-intact disc first.
uniform float shatter_flight_start : hint_range(0.0, 1.0) = 0.0;
// EV stops the colour drops across the flight (spawn tier - end tier). The
// colour value is the dimmer; alpha is the fade channel and runs out last.
uniform float shatter_fade_stops = 1.0;
// Peak spin rate in rad/s; each shard's own rate is hashed in [-max, +max].
uniform float shatter_spin_max = 6.0;
// Where the Voronoi seeds sit, in disc-radius units, and how far a seed may
// stray from its cell's nominal angle (1.0 = up to half a sector either way).
uniform float shatter_seed_radius_min : hint_range(0.0, 1.0) = 0.3;
uniform float shatter_seed_radius_max : hint_range(0.0, 1.0) = 0.85;
uniform float shatter_seed_angle_jitter : hint_range(0.0, 1.0) = 0.45;

// Must match `ShatterField.OVERSIZE`.
const float SHATTER_OVERSIZE = 2.0;
// Must match `ShatterField._CELL_SCALE`.
const int SHATTER_CELL_SCALE = 32;
const uint SHATTER_SEED_MASK = 2047u;

varying vec4 shatter_custom;
varying vec2 shatter_local;
varying float shatter_seed;

struct ShatterShard {
	vec2 velocity;
	float spawn_time;
	int cell;
	int cell_count;
	int seed;
};

ShatterShard shatter_unpack(vec4 custom, float seed_f) {
	ShatterShard s;
	s.velocity = custom.xy;
	s.spawn_time = custom.z;
	int packed = int(custom.w + 0.5);
	s.cell = packed % SHATTER_CELL_SCALE;
	s.cell_count = packed / SHATTER_CELL_SCALE + 1;
	s.seed = int(seed_f + 0.5);
	return s;
}

// Integer hash (Wang-style) — no `sin()` of a large argument, which loses
// precision on mediump GPUs and would make seeds drift between drivers.
uint shatter_hash_u(uint x) {
	x = (x ^ 61u) ^ (x >> 16u);
	x *= 9u;
	x = x ^ (x >> 4u);
	x *= 668265261u;
	x = x ^ (x >> 15u);
	return x;
}

// The fracture pattern's seed, from the instance's world origin (the source
// object's position). Same origin, same pattern — which is exactly what one
// dying object wants, and what lets #257 draw its cracks on the intact disc
// from the same seeds the shards later break along.
float shatter_origin_seed(vec2 origin) {
	uint h = shatter_hash_u(floatBitsToUint(origin.x) ^ shatter_hash_u(floatBitsToUint(origin.y)));
	return float(h & SHATTER_SEED_MASK);
}

// Unclamped: < 0 before spawn, >= 1 once expired.
float shatter_progress_raw(float spawn_t) {
	return (shatter_elapsed - spawn_t) / max(shatter_window, 0.0001);
}

float shatter_progress(ShatterShard s) {
	return clamp(shatter_progress_raw(s.spawn_time), 0.0, 1.0);
}

// Seconds in flight: zero until `p0`, then window time since. The owner's
// "simulation time left". `ShatterField.flight_time_at`.
float shatter_flight_time(float prog) {
	return max(prog - shatter_flight_start, 0.0) * shatter_window;
}

// Momentum times time. No drag term, by decision. `ShatterField.displacement_at`.
vec2 shatter_displacement(ShatterShard s, float prog) {
	return s.velocity * shatter_flight_time(prog);
}

// Collapses dead/unborn shards to a zero quad and moves a live one by its
// displacement in local units (the instance transform's scale is the quad
// side, so local = world / side — the trick `graph/edge_mesh.gdshader` uses).
// Consumers call it through `SHATTER_VERTEX()` below, never directly.
void shatter_vertex(inout vec2 vertex, mat4 model, vec4 custom) {
	ShatterShard s = shatter_unpack(custom, 0.0);
	float raw = shatter_progress_raw(s.spawn_time);
	if (raw < 0.0 || raw >= 1.0) {
		vertex = vec2(0.0);
		return;
	}
	float side = max(length(model[0].xy), 0.0001);
	vertex += shatter_displacement(s, clamp(raw, 0.0, 1.0)) / side;
}

// The whole of a consumer's vertex(): `void vertex() { SHATTER_VERTEX; }`.
// A macro rather than a function because Godot only lets a varying be
// assigned inside vertex() itself — the expansion puts the two varying writes
// there, so a consumer cannot forget them. Object-like (no parentheses)
// because Godot's preprocessor rejects a zero-argument function-like macro.
// Captures `VERTEX` BEFORE the displacement so `shatter_disc_point()` reads
// the undisplaced quad; `MODEL_MATRIX[3].xy` is the instance's world origin.
#define SHATTER_VERTEX shatter_custom = INSTANCE_CUSTOM; shatter_local = VERTEX; shatter_seed = shatter_origin_seed(MODEL_MATRIX[3].xy); shatter_vertex(VERTEX, MODEL_MATRIX, INSTANCE_CUSTOM)

// ---------------------------------------------------------------- fragment

ShatterShard shatter_shard() {
	return shatter_unpack(shatter_custom, shatter_seed);
}

// This fragment's position in disc-radius units (|p| <= 1 is the source
// disc), before any spin — the quad is `2 * SHATTER_OVERSIZE` radii wide.
vec2 shatter_disc_point() {
	return shatter_local * 2.0 * SHATTER_OVERSIZE;
}

float shatter_hash(int seed_i, int k, int salt) {
	uint h = shatter_hash_u(uint(seed_i) * 7919u + uint(k) * 104729u + uint(salt) * 15485863u);
	return float(h & 16777215u) / 16777216.0;
}

// Voronoi seed of cell K: on the cell's NOMINAL angle `TAU * K / N` — the
// same angle `ShatterField.radial_kick` pushes the shard along, so the kick
// points out through the shard's own centre — plus a hashed jitter bounded
// to stay inside the sector, at a hashed radius.
vec2 shatter_cell_seed(int seed_i, int k, int n) {
	float nominal = TAU * float(k) / float(max(n, 1));
	float jitter = (shatter_hash(seed_i, k, 1) * 2.0 - 1.0)
			* shatter_seed_angle_jitter * (TAU / float(max(n, 1))) * 0.5;
	float r = mix(shatter_seed_radius_min, shatter_seed_radius_max, shatter_hash(seed_i, k, 2));
	float a = nominal + jitter;
	return vec2(cos(a), sin(a)) * r;
}

// This shard's own rate in [-max, +max], times time in flight.
float shatter_spin(ShatterShard s, float prog) {
	float rate = (shatter_hash(s.seed, s.cell, 3) * 2.0 - 1.0) * shatter_spin_max;
	return rate * shatter_flight_time(prog);
}

// Where in the UNSPUN source disc this fragment samples: the shard rotates
// about its own seed point, so undo that rotation about the same pivot. Feed
// the result to the cell test and to the consumer's look, and the piece
// carries its own pixels as it turns.
vec2 shatter_unspin(vec2 p, ShatterShard s, float prog) {
	vec2 pivot = shatter_cell_seed(s.seed, s.cell, s.cell_count);
	float th = -shatter_spin(s, prog);
	float c = cos(th);
	float sn = sin(th);
	vec2 d = p - pivot;
	return pivot + vec2(c * d.x - sn * d.y, sn * d.x + c * d.y);
}

// (distance to own seed, distance to the nearest OTHER seed).
vec2 shatter_cell_distances(vec2 p, ShatterShard s) {
	float own = distance(p, shatter_cell_seed(s.seed, s.cell, s.cell_count));
	float other = 1e9;
	for (int k = 0; k < s.cell_count; k++) {
		if (k == s.cell) {
			continue;
		}
		other = min(other, distance(p, shatter_cell_seed(s.seed, k, s.cell_count)));
	}
	return vec2(own, other);
}

// Signed distance-ish to this shard's boundary: > 0 inside its cell, 0 on the
// seam, < 0 in another cell. Feather alpha on it with `fwidth` for AA.
float shatter_cell_margin(vec2 p, ShatterShard s) {
	vec2 d = shatter_cell_distances(p, s);
	return d.y - d.x;
}

bool shatter_in_cell(vec2 p, ShatterShard s) {
	return shatter_cell_margin(p, s) >= 0.0;
}

// Distance to the nearest seam ANYWHERE in the pattern (second-nearest minus
// nearest seed), for drawing the cracks on a still-intact disc before it
// comes apart (#257): the same seeds, so the disc breaks along the cracks it
// was showing.
float shatter_seam_distance(vec2 p, ShatterShard s) {
	float d1 = 1e9;
	float d2 = 1e9;
	for (int k = 0; k < s.cell_count; k++) {
		float d = distance(p, shatter_cell_seed(s.seed, k, s.cell_count));
		if (d < d1) {
			d2 = d1;
			d1 = d;
		} else if (d < d2) {
			d2 = d;
		}
	}
	return d2 - d1;
}

// 0..1 across the flight. `ShatterField.fade_ramp_at`.
float shatter_fade_ramp(float prog) {
	float p0 = shatter_flight_start;
	if (p0 >= 1.0) {
		return step(1.0, prog);
	}
	return clamp((prog - p0) / (1.0 - p0), 0.0, 1.0);
}

// Tier drop then fade: colour value falls `shatter_fade_stops` EV across the
// flight (the dimmer), alpha holds through the first half and reaches exactly
// 0 at progress 1 (the fade channel). `ShatterField.fade_alpha_at`.
vec4 shatter_fade(vec4 color, float prog) {
	float ramp = shatter_fade_ramp(prog);
	color.rgb *= exp2(-shatter_fade_stops * ramp);
	color.a *= 1.0 - smoothstep(0.5, 1.0, ramp);
	return color;
}

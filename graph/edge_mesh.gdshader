shader_type canvas_item;

#include "res://ui/vision_field.gdshaderinc"

// One shared MultiMeshInstance2D draws every Edge in a Graph, self-loops
// included (#413, extended to fold self-loops into the same batch — they
// used to be CPU `draw_arc()` immediate-mode geometry, which overdraws at
// every one of its 24 segment joints and, under non-premultiplied canvas
// blending, stacked the HDR-lifted colour into a visibly brighter glow than
// a regular edge at the same settings; see docs/handoffs if that regression
// ever needs re-diagnosing). One draw call, one z_index, zero per-instance
// CPU writes on a camera zoom step. Per-instance data (INSTANCE_CUSTOM /
// COLOR, set by `Graph.set_edge_transform`/`set_edge_colors` on Edge's
// behalf):
//
//   COLOR (instance_color)         = endpoint-A display colour, HDR lift baked in
//                                    (self-loop: its one endpoint's colour)
//   INSTANCE_CUSTOM (custom_data)  = endpoint-B display colour in .rgb
//                                    (self-loop: same as COLOR.rgb — one
//                                    endpoint, no gradient to speak of);
//                                    .a is NOT endpoint-B's alpha (both
//                                    endpoints always share one alpha, see
//                                    `Edge._display_color`) — it instead packs
//                                    the vision-visibility state, offset by
//                                    +10 for a self-loop instance so one
//                                    comparison in fragment() picks the
//                                    ring-vs-bar branch with no extra channel,
//                                    PLUS a further +100 * clamp_code (0-3,
//                                    bit0 = `from` carries ClampAddon, bit1 =
//                                    `to` does — see `Edge._clamp_code`) added
//                                    ONLY for bar instances, never rings
//                                    (`Edge._push_self_loop_colors` never adds
//                                    it — self-loops are structurally exempt
//                                    from widening, not a shader special-case):
//                                      0/10  = hidden   → alpha 0, nothing drawn
//                                      1/11  = visible  → alpha dimmed by the
//                                                          shared vision field,
//                                                          sampled PER-FRAGMENT
//                                      2/12  = sensed   → alpha unchanged
//                                                          (already baked into
//                                                          COLOR.a by Edge)
//                                    vertex() strips the *100 term back out
//                                    before any of the above logic runs, so it
//                                    never sees anything but the plain 0/1/2
//                                    (+10) values it already handled.
//
// Width is a material uniform, not per-instance (#413 acceptance: every edge
// authors the same width — self-loops included, now that they share this
// mesh/material too) — held constant in SCREEN pixels across camera zoom via
// `edge_camera_zoom`, a GLOBAL uniform `GraphCamera` pushes on every zoom
// change (`scenes/camera_2d.gd`), one O(1) write regardless of edge count.
// NOT `CANVAS_MATRIX` — that transforms WORLD space → canvas space,
// downstream of `MODEL_MATRIX`, and `VERTEX` here is still local/model space
// pre-`MODEL_MATRIX`; using it collapsed every edge quad to near-zero width
// (see #413's regression comment / docs/handoffs/edge-mesh-invisible.md).
// Registered in `project.godot`'s `[shader_globals]` — a shader reading it
// before registration silently gets the zero/default value, not an error.
//
// Self-loop (ring) instances: `Edge` pushes a `Transform2D` whose origin is
// the loop's centre and whose 2×2 part is a uniform scale to
// `2 * (loop_radius + margin)` (`margin` an ADDITIVE safety pad — a fixed
// world-space amount, not proportional to loop_radius, since the
// screen-constant stroke's local-space half-width is itself a fixed amount
// independent of node size; see `Edge.SELF_LOOP_MARGIN`'s docstring for why a
// multiplicative pad clipped small self-loops — rotation doesn't matter, the
// shape is a circle). `loop_radius_world` below recovers that radius from
// `MODEL_MATRIX` at draw time (half the transform's x-basis length, minus the
// same margin) — no extra per-instance channel needed just to carry one
// scalar.

uniform float width : hint_range(0.0, 32.0) = 3.0;
global uniform float edge_camera_zoom = 1.0;

// ClampAddon's edge-widening visual (issue #455): how much extra width a
// clamped endpoint adds (1.0 = edge doubles to 2x `width` at that end) and
// how far in WORLD units the taper reaches before settling back to normal
// width. Both shared-material uniforms, not per-instance — cheap to retune
// from `edge_mesh_material.tres` with no code change, same pattern `width`
// itself already uses.
uniform float clamp_widen_amount : hint_range(0.0, 3.0) = 1.0;
uniform float clamp_falloff_world : hint_range(1.0, 200.0) = 48.0;

// Matches `FogOverlay._VISIBLE_DIM_FLOOR` — a visible edge in the fade zone
// dims toward this floor instead of all the way to `vision_falloff`'s edge,
// so it never bisects into pure black mid-fade the way a raw multiply would.
const float _VISIBLE_DIM_FLOOR = 0.30;
const float _VIS_HIDDEN = 0.0;
const float _VIS_VISIBLE = 1.0;
const float _VIS_LOOP_OFFSET = 10.0;
// Must match `graph/edge.gd`'s `_CLAMP_CODE_SCALE` (and its
// `_CLAMP_A_BIT`/`_CLAMP_B_BIT` = 1.0/2.0 encoding) — the digit place packed
// into INSTANCE_CUSTOM.a above the vis_state/loop-offset digits. See the
// header comment above and `Edge._clamp_code`.
const float _CLAMP_CODE_SCALE = 100.0;
// Must match `graph/edge.gd`'s `SELF_LOOP_MARGIN` (== _SELF_LOOP_MAX_WIDTH *
// 0.5 / GraphCamera.MIN_ZOOM + _SELF_LOOP_AA_SLACK == 3.0 * 0.5 / 0.25 + 2.0).
const float _SELF_LOOP_MARGIN = 8.0;
// Pure AA slack for the bar branch's padded quad (#454) — unlike
// `_SELF_LOOP_MARGIN`, which pads a WORLD-space quad scaled from node radius,
// the bar quad's local Y already IS the screen-constant stroke width, so this
// pad divides by zoom too (see vertex()) to stay a constant couple of screen
// pixels at any zoom, same as `width` itself.
const float _BAR_AA_PAD_PX = 2.0;

varying vec4 v_custom;
varying vec2 world_pos;
varying vec2 local_vertex;
varying float loop_radius_world;
varying float loop_half_extent;
varying float is_loop;
varying float bar_local_y;
// 0-3: bit0 (1) = `from` carries ClampAddon, bit1 (2) = `to` does. Always 0
// for ring instances — see the header comment.
varying float v_clamp_code;
// World-space segment length, recovered from the transform's x-basis (bar
// branch only). `MODEL_MATRIX` is a vertex-stage-only builtin in canvas_item
// shaders — fragment() can't read it directly, so this has to ride a varying
// the same way `loop_half_extent`/`loop_radius_world` already do for rings.
varying float v_edge_len;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	// Decode + strip the clamp-code digit place FIRST — it sits above the
	// loop-offset digit, so `is_loop`'s threshold check must run against the
	// reduced value or a clamped bar edge (code > 0 adds >= 100) would
	// misread as a ring instance (`.claude/rules/godot-shaders.md`: this kind
	// of ordering bug only shows up under a real GLSL compile, not GUT).
	v_clamp_code = floor((v_custom.a + 0.5) / _CLAMP_CODE_SCALE);
	v_custom.a -= v_clamp_code * _CLAMP_CODE_SCALE;
	is_loop = v_custom.a >= _VIS_LOOP_OFFSET - 0.5 ? 1.0 : 0.0;
	local_vertex = VERTEX;
	if (is_loop > 0.5) {
		// Ring branch: leave VERTEX as the raw [-0.5, 0.5] quad — the pushed
		// instance transform already scales it to the padded bounding square,
		// see `Edge._push_self_loop_transform` / the header comment above.
		// `loop_half_extent` is the TRUE applied scale (includes the margin) —
		// it's what actually maps `local_vertex` to a world-space offset, so
		// fragment() must use it for that conversion, not the de-padded
		// `loop_radius_world` — using the de-padded value there was the actual
		// clipping bug (see `Edge.SELF_LOOP_MARGIN`'s docstring): it put the
		// ring's SDF centerline exactly ON the quad's flat boundary rather
		// than inset from it, so the outer half of the stroke was clipped at
		// the quad's 4 flat sides regardless of how much padding was applied.
		loop_half_extent = length(MODEL_MATRIX[0].xy) * 0.5;
		loop_radius_world = loop_half_extent - _SELF_LOOP_MARGIN;
	} else {
		// Bar branch: dividing the authored screen-pixel width by
		// the current camera zoom gives the LOCAL-space half-width that
		// renders at a constant on-screen size regardless of zoom — exactly
		// `Edge._screen_constant_width()`'s old, proven math
		// (`width / _current_zoom`), just driving one shared global uniform
		// instead of N per-edge `Line2D` writes.
		float half_width_local = (width * 0.5) / max(edge_camera_zoom, 0.0001);
		// The quad's local X already spans the segment (stretched by the
		// instance transform's x-scale, see Graph.set_edge_transform); only Y
		// carries width, and only its SIGN survives from the base mesh — the
		// magnitude is entirely zoom-derived, never inherited from instance scale.
		// Padded past the true half-width (#454) so fragment()'s AA feather has
		// room to fade out instead of being hard-clipped at the mesh edge —
		// same idea as the ring branch's margin above, mirrored for a strip.
		float aa_pad_local = _BAR_AA_PAD_PX / max(edge_camera_zoom, 0.0001);
		// ClampAddon widening (#455): a QuadMesh has only 4 vertices, so the
		// actual taper curve can't be expressed here — geometry just needs to
		// cover the WORST-CASE width so fragment()'s per-pixel taper (against
		// UV.x) has room to draw into. `code == 0` (the overwhelming common
		// case) takes the exact same expression as before this feature existed.
		float max_mult = v_clamp_code > 0.5 ? (1.0 + clamp_widen_amount) : 1.0;
		VERTEX.y = sign(VERTEX.y) * (half_width_local * max_mult + aa_pad_local);
		bar_local_y = VERTEX.y;
		v_edge_len = length(MODEL_MATRIX[0].xy);
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float base_alpha = COLOR.a;
	float raw_vis = v_custom.a;
	float vis_state = is_loop > 0.5 ? raw_vis - _VIS_LOOP_OFFSET : raw_vis;

	vec3 rgb;
	float shape_alpha = 1.0;
	if (is_loop > 0.5) {
		rgb = COLOR.rgb;
		float half_width_world = (width * 0.5) / max(edge_camera_zoom, 0.0001);
		float dist = length(local_vertex) * 2.0 * loop_half_extent;
		float d = abs(dist - loop_radius_world) - half_width_world;
		// Centered on the true edge (`d == 0` -> alpha 0.5), not extended
		// purely outward from it — the old `1.0 - clamp(d / fwidth(dist), 0,
		// 1)` held `d == 0` at full alpha 1.0 and only faded past it, so the
		// visible stroke bulged about a full `fwidth(dist)` (~1 screen px)
		// wider than `half_width_world` on BOTH the inner and outer edge —
		// rendering visibly thicker than a bar edge at the same `width`
		// (the bar branch below uses this same centered technique, #454).
		float aa = max(fwidth(dist), 0.0001);
		shape_alpha = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, d);
	} else {
		rgb = mix(COLOR.rgb, v_custom.rgb, UV.x);
		// Same centered-feather technique as the ring branch above (#454):
		// `d == 0` at the TRUE (unpadded) half-width keeps the measured
		// on-screen width unchanged — centering on the real edge instead of
		// extending outward from it is what avoids the ring's old bulge bug.
		float half_width_local = (width * 0.5) / max(edge_camera_zoom, 0.0001);
		// ClampAddon widening (#455): per-pixel taper against UV.x, normalized
		// into WORLD units (not raw UV.x) so the thick stub is a consistent
		// size near a clamped node regardless of the edge's own length — a
		// pure-UV falloff would stretch wider on long edges, narrower on short
		// ones. UV.x == 0 is the `from`/A end, UV.x == 1 is `to`/B (matches the
		// COLOR/v_custom endpoint-color mix just above, and Edge._push_transform's
		// x-basis direction (b - a)). `max`, not sum, for a double-clamped edge —
		// never overshoots 1 + clamp_widen_amount even when both falloffs overlap
		// on a short edge.
		float width_mult = 1.0;
		if (v_clamp_code > 0.5) {
			bool widen_a = v_clamp_code == 1.0 || v_clamp_code == 3.0;
			bool widen_b = v_clamp_code == 2.0 || v_clamp_code == 3.0;
			float falloff = max(clamp_falloff_world, 0.0001);
			float t_a = widen_a ? clamp(1.0 - (UV.x * v_edge_len) / falloff, 0.0, 1.0) : 0.0;
			float t_b = widen_b ? clamp(1.0 - ((1.0 - UV.x) * v_edge_len) / falloff, 0.0, 1.0) : 0.0;
			width_mult = 1.0 + clamp_widen_amount * max(t_a, t_b);
		}
		float d = abs(bar_local_y) - half_width_local * width_mult;
		// `fwidth(d)`, not `fwidth(bar_local_y)` — `d` now varies along X too
		// (via `width_mult`), so its own screen-space derivative is what the AA
		// feather must track; the old `bar_local_y`-only derivative would ignore
		// the taper's slope entirely.
		float aa = max(fwidth(d), 0.0001);
		shape_alpha = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, d);
	}

	float alpha;
	if (vis_state < _VIS_HIDDEN + 0.5) {
		alpha = 0.0;
	} else if (vis_state < _VIS_VISIBLE + 0.5) {
		float dark = vision_field_enabled ? vision_field_darkness(world_pos) : 0.0;
		alpha = base_alpha * clamp(1.0 - dark, _VISIBLE_DIM_FLOOR, 1.0);
	} else {
		// Sensed: fixed alpha, already baked into base_alpha by Edge —
		// ignores the darkness ramp entirely (structure reads through fog).
		alpha = base_alpha;
	}
	COLOR = vec4(rgb, alpha * shape_alpha);
}

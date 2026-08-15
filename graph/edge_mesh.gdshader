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
//                                    ring-vs-bar branch with no extra channel:
//                                      0/10  = hidden   → alpha 0, nothing drawn
//                                      1/11  = visible  → alpha dimmed by the
//                                                          shared vision field,
//                                                          sampled PER-FRAGMENT
//                                      2/12  = sensed   → alpha unchanged
//                                                          (already baked into
//                                                          COLOR.a by Edge)
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
// `2 * loop_radius * pad` (`pad` a small safety margin so the screen-constant
// stroke never clips the instance's bounding quad — rotation doesn't matter,
// the shape is a circle). `loop_radius_world` below recovers that radius from
// `MODEL_MATRIX` at draw time (half the transform's x-basis length) — no
// extra per-instance channel needed just to carry one scalar.

uniform float width : hint_range(0.0, 32.0) = 3.0;
global uniform float edge_camera_zoom = 1.0;

// Matches `FogOverlay._VISIBLE_DIM_FLOOR` — a visible edge in the fade zone
// dims toward this floor instead of all the way to `vision_falloff`'s edge,
// so it never bisects into pure black mid-fade the way a raw multiply would.
const float _VISIBLE_DIM_FLOOR = 0.30;
const float _VIS_HIDDEN = 0.0;
const float _VIS_VISIBLE = 1.0;
const float _VIS_LOOP_OFFSET = 10.0;
const float _LOOP_PAD = 1.3;

varying vec4 v_custom;
varying vec2 world_pos;
varying vec2 local_vertex;
varying float loop_radius_world;
varying float is_loop;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	is_loop = v_custom.a >= _VIS_LOOP_OFFSET - 0.5 ? 1.0 : 0.0;
	local_vertex = VERTEX;
	if (is_loop > 0.5) {
		// Ring branch: leave VERTEX as the raw [-0.5, 0.5] quad — the pushed
		// instance transform already scales it to the padded bounding square,
		// see `Edge._push_self_loop_transform` / the header comment above.
		loop_radius_world = length(MODEL_MATRIX[0].xy) * 0.5 / _LOOP_PAD;
	} else {
		// Bar branch (unchanged): dividing the authored screen-pixel width by
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
		VERTEX.y = sign(VERTEX.y) * half_width_local;
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
		float dist = length(local_vertex) * 2.0 * loop_radius_world;
		float d = abs(dist - loop_radius_world) - half_width_world;
		shape_alpha = 1.0 - clamp(d / max(fwidth(dist), 0.0001), 0.0, 1.0);
	} else {
		rgb = mix(COLOR.rgb, v_custom.rgb, UV.x);
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

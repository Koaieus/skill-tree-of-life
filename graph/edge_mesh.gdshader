shader_type canvas_item;

#include "res://ui/vision_field.gdshaderinc"

// One shared MultiMeshInstance2D draws every regular (non-self-loop) Edge in
// a Graph (#413) — one draw call, one z_index, zero per-instance CPU writes
// on a camera zoom step. Per-instance data (INSTANCE_CUSTOM / COLOR, set by
// `Graph.set_edge_transform`/`set_edge_colors` on Edge's behalf):
//
//   COLOR (instance_color)         = endpoint-A display colour, HDR lift baked in
//   INSTANCE_CUSTOM (custom_data)  = endpoint-B display colour in .rgb;
//                                    .a is NOT endpoint-B's alpha (both
//                                    endpoints always share one alpha, see
//                                    `Edge._display_color`) — it instead packs
//                                    the vision-visibility state:
//                                      0.0 = hidden   → alpha 0, nothing drawn
//                                      1.0 = visible  → alpha dimmed by the
//                                                       shared vision field,
//                                                       sampled PER-FRAGMENT
//                                      2.0 = sensed   → alpha unchanged
//                                                       (already baked into
//                                                       COLOR.a by Edge)
//
// Width is a material uniform, not per-instance (#413 acceptance: every edge
// authors the same width) — held constant in SCREEN pixels across camera
// zoom by reading the local→canvas scale off CANVAS_MATRIX every vertex,
// which costs nothing extra on a zoom step: no signal, no per-edge write,
// the engine already recomputes CANVAS_MATRIX whenever the camera changes.

uniform float width : hint_range(0.0, 32.0) = 3.0;

// Matches `FogOverlay._VISIBLE_DIM_FLOOR` — a visible edge in the fade zone
// dims toward this floor instead of all the way to `vision_falloff`'s edge,
// so it never bisects into pure black mid-fade the way a raw multiply would.
const float _VISIBLE_DIM_FLOOR = 0.30;
const float _VIS_HIDDEN = 0.0;
const float _VIS_VISIBLE = 1.0;

varying vec4 v_custom;
varying vec2 world_pos;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	// CANVAS_MATRIX's X basis length is the local→canvas (screen) scale —
	// i.e. current camera zoom in world-units-to-pixels terms. Dividing the
	// authored screen-pixel width by it gives the LOCAL-space half-width
	// that renders at a constant on-screen size regardless of zoom.
	float canvas_scale = length(CANVAS_MATRIX[0].xy);
	float half_width_local = (width * 0.5) / max(canvas_scale, 0.0001);
	// The quad's local X already spans the segment (stretched by the
	// instance transform's x-scale, see Graph.set_edge_transform); only Y
	// carries width, and only its SIGN survives from the base mesh — the
	// magnitude is entirely zoom-derived, never inherited from instance scale.
	VERTEX.y = sign(VERTEX.y) * half_width_local;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec3 rgb = mix(COLOR.rgb, v_custom.rgb, UV.x);
	float base_alpha = COLOR.a;
	float vis_state = v_custom.a;
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
	COLOR = vec4(rgb, alpha);
}

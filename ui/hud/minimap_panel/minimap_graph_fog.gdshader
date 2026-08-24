shader_type canvas_item;

#include "res://ui/vision_field.gdshaderinc"

// Self-shading for the minimap's dot/edge layer (#453) — a node outside every
// vision circle is drawn at alpha ZERO, not merely covered.
//
// [b]Why this exists at all[/b]: `minimap_fog.gdshader` paints darkness OVER
// this layer, and its `max_darkness` ceiling is deliberately under 1.0 (a
// fresh level is almost entirely fogged, and a hard black quad reads as a hole
// punched in the HUD). That residual few percent is enough to leave a bright
// entity dot legibly glowing through pitch-black fog, which is exactly the
// information fog exists to withhold. So the layer subtracts itself from the
// field instead of trusting a quad to bury it — the same self-shading contract
// #413/#414 put on the world's disks, rims and edges.
//
// It is NOT `vision_field_dim`: that helper floors at
// VISION_VISIBLE_DIM_FLOOR so a *visible* element stays legible while it dims
// through the fade zone. Here the floor is the bug. This reads the raw
// darkness and cuts to nothing.

// `_map_to_world` from `minimap_panel.gd`, as the shader sees it: local pixel
// coordinates of THIS Control, which is full-bleed over `MapArea`. Pushed by
// `MinimapPanel._push_graph_fog_mapping()` from the same `_fit` results the
// dots were placed with, so the two cannot disagree.
//
// `minimap_`-prefixed on purpose: Godot's shader codegen rewrites uniform
// tokens even inside included function bodies, so a name colliding with one of
// `vision_field.gdshaderinc`'s globals would be silently substituted.
uniform vec2 minimap_world_origin = vec2(0.0);
uniform float minimap_world_per_pixel = 1.0;

// Local-space position of the fragment. `UV` is useless here: the layer draws
// `draw_multiline_colors` primitives, which carry no meaningful UVs.
varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 world = minimap_world_origin + v_local * minimap_world_per_pixel;
	// The gate INVERTS relative to `minimap_fog.gdshader`. There, no live fog
	// system must mean no darkness (`* active`); here it must mean full
	// visibility — a copy-pasted `* active` would erase the whole board in
	// every dev sandbox and HUD fixture. Branchless for the same reason the
	// fog shader documents: Godot rejects `return` inside `fragment()` at
	// DRIVER compile time, which headless import and GUT sail past.
	float active = vision_field_enabled ? 1.0 : 0.0;
	COLOR.a *= mix(1.0, 1.0 - vision_field_darkness(world), active);
}

shader_type canvas_item;

#include "res://ui/vision_field.gdshaderinc"

// Fog of war for the minimap (#453) — the SAME darkness field `fog.gdshader`
// paints over the world, sampled through the minimap's own world mapping
// instead of through a world-space quad.
//
// This costs nothing to keep in sync because there is nothing to sync: the
// circle textures, falloff and union smoothness are GLOBAL uniforms that
// `FogOverlay` writes once per vision tick (`ui/fog_overlay/fog_overlay.gd`),
// and every consumer is a reader. The minimap adds no CPU work of its own and
// asks `VisionSystem` nothing per node — it just reads the field at a
// different set of world positions.
//
// This quad is the fog's LOOK, not its concealment. Hiding is the dot/edge
// layer's own job — it self-shades to alpha zero against this same field in
// `minimap_graph_fog.gdshader`, because this quad's alpha ceiling is under 1.0
// (see `max_darkness`) and the residual few percent left a bright entity dot
// legibly glowing through pitch black. Neither half culls on the CPU, so the
// minimap still asks `VisionSystem` nothing, per node or otherwise.

// The world rect this quad's UV space maps onto — x,y = position, z,w = size.
//
// Named with a `minimap_` prefix on purpose: Godot's shader codegen rewrites
// *uniform tokens* even inside included function bodies, so a name that
// collides with one of `vision_field.gdshaderinc`'s globals would be silently
// substituted. See the include's own header note.
uniform vec4 minimap_world_rect = vec4(0.0, 0.0, 1.0, 1.0);

// Ceiling on the darkness alpha. Deliberately under 1.0: the panel sits on a
// styled glass gradient, and a fresh level (one owned node) is almost entirely
// fogged — at a hard 1.0 the whole minimap reads as a black hole punched in
// the HUD. It does NOT have to reach 1.0 to hide anything: the dots and edges
// underneath have already erased themselves.
uniform float max_darkness : hint_range(0.0, 1.0) = 0.92;

void fragment() {
	vec2 world = minimap_world_rect.xy + UV * minimap_world_rect.zw;
	// `vision_circle_count == 0` cannot distinguish "fog is on and nobody can
	// see anything" from "this level has no fog system at all" (dev sandboxes,
	// most tests). The global flag can — without this gate every fog-less level
	// would show a fully black minimap. Mirrors `vision_field_dim`.
	//
	// Written as a multiply rather than an early-out because Godot rejects
	// `return` inside `fragment()` outright — and it rejects it at DRIVER
	// compile time, which a headless import and the whole GUT suite sail past
	// (they run the dummy renderer and never compile GLSL). See
	// .claude/rules/godot-shaders.md for the xvfb-run check that catches it.
	float active = vision_field_enabled ? 1.0 : 0.0;
	COLOR = vec4(0.0, 0.0, 0.0, vision_field_darkness(world) * max_darkness * active);
}

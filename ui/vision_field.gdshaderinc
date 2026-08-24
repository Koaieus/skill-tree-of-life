// Shared vision-darkness field — the SAME world-space circle-union math
// `fog.gdshader` composites as an opaque overlay, exposed here as a plain
// darkness lookup so any OTHER canvas_item shader can self-shade against the
// exact same fog state instead of relying on z-order to escape an opaque
// quad painted over it (see #413 and docs/domain/rendering-performance.md).
//
// Declared as GLOBAL uniforms (not per-material) so every consumer reads one
// shared, per-frame-updated field with no per-material parameter wiring:
// `FogOverlay` is the sole writer (`RenderingServer.global_shader_parameter_set`,
// see `ui/fog_overlay/fog_overlay.gd`), every self-shading consumer is a
// reader. Registered in `project.godot`'s `[shader_globals]` section — a
// shader referencing one of these before it's registered there silently reads
// the zero/default value, not an error.
//
// Parameter names on `vision_field_darkness` are underscore-prefixed:
// Godot's shader codegen rewrites *uniform tokens* even inside included
// function bodies, so a param named e.g. `falloff` would be silently
// substituted at the call site's own uniform. See
// .claude/rules/godot-workflow.md.

global uniform sampler2D vision_circles_tex : filter_nearest, repeat_disable;
global uniform sampler2D vision_tile_index_tex : filter_nearest, repeat_disable;
global uniform sampler2D vision_tile_indices_tex : filter_nearest, repeat_disable;
global uniform vec2 vision_grid_origin;
global uniform float vision_cell_size;
global uniform int vision_grid_cols;
global uniform int vision_grid_rows;
global uniform int vision_circle_count;
global uniform float vision_falloff : hint_range(0.0, 1.0);
global uniform float vision_union_smoothness : hint_range(0.0, 0.5);
// True only while `FogOverlay` is actually active (a live `VisionSystem` says
// fog is meaningful right now) — mirrors its own `visible` gate. Zero
// circles legitimately means "full darkness" WHILE fog is active (nobody has
// vision), but a scene with no fog system at all (dev sandboxes, most tests)
// must read as fully lit, not fully dark, and `vision_circle_count == 0`
// can't tell those two cases apart on its own.
//
// THE GATE INVERTS BY WHAT YOU PAINT, and getting it backwards is silent:
// a shader painting DARKNESS multiplies its alpha by `active` (fog.gdshader,
// minimap_fog.gdshader), while a shader painting CONTENT that erases itself
// needs `mix(1.0, <lit>, active)` (minimap_graph_fog.gdshader). A copy-pasted
// `* active` in the second case blanks the whole board in every fogless dev
// sandbox and HUD fixture — which no headless test can see.
global uniform bool vision_field_enabled;

// A VISIBLE element in the fade zone dims toward this floor instead of being
// bisected by the fog gradient — it must stay legible against the sensed
// outline of a neighbour in pitch black. The ONE home for the number: edges
// (`edge_mesh.gdshader`), SkillNode's disk and rim (#414) and the CPU
// reference path (`FogOverlay._VISIBLE_DIM_FLOOR`, which still mirrors it for
// `_sample_dark`'s lockstep tests) all have to agree, or a node dims by a
// different amount than the edge leaving it.
const float VISION_VISIBLE_DIM_FLOOR = 0.30;

// Polynomial smooth-minimum — twin of `field_smin` in overlay_field.gdshaderinc,
// duplicated (not included) because Godot shader includes don't nest cleanly
// across two independent global-uniform-bearing files without risking a
// double-declaration; this is the only function this file needs from it.
float _vision_field_smin(float _a, float _b, float _k) {
	if (_k <= 0.0) {
		return min(_a, _b);
	}
	float _h = clamp(0.5 + 0.5 * (_b - _a) / _k, 0.0, 1.0);
	return mix(_b, _a, _h) - _k * _h * (1.0 - _h);
}

// Darkness in [0,1] at `_world_pos`: 0 inside the clear zone, smooth 0→1
// across the fade zone, 1 beyond every vision source's radius. Mirrors
// `fog.gdshader`'s fragment() exactly (minus the frontier-halo term, which is
// FogOverlay's own cosmetic and not part of the shared visibility field).
float vision_field_darkness(vec2 _world_pos) {
	float _min_d = 1e9;
	if (vision_circle_count > 0 && vision_cell_size > 0.0) {
		ivec2 _centre_tile = ivec2(floor((_world_pos - vision_grid_origin) / vision_cell_size));
		for (int _dx = -1; _dx <= 1; _dx++) {
			for (int _dy = -1; _dy <= 1; _dy++) {
				ivec2 _tile = _centre_tile + ivec2(_dx, _dy);
				if (_tile.x < 0 || _tile.x >= vision_grid_cols || _tile.y < 0 || _tile.y >= vision_grid_rows) {
					continue;
				}
				vec2 _oc = texelFetch(vision_tile_index_tex, _tile, 0).rg;
				int _offset = int(_oc.x);
				int _count = int(_oc.y);
				for (int _j = 0; _j < _count; _j++) {
					int _idx = int(texelFetch(vision_tile_indices_tex, ivec2(_offset + _j, 0), 0).r);
					vec4 _c = texelFetch(vision_circles_tex, ivec2(_idx, 0), 0);
					float _d = distance(_world_pos, _c.xy) / max(_c.z, 1.0);
					_min_d = _vision_field_smin(_min_d, _d, vision_union_smoothness);
				}
			}
		}
	}
	float _fade_start = 1.0 - max(vision_falloff, 1e-4);
	return smoothstep(_fade_start, 1.0, _min_d);
}

// The multiplier a VISIBLE element applies to its own alpha to self-shade:
// 1.0 in the clear zone, ramping down to `VISION_VISIBLE_DIM_FLOOR` past the
// vision edge. This is the whole self-shading contract — a consumer multiplies
// its final alpha by this and needs to know nothing else about the fog.
//
// Returns 1.0 (fully lit) when no fog system is live, which is the case
// `vision_circle_count == 0` cannot distinguish from "fog is on and nobody has
// vision" — see `vision_field_enabled` above. Without this gate every dev
// sandbox and most tests would render the whole board at the floor.
float vision_field_dim(vec2 _world_pos) {
	if (!vision_field_enabled) {
		return 1.0;
	}
	return clamp(1.0 - vision_field_darkness(_world_pos), VISION_VISIBLE_DIM_FLOOR, 1.0);
}

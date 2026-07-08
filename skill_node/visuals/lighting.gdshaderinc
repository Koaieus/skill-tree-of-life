// Shared shading model for the SkillNode-visuals family (milestone #16).
//
// ONE source of truth for the "height-field + one light" model: rim, disk, and
// the weld glyph (folded into the disk's own dome height field, see
// sn_polygon_facet/sn_bowl_drop below) all #include these helpers instead of
// re-deriving the same `normalize(vec3(dir, LIGHT_Z))` light + Lambert/specular
// math. The weld used to keep a CPU twin of this math (weld_symbol.gd's
// _disk_shade()) — that's gone now that it's a real height feature lit by
// this same code, not a separately-maintained approximation.
//
// LIGHT_Z is the fixed height of the faked light above the node plane. A later
// global-uniform light framework can replace the per-shader `*_dir_xy` inputs
// with global data without touching these helpers.
//
// GOTCHA: every parameter below is `p_`-prefixed ON PURPOSE. Godot's shader
// code-generator rewrites uniform-name *tokens* wherever they appear — including
// inside a function body — into the uniform's storage accessor. A parameter
// sharing a uniform's name (e.g. a `vec3 tint_color` param vs the shader's
// `instance uniform vec4 tint_color`) gets its in-body uses silently swapped for
// the uniform, producing invalid generated GLSL (`mix(vec3, vec4, float)`) that
// fails at driver compile — passing Godot's own parser, so nothing catches it
// until the GPU rejects it. Prefixing keeps these functions genuinely
// parameterized and collision-proof against any consumer's uniform names.

const float SN_LIGHT_Z = 0.65;
const vec3 SN_NEUTRAL_DARK = vec3(0.16, 0.17, 0.20);
const vec3 SN_NEUTRAL_LIGHT = vec3(0.38, 0.40, 0.45);

// The faked main-light direction from its xy component (z fixed above plane).
vec3 sn_light_dir(vec2 p_dir_xy) {
	return normalize(vec3(p_dir_xy, SN_LIGHT_Z));
}

float sn_diffuse(vec3 p_normal, vec3 p_light_dir) {
	return max(dot(p_normal, p_light_dir), 0.0);
}

float sn_specular(float p_diffuse, float p_intensity) {
	return pow(p_diffuse, 24.0) * p_intensity;
}

// Hemisphere-dome surface normal at a normalized (-1..1) disk-space position.
vec3 sn_dome_normal(vec2 p_pos) {
	float r2 = dot(p_pos, p_pos);
	float z = sqrt(max(0.0, 1.0 - min(r2, 1.0)));
	return normalize(vec3(p_pos, z));
}

// Full inner-disk shaded color: tinted-lit when allocated, neutral-dark when
// not, plus the specular term. Matches the pre-include inner_disk fragment.
vec3 sn_disk_color(vec3 p_normal, vec3 p_light_dir, vec3 p_tint, float p_tint_mix,
		bool p_allocated, float p_highlight_intensity) {
	if (!p_allocated) {
		return SN_NEUTRAL_DARK;
	}
	float diffuse = sn_diffuse(p_normal, p_light_dir);
	float spec = sn_specular(diffuse, p_highlight_intensity);
	vec3 tinted = mix(vec3(0.5), p_tint, p_tint_mix);
	vec3 base_dark = mix(SN_NEUTRAL_DARK, SN_NEUTRAL_LIGHT, 0.35 + 0.5 * diffuse);
	vec3 base_tint = tinted * (0.45 + 0.65 * diffuse);
	vec3 base = p_allocated ? base_tint : base_dark;
	return base + vec3(spec);
}

// --- Weld glyph: a regular-polygon "gem facet" bowl dent folded into the
// disk's own dome height field ---
//
// Each of the polygon's `p_sides` sectors is a flat facet with a CONSTANT
// gradient. That flatness is deliberate: it's what reads as crease "depth
// lines toward the visual center", not something to smooth away. Regular
// polygons only (no arbitrary glyph support) — an arbitrary rune/kanji shape
// would need a per-instance LUT-texture escape hatch (breaking the
// shared-material batching every component in this family relies on,
// see .claude/rules/skill-node-visuals.md); deferred, not attempted here.

// Signed perpendicular ("apothem-space") distance from p_pos to the nearest
// edge of a point-up regular N-gon (p_sides) with circumradius p_radius,
// plus that sector's fixed inward unit normal and the local normalized
// radius `t` (0 at the glyph's own center, 1 at its boundary). Packed as
// vec4(n_sector.x, n_sector.y, t, edge_dist) so callers don't redo the
// angle-fold to get each piece.
vec4 sn_polygon_facet(vec2 p_pos, float p_sides, float p_radius) {
	float sector = TAU / p_sides;
	float raw_angle = atan(p_pos.y, p_pos.x) + PI * 0.5; // point-up, matches the glyph's placeholder orientation
	float a = mod(raw_angle, sector) - sector * 0.5;
	float apothem = p_radius * cos(sector * 0.5);
	float edge_dist = length(p_pos) * cos(a) - apothem; // <= 0 inside the polygon
	float bisector_angle = raw_angle - a - PI * 0.5; // back to standard atan2 space
	vec2 n_sector = vec2(cos(bisector_angle), sin(bisector_angle));
	float t = clamp(edge_dist / apothem + 1.0, 0.0, 1.0);
	return vec4(n_sector, t, edge_dist);
}

// Bowl height drop + its analytic xy-gradient at p_pos, for a regular-polygon
// dent of circumradius p_radius and max depth p_depth. Zero outside the
// polygon (or when p_depth <= 0). The bowl reuses the SAME sqrt(1-t^2)
// profile as the main dome, just re-centered/rescaled to the glyph's own
// footprint — a mini inverted dome nested in the big one, not a new shape.
// Returned as vec3(drop, grad.x, grad.y).
vec3 sn_bowl_drop(vec2 p_pos, float p_sides, float p_radius, float p_depth) {
	vec4 facet = sn_polygon_facet(p_pos, p_sides, p_radius);
	vec2 n_sector = facet.xy;
	float t = facet.z;
	float edge_dist = facet.w;
	if (edge_dist > 0.0 || p_depth <= 0.0) {
		return vec3(0.0);
	}
	float apothem = p_radius * cos(PI / p_sides);
	float s = sqrt(max(0.0001, 1.0 - t * t));
	// Fade only the outer rim (t near 1) for AA — interior facet creases stay sharp.
	float fade = 1.0 - smoothstep(0.92, 1.0, t);
	float drop = p_depth * s * fade;
	vec2 grad = -(p_depth * t / (s * apothem)) * n_sector * fade;
	return vec3(drop, grad);
}

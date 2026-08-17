shader_type canvas_item;

// #123 — semi-sphere shading for the SkillNode inner disk: an offset radial
// highlight fakes a lit hemisphere. Player-tinted when allocated,
// neutral-dark otherwise. `instance uniform`s mean every inner_disk shares
// ONE ShaderMaterial (batches into one draw call) while still varying
// per-node via CanvasItem.set_instance_shader_parameter() — see
// skill_node/visuals/inner_disk.gd.
//
// The lighting math lives in lighting.gdshaderinc (shared with rim_ring.gdshader)
// so the disk and its rim read as lit from one source and neither re-derives it.

#include "res://skill_node/visuals/lighting.gdshaderinc"
// #414 — self-shade against the shared vision-darkness field, per fragment,
// exactly as `edge_mesh.gdshader` does (#413). This REPLACES
// `FogOverlay._apply_per_element_dimming` sampling the fog once at the node's
// centre and writing `SkillNode.modulate.a` every frame: modulate arrives as
// the incoming COLOR, and this shader overwrites COLOR unconditionally, so
// that write never reached the disk at all — the dome popped to full
// brightness at the vision edge instead of fading. It fades now.
#include "res://ui/vision_field.gdshaderinc"

// Canvas-space position of this fragment. `MODEL_MATRIX` is a vertex-stage-only
// builtin in canvas_item shaders, so the lookup has to ride a varying — same
// mechanism as `edge_mesh.gdshader`.
varying vec2 world_pos;

instance uniform vec4 tint_color : source_color = vec4(0.291, 0.5892, 1.0, 1.0);
instance uniform float tint_mix : hint_range(0.0, 1.0) = 0.6;  // TODO: this one might be a real uniform, we don't tweak it per instance
instance uniform bool allocated = false;
instance uniform vec2 highlight_position = vec2(-0.35, -0.35); // TODO: this one might be a real uniform, we don't tweak it per instance
instance uniform float highlight_intensity : hint_range(0.0, 1.0) = 0.85; // TODO: this one might be a real uniform, we don't tweak it per instance 

// Which CARVE shape family the dome etches — one selector rather than the
// retired pair of mutually-exclusive "show this glyph" bools
// (0 = NONE, 1 = POLYGON, 2 = GEM, 3 = TEXTURE; see InnerDisk.CarveKind). All
// scalar so the shared ShaderMaterial keeps batching every InnerDisk into one
// draw call.
instance uniform int carve_kind = 0;

// Polygon carve (#124 rework) — a regular-polygon "gem facet" bowl dent folded
// into this same dome height field. See sn_polygon_facet/sn_bowl_drop in
// lighting.gdshaderinc for the math and skill-node-visuals.md for the design
// intent. Every default here MUST match the matching InnerDisk export's.
instance uniform float carve_sides : hint_range(3.0, 16.0, 1.0) = 3.0;
// Anisotropic X-squish (1.0 = regular; < 1.0 narrows the shape, e.g. DEX's
// diamond read) — applied as a warp of the sampled position before the facet
// math, so the analytic gradient just needs a chain-rule rescale back.
instance uniform float carve_squish : hint_range(0.3, 1.0, 0.01) = 1.0;
instance uniform float carve_radius : hint_range(0.4, 1.15, 0.01) = 0.75;
instance uniform float well_depth : hint_range(0.0, 1.0, 0.01) = 0.35;

// Loot relic gem cut (#168), viewed from the side — see sn_gem_bump in
// lighting.gdshaderinc. `gem_lut` is deliberately a PLAIN uniform (not
// `instance uniform`): the shape is fixed and identical for every relic, so
// one shared texture on the shared ShaderMaterial costs nothing against the
// family's batching, unlike a per-instance-varying sampler would.
// filter_linear_mipmap (trilinear), not plain filter_linear: the 128px LUT
// is higher-res than the disk's on-screen footprint, so sampling it is a
// MINIFICATION — mip-aware filtering is what actually antialiases the
// facet creases instead of aliasing them (see _build_gem_lut in
// inner_disk.gd, which bakes the matching mip chain).
uniform sampler2D gem_lut : filter_linear_mipmap, hint_default_black;

// Arbitrary-art carves (#247) — every baked LUT packed into ONE array texture
// on the shared material (a plain uniform, like gem_lut), with the per-node
// choice riding as a cheap int index. A sampler can't be an `instance uniform`,
// so this indirection is what lets N distinct baked shapes coexist without
// either duplicating the material per node or burning a uniform slot per shape
// (#172's ceiling). See sn_texture_bump in lighting.gdshaderinc and [CarveAtlas].
uniform sampler2DArray carve_atlas : filter_linear_mipmap;
// Which slice this node reads; < 0 means "no slice", the honest empty dome.
instance uniform int carve_slice = -1;

// Slot B: a second competing carve (#206's widened spell-grant distribution
// can stack 2+ different SpellGrants on one node — EmblemResolver.Resolution
// .carve_ties exists for exactly that, and this is the renderer half of the
// contract it defers; see skill-node-visuals.md). TEXTURE-only, deliberately —
// every SpellDef.carve_shape is a TextureCarveShape (baked icon art via
// CarveAtlas), never a POLYGON/GEM shape, so a full mirror of slot A's 6
// uniforms isn't needed; this shader is already at 11 instance uniforms
// against Godot's hard cap of 16 (verified empirically — "Too many 'instance'
// uniforms" is a shader COMPILE failure, invisible under the headless dummy
// renderer, see godot-shaders.md), and a full mirror would have blown it.
// < 0 means "no second carve" — the crossfade below then collapses to a
// static 1.0/0.0 split and a single-carve node never reads TIME.
instance uniform int carve_slice_b = -1;

// Full A-to-B-and-back period, seconds. A tuning value, not a derived one —
// eyeball it in the sandbox before treating it as settled.
const float CARVE_ALTERNATE_PERIOD = 4.0;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}


void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	vec3 normal = sn_dome_normal(p);

	// Crossfade weight between slot A and slot B. Sinusoidal ping-pong, no
	// flat hold at either end — a hold-phase version is a possible follow-up
	// if this reads as too blended at the midpoint; needs an eyeball pass
	// either way (see godot-shaders.md — this can't be judged headless).
	float mix_a = 1.0;
	float mix_b = 0.0;
	if (carve_slice_b >= 0) {
		float phase = fract(TIME / CARVE_ALTERNATE_PERIOD) * TAU;
		mix_a = 0.5 + 0.5 * cos(phase);
		mix_b = 1.0 - mix_a;
	}

	vec2 bump_sum = vec2(0.0);
	bool carved = false;

	if (carve_kind == 2 && mix_a > 0.0) {
		vec4 lut = texture(gem_lut, UV);
		// lut.a is antialiased COVERAGE (see InnerDisk._gem_coverage), so it
		// scales the perturbation instead of gating it. A `> 0.5` branch here
		// snapped every partially-covered pixel fully in or fully out and
		// stair-stepped the gem's outline — the soft bake was being discarded.
		if (lut.a > 0.0) {
			vec3 bump = sn_gem_bump(lut);
			bump_sum += bump.yz * lut.a * mix_a;
			carved = true;
		}
	} else if (carve_kind == 3 && carve_slice >= 0 && mix_a > 0.0) {
		vec4 lut = texture(carve_atlas, vec3(UV, float(carve_slice)));
		// Same blend-weight treatment as the gem branch above, deliberately:
		// #246's bake still writes a HARD 0/1 mask here, so today this behaves
		// as a gate — but weighting rather than branching means the outline
		// antialiases for free the moment that bake picks up the gem's
		// coverage ramp, instead of needing this shader changed too.
		if (lut.a > 0.0) {
			vec3 bump = sn_texture_bump(lut);
			bump_sum += bump.yz * lut.a * mix_a;
			carved = true;
		}
	} else if (carve_kind == 1 && mix_a > 0.0) {
		vec2 wp = vec2(p.x / carve_squish, p.y);
		vec3 bowl = sn_bowl_drop(wp, carve_sides, carve_radius, well_depth * mix_a);
		if (bowl.x > 0.0) {
			// Chain rule: q.x = p.x / carve_squish, so d/d(p.x) = d/d(q.x) / carve_squish.
			bump_sum += vec2(bowl.y / carve_squish, bowl.z);
			carved = true;
		}
	}

	if (carve_slice_b >= 0 && mix_b > 0.0) {
		vec4 lut = texture(carve_atlas, vec3(UV, float(carve_slice_b)));
		if (lut.a > 0.0) {
			vec3 bump = sn_texture_bump(lut);
			bump_sum += bump.yz * lut.a * mix_b;
			carved = true;
		}
	}

	if (carved) {
		float z_dome = sqrt(max(0.0001, 1.0 - dot(p, p)));
		vec2 grad_dome = -p / z_dome;
		vec2 grad_total = grad_dome - bump_sum;
		normal = normalize(vec3(-grad_total, 1.0));
	}

	vec3 light_dir = sn_light_dir(highlight_position);
	vec3 final_color = sn_disk_color(normal, light_dir, tint_color.rgb, tint_mix, allocated, highlight_intensity);

	float r2 = dot(p, p);
	float edge_alpha = 1.0 - smoothstep(0.96, 1.0, r2);
	COLOR = vec4(final_color, edge_alpha * vision_field_dim(world_pos));
}

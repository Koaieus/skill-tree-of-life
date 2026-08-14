extends GutTest

## Pins `height_mesa()` in `rim_ring.gdshader` to the authored Curve it replaced.
##
## Every SkillNode in the game used to carry `rim_ring_curve.tres` as a CUSTOM
## height curve, which forced each rim onto a private ShaderMaterial + a private
## 64-texel LUT — one draw call per rim at 500-2500 nodes, defeating the whole
## shared-material design (`.claude/rules/rendering-performance.md`). The curve
## was baked into the shader as preset 5 (MESA) to get the batching back.
##
## GDScript cannot call a shader function, so this asserts the closed form
## *as transcribed here* against the Curve — which is exactly the thing that can
## silently drift. **If you edit `height_mesa` in the shader, edit `_mesa` below
## to match.** `rim_ring_curve.tres` is otherwise unreferenced now; it is kept
## precisely so this comparison has something to compare against.

const _CURVE := preload("res://skill_node/visuals/rim_ring_curve.tres")
## RimRing has no `class_name` — leaf components in this family deliberately
## don't declare one (see `.claude/rules/skill-node-visuals.md`), so the enum and
## the constant are reachable only through the script resource.
const _RIM_RING := preload("res://skill_node/visuals/rim_ring.gd")

## Byte-for-byte the shader's `height_mesa`, in GDScript.
func _mesa(t: float) -> float:
	return clampf(t * (5.5699086 + t * (-5.2543735 + t * -0.3155351)), 0.0, 1.0)


## `RimRing._bake_lut` clamps `curve.sample()` into [0,1] before writing the
## texel, so the clamp — not the raw Curve, which peaks at ~1.43 — is what
## actually shipped. The closed form must match the CLAMPED curve.
func test_mesa_preset_reproduces_the_authored_curve() -> void:
	for i in 65:
		var t := float(i) / 64.0
		var baked := clampf(_CURVE.sample(t), 0.0, 1.0)
		assert_almost_eq(_mesa(t), baked, 0.0005,
			"mesa preset diverges from rim_ring_curve.tres at t=%.4f" % t)


## The shape that makes this preset distinct from the other four: it is the only
## one that comes back DOWN to zero at the outer edge, giving the rim a rounded
## outer lip instead of the hard shoulder level/terrace/smooth/sharpen all end on.
func test_mesa_rises_plateaus_and_falls_back_to_zero() -> void:
	assert_almost_eq(_mesa(0.0), 0.0, 0.0001, "starts flat at the crest")
	assert_almost_eq(_mesa(1.0), 0.0, 0.0001, "returns to zero at the outer edge")
	assert_almost_eq(_mesa(0.5), 1.0, 0.0001, "plateaus at full height mid-band")
	assert_lt(_mesa(0.1), 1.0, "still climbing early in the bevel")
	assert_lt(_mesa(0.95), 1.0, "already rolling off late in the bevel")


## The escape hatch must keep index 4: scenes author `height_preset = 4` and the
## shader's LUT branch is keyed on it, so appending MESA anywhere but the end
## would silently repoint every authored CUSTOM rim.
func test_custom_keeps_index_four_and_mesa_appends_after_it() -> void:
	assert_eq(_RIM_RING.CUSTOM_PRESET_INDEX, 4)
	assert_eq(int(_RIM_RING.HeightPreset.CUSTOM), 4, "CUSTOM must not be renumbered")
	assert_eq(int(_RIM_RING.HeightPreset.MESA), 5, "MESA is the shader's branch 5")


## The point of the whole exercise: the shipped composite must be back on a
## closed-form preset, not the per-instance LUT path.
func test_shipped_composite_no_longer_takes_the_unbatched_custom_path() -> void:
	var composite := preload("res://skill_node/visuals/node_visuals_composite.tscn").instantiate()
	add_child_autofree(composite)
	await get_tree().process_frame
	var rim: Node = composite.get_node("%RimRing")
	assert_eq(int(rim.height_preset), int(_RIM_RING.HeightPreset.MESA))
	assert_null(rim.rim_height_style,
		"a non-null curve forces height_preset to CUSTOM and mints a private material")

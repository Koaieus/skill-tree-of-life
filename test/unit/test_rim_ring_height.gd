extends GutTest
## RimRing height-profile material routing (#16). A built-in preset must stay on
## the shared/batched static material; a custom `rim_height_style` Curve must opt
## into a per-instance (resource_local_to_scene) material carrying the baked LUT.
## Guards the fix where the custom path used to set instance-uniforms via
## material.set_shader_parameter() (a no-op), so a Curve did nothing.
##
## HeightPreset ints (rim_ring.gd has no class_name to reference the enum by):
## LEVEL=0, TERRACE=1, SMOOTH=2, SHARPEN=3.

const RimScene := preload("res://skill_node/visuals/rim_ring.tscn")


func test_preset_uses_shared_batched_material() -> void:
	var rim = add_child_autofree(RimScene.instantiate())
	await get_tree().process_frame

	rim.height_preset = 2  # SMOOTH
	assert_false(rim.material.resource_local_to_scene,
		"a built-in preset stays on the shared batched material")


func test_custom_curve_opts_into_local_material_with_lut() -> void:
	var rim = add_child_autofree(RimScene.instantiate())
	await get_tree().process_frame

	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(1.0, 1.0))
	rim.rim_height_style = curve
	assert_true(rim.material.resource_local_to_scene,
		"a custom Curve opts into a per-instance material")
	assert_not_null(rim.material.get_shader_parameter("height_lut"),
		"the per-instance material carries the baked LUT sampler")


func test_clearing_curve_returns_to_shared_material() -> void:
	var rim = add_child_autofree(RimScene.instantiate())
	await get_tree().process_frame

	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(1.0, 1.0))
	rim.rim_height_style = curve
	assert_true(rim.material.resource_local_to_scene, "custom while a Curve is set")

	rim.height_preset = 0  # LEVEL — setter clears rim_height_style
	assert_false(rim.material.resource_local_to_scene,
		"selecting a preset returns to the shared batched material")


func test_editing_curve_points_live_rebakes_lut() -> void:
	var rim = add_child_autofree(RimScene.instantiate())
	await get_tree().process_frame

	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(1.0, 1.0))
	rim.rim_height_style = curve
	var lut_before = rim.material.get_shader_parameter("height_lut")

	# In-place edit (what dragging a point in the inspector does) → Curve emits
	# `changed` → the rim re-bakes a fresh LUT without a whole-resource reassign.
	curve.add_point(Vector2(0.5, 0.5))
	var lut_after = rim.material.get_shader_parameter("height_lut")
	assert_ne(lut_before, lut_after, "editing the Curve re-bakes a new LUT live")

extends GutTest

## TargetReticle standalone: no parent, no SkillNode, no HighlightController.
## The root owns one derived fact (modulate from tint + tier); the spinner's
## rotation advances by its own exported rate.

const _RETICLE_PATH := "res://ui/indicator/target_reticle.tscn"


func _make() -> Node2D:
	var scene := load(_RETICLE_PATH) as PackedScene
	assert_not_null(scene, "target_reticle.tscn must exist")
	if scene == null:
		return null
	var r := scene.instantiate() as Node2D
	add_child_autofree(r)
	return r


func test_modulate_derives_from_tint_and_tier() -> void:
	var r := _make()
	if r == null:
		return
	var tint := Color(0.2, 0.7, 1.0, 0.95)
	r.set("tint", tint)
	r.set("tier", Emissive.Tier.LABEL)
	assert_eq(r.modulate, Emissive.at(tint, Emissive.stops(Emissive.Tier.LABEL)))


func test_changing_tier_rederives_modulate() -> void:
	var r := _make()
	if r == null:
		return
	var tint := Color(1.0, 0.2, 0.2, 0.95)
	r.set("tint", tint)
	r.set("tier", Emissive.Tier.LABEL)
	r.set("tier", Emissive.Tier.ALERT)
	assert_eq(r.modulate, Emissive.at(tint, Emissive.stops(Emissive.Tier.ALERT)))


func test_spinner_advances_by_exported_rate() -> void:
	var r := _make()
	if r == null:
		return
	r.set_process(false)
	var spinner := r.get_node("%Spinner") as Node2D
	var before := spinner.rotation
	var dt := 0.25
	r.call("_process", dt)
	var expected := deg_to_rad(float(r.get("spin_degrees_per_second"))) * dt
	assert_almost_eq(spinner.rotation - before, expected, 1e-5)


func test_zero_spin_leaves_rotation_unchanged() -> void:
	var r := _make()
	if r == null:
		return
	r.set_process(false)
	r.set("spin_degrees_per_second", 0.0)
	var spinner := r.get_node("%Spinner") as Node2D
	var before := spinner.rotation
	r.call("_process", 0.5)
	assert_eq(spinner.rotation, before)

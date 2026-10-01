extends GutTest

## SquadMarker standalone: no parent, no SkillNode, no HighlightController.
## The chevron group turns to `facing` over `aim_turn_seconds` (driven here
## by calling `_process` by hand); `charge` 0 is the muted look.

const _MARKER_PATH := "res://ui/indicator/squad_marker.tscn"
const _ARMED_PATH := "res://ui/indicator/squad_marker_armed.tscn"


func _make(path: String = _MARKER_PATH) -> Node2D:
	var scene := load(path) as PackedScene
	assert_not_null(scene, "%s must exist" % path)
	if scene == null:
		return null
	var m := scene.instantiate() as Node2D
	add_child_autofree(m)
	m.set_process(false)
	return m


func _chevron_angle(m: Node2D) -> float:
	return (m.get_node("%Chevrons") as Node2D).rotation


func test_zero_turn_time_aims_immediately() -> void:
	var m := _make()
	if m == null:
		return
	m.set("aim_turn_seconds", 0.0)
	m.set("facing", Vector2.RIGHT)
	m.set("facing", Vector2(-1, 1))
	assert_almost_eq(_chevron_angle(m), Vector2(-1, 1).angle(), 1e-5)


func test_first_facing_snaps() -> void:
	var m := _make()
	if m == null:
		return
	m.set("facing", Vector2.DOWN)
	assert_almost_eq(_chevron_angle(m), Vector2.DOWN.angle(), 1e-5)


func test_a_new_facing_is_reached_after_the_turn_time() -> void:
	var m := _make()
	if m == null:
		return
	m.set("aim_turn_seconds", 0.2)
	m.set("facing", Vector2.RIGHT)
	m.set("facing", Vector2.DOWN)
	assert_almost_eq(_chevron_angle(m), 0.0, 1e-5, "the swing has not started yet")
	m.call("_process", 0.1)
	assert_true(_chevron_angle(m) > 0.0 and _chevron_angle(m) < Vector2.DOWN.angle(), "mid-swing")
	m.call("_process", 0.1)
	assert_almost_eq(_chevron_angle(m), Vector2.DOWN.angle(), 1e-5)


func test_charge_zero_is_muted_and_charge_above_zero_is_lit() -> void:
	var m := _make()
	if m == null:
		return
	var tint := Color(0.2, 0.95, 0.8, 0.9)
	m.set("tint", tint)
	m.set("charge", 0.0)
	assert_true(m.get("spent"), "charge 0 is spent")
	assert_eq(m.modulate, Emissive.at(m.get("spent_tint"), Emissive.stops(Emissive.Tier.INERT)))
	m.set("charge", 0.4)
	assert_false(m.get("spent"))
	assert_eq(m.modulate, Emissive.at(tint, Emissive.stops(m.get("tier"))))


func test_armed_variant_is_brighter() -> void:
	var base := _make()
	var armed := _make(_ARMED_PATH)
	if base == null or armed == null:
		return
	assert_gt(int(armed.get("tier")), int(base.get("tier")))

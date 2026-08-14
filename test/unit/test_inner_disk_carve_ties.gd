extends GutTest

## InnerDisk's slot-B wiring: when EmblemResolver hands back more than one
## SPELL-priority tie (#206's widened distribution can stack 2+ SpellGrants
## on one node), a second carve should land in InnerDisk's own slot-B state
## so inner_disk.gdshader can alternate between them. The shader's own
## crossfade animation isn't assertable headless (see godot-shaders.md) — this
## covers only the GDScript-side wiring: which shape lands in which slot.

const _DISK_SCENE := preload("res://skill_node/visuals/inner_disk.tscn")
const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")
const TextureCarveShape = preload("res://skill_node/visuals/emblem/texture_carve_shape.gd")

var _disk: Node


func before_each() -> void:
	_disk = _DISK_SCENE.instantiate()
	add_child_autofree(_disk)


func _mk_carve(prio: int, source: StringName) -> EmblemSpec:
	var shape := TextureCarveShape.new()
	return shape.carve(prio, source)


func test_single_tie_leaves_slot_b_empty() -> void:
	var a := _mk_carve(EmblemSpec.Priority.SPELL, &"spell_a")
	_disk.set_carve(a, [a])
	assert_null(_disk._carved_shape_b, "one tie → nothing for slot B")


func test_no_ties_array_leaves_slot_b_empty() -> void:
	var a := _mk_carve(EmblemSpec.Priority.SPELL, &"spell_a")
	_disk.set_carve(a)  # default ties = []
	assert_null(_disk._carved_shape_b, "no ties supplied → nothing for slot B")


func test_second_tie_lands_in_slot_b() -> void:
	var a := _mk_carve(EmblemSpec.Priority.SPELL, &"spell_a")
	var b := _mk_carve(EmblemSpec.Priority.SPELL, &"spell_b")
	_disk.set_carve(a, [a, b])
	assert_eq(_disk._carved_shape_b, b.shape, "second tie becomes slot B's shape")
	assert_ne(_disk._carved_shape_b, _disk._carved_shape, "slot A and B carry distinct shapes")


func test_third_tie_is_dropped_not_a_second_slot() -> void:
	var a := _mk_carve(EmblemSpec.Priority.SPELL, &"spell_a")
	var b := _mk_carve(EmblemSpec.Priority.SPELL, &"spell_b")
	var c := _mk_carve(EmblemSpec.Priority.SPELL, &"spell_c")
	_disk.set_carve(a, [a, b, c])
	assert_eq(_disk._carved_shape_b, b.shape, "only ties[1] is used — a third collision is dropped, not queued")


## No CarveAtlas registration in this fixture, so slot B degrades to NO_SLICE
## rather than crashing — the same honest-empty fallback slot A already has.
func test_unregistered_shape_degrades_to_no_slice_not_a_crash() -> void:
	var a := _mk_carve(EmblemSpec.Priority.SPELL, &"spell_a")
	var b := _mk_carve(EmblemSpec.Priority.SPELL, &"spell_b")
	_disk.set_carve(a, [a, b])
	assert_eq(_disk.effective_carve_slice_b, -1, "unpacked LUT degrades to NO_SLICE")

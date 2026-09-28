@tool
extends GutTest

## The core-drag ghost's scene contract, which PlayerInputController relies
## on: configure dresses the presence, place snaps or trails it (the bloom
## only while snapped), set_badge trails the cursor.

const _GHOST_SCENE := preload("res://skill_node/visuals/core_drag_ghost.tscn")
const _CORE_CLASS := preload("res://entity/core/balanced_core.tres")

var _ghost: CoreDragGhost


func before_each() -> void:
	_ghost = _GHOST_SCENE.instantiate()
	add_child_autofree(_ghost)


func after_each() -> void:
	_ghost = null


func _presence() -> CorePresence:
	return _ghost.get_node(^"%Presence")


func _bloom() -> Node2D:
	return _presence().get_node(^"CoreSigilBloom")


func test_configure_null_entity_is_a_plain_core() -> void:
	_ghost.configure(null, 32.0)
	assert_null(_presence().get_look(), "no core class, no look")
	assert_false(_bloom().visible, "bloom waits for a snap")


func test_configure_wears_the_entity_core_look() -> void:
	var entity: Entity = autofree(Entity.new())
	entity.core_class = _CORE_CLASS
	_ghost.configure(entity, 32.0)
	assert_eq(_presence().get_look() != null, _CORE_CLASS.core_look != null,
			"the presence wears the core class's look")
	assert_false(_bloom().visible, "bloom waits for a snap")


func test_place_snapped_shows_bloom_at_snapped_alpha() -> void:
	_ghost.configure(null, 32.0)
	_ghost.place(Vector2(40, 50), true)
	assert_true(_bloom().visible)
	assert_almost_eq(_presence().modulate.a, _ghost.snapped_alpha, 0.001)
	assert_eq(_presence().global_position, Vector2(40, 50))


func test_place_free_hides_bloom_at_free_alpha() -> void:
	_ghost.configure(null, 32.0)
	_ghost.place(Vector2(40, 50), true)
	_ghost.place(Vector2(7, 9), false)
	assert_false(_bloom().visible)
	assert_almost_eq(_presence().modulate.a, _ghost.free_alpha, 0.001)
	assert_eq(_presence().global_position, Vector2(7, 9))


func test_set_badge_trails_the_cursor() -> void:
	var cursor := Vector2(100, 200)
	_ghost.set_badge("x", cursor)
	var badge: Label = _ghost.get_node(^"%Badge")
	assert_eq(badge.text, "x")
	assert_eq(badge.global_position, cursor + _ghost.badge_offset)

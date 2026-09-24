extends GutTest
## CorePresence wiring (#128, docs/domain/skillnode-emblem.md): CoreHalos +
## CoreSigilBloom replace the old star CoreMarker, gated on is_core, fed the
## owner's core-class sigil. FX timing (glide/extinguish/reignite) is an
## eyeball-only concern (see the sandbox); this locks in the structure.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _BALANCED_CORE := preload("res://entity/core/balanced_core.tres")
const _GEAR := preload("res://skill_node/visuals/core_gear.tscn")
const _GIMBAL := preload("res://skill_node/visuals/core_gimbal.tscn")
const _HALOS := preload("res://skill_node/visuals/core_halos.gd")

var _graph: Graph
var _node: SkillNode
var _entity: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_node.name = "N0"
	_graph.skill_nodes_container.add_child(_node)

	_entity = autofree(Entity.new())
	_entity.display_name = "Coreholder"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_entity.core_class = _BALANCED_CORE
	_entity.core_location = _node
	_graph.add_child(_entity)


func _core_presence():
	return _node.get_node("Visuals/NodeVisualsComposite/ShaderStack/CorePresence")


func test_core_marker_is_gone() -> void:
	assert_null(_node.get_node_or_null("Visuals/CoreMarker"), "CoreMarker retired in favor of CorePresence (#128)")
	assert_false(_node.has_method("play_core_slide_from") and _node.get("core_marker") != null,
		"no core_marker property should remain")


func test_composite_children_still_resolve_by_unique_name() -> void:
	var comp := _node.get_node("Visuals/NodeVisualsComposite")
	assert_not_null(comp.get_node_or_null("ShaderStack/InnerDisk"))
	assert_not_null(comp.get_node_or_null("ShaderStack/RimRing"))
	assert_not_null(_core_presence())


func test_core_presence_hidden_when_not_core() -> void:
	_entity.core_location = null
	_node.owned_by = _entity
	await get_tree().process_frame
	assert_false(_core_presence().visible, "not the core node -> CorePresence hidden")


func test_core_presence_visible_and_sigil_set_when_core() -> void:
	_node.owned_by = _entity
	await get_tree().process_frame
	var presence = _core_presence()
	assert_true(presence.visible, "core node -> CorePresence visible")
	var bloom := presence.get_node(^"CoreSigilBloom")
	assert_eq(bloom.sigil, _entity.core_class.sigil, "set_core_sigil reached CoreSigilBloom")


func test_glide_from_repositions_halos_and_completes() -> void:
	_node.owned_by = _entity
	await get_tree().process_frame
	var presence = _core_presence()
	var halos := _look(presence) as Node2D
	presence.glide_from(Vector2(40, 0), 0.05)
	assert_eq(halos.position, Vector2(40, 0), "halo starts offset at the old node's relative position")
	await get_tree().create_timer(0.15).timeout
	assert_true(halos.position.distance_to(Vector2.ZERO) < 0.01, "halo glides back to zero")


func _look(presence) -> Node:
	var slot: Node = presence.get_node(^"Slot")
	return slot.get_child(0) if slot.get_child_count() > 0 else null


func _entity_wearing(look: PackedScene, label: String) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.display_name = label
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	var cls := _BALANCED_CORE.duplicate() as CoreClass
	cls.core_look = look
	e.core_class = cls
	_graph.add_child(e)
	return e


func test_slot_swaps_on_set_look_and_is_idempotent() -> void:
	var presence = _core_presence()
	var slot: Node = presence.get_node_or_null(^"Slot")
	assert_not_null(slot, "CorePresence authors an empty Slot")
	if slot == null:
		return
	presence.entity_tint = Color(0.2, 0.4, 0.9)
	presence.configure(40.0)
	presence.set_look(_GEAR)
	assert_eq(slot.get_child_count(), 1, "one look in the slot")
	var gear: Node = _look(presence)
	assert_eq(gear.halo_style, _HALOS.CoreHaloStyle.COG, "the gear is a CoreHalos at COG")
	presence.set_look(_GEAR)
	assert_same(_look(presence), gear, "same scene again is a no-op")
	presence.set_look(_GIMBAL)
	assert_eq(slot.get_child_count(), 1, "the gear left the slot")
	assert_true(gear.is_queued_for_deletion(), "the gear is freed")
	var gimbal: Node = _look(presence)
	assert_eq(gimbal.scene_file_path, _GIMBAL.resource_path, "a core_gimbal leaf is in the slot")
	assert_eq(gimbal.entity_tint, Color(0.2, 0.4, 0.9), "entity_tint already pushed")
	assert_eq(gimbal.radius, 40.0, "radius already pushed")
	presence.set_look(null)
	assert_eq(slot.get_child_count(), 0, "null empties the slot")


func test_look_follows_the_owners_core_class() -> void:
	var gear_owner := _entity_wearing(_GEAR, "GearWearer")
	gear_owner.core_location = _node
	_node.owned_by = gear_owner
	await get_tree().process_frame
	var look: Node = _look(_core_presence())
	assert_not_null(look, "a core node wears its owner's look")
	if look != null:
		assert_eq(look.scene_file_path, _GEAR.resource_path, "the gear class shows the gear")

	var gimbal_owner := _entity_wearing(_GIMBAL, "GimbalWearer")
	gimbal_owner.core_location = _node
	_node.owned_by = gimbal_owner
	await get_tree().process_frame
	look = _look(_core_presence())
	assert_not_null(look)
	if look != null:
		assert_eq(look.scene_file_path, _GIMBAL.resource_path, "re-owned: the gimbal class shows the gimbal")

	var other := _SKILL_NODE_SCENE.instantiate() as SkillNode
	other.name = "N1"
	_graph.skill_nodes_container.add_child(other)
	other.owned_by = gimbal_owner
	await get_tree().process_frame
	var other_slot: Node = other.get_node(
		"Visuals/NodeVisualsComposite/ShaderStack/CorePresence/Slot")
	assert_eq(other_slot.get_child_count(), 0, "a non-core node has an empty slot")

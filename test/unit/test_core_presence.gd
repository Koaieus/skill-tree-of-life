extends GutTest
## CorePresence wiring (#128, docs/domain/skillnode-emblem.md): CoreHalos +
## CoreSigilBloom replace the old star CoreMarker, gated on is_core, fed the
## owner's core-class sigil. FX timing (glide/extinguish/reignite) is an
## eyeball-only concern (see the sandbox); this locks in the structure.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _BALANCED_CORE := preload("res://entity/core/balanced_core.tres")

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


func _core_presence() -> Node2D:
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
	var presence := _core_presence()
	assert_true(presence.visible, "core node -> CorePresence visible")
	var bloom := presence.get_node(^"CoreSigilBloom")
	assert_eq(bloom.sigil, _entity.core_class.sigil, "set_core_sigil reached CoreSigilBloom")


func test_glide_from_repositions_halos_and_completes() -> void:
	_node.owned_by = _entity
	await get_tree().process_frame
	var presence := _core_presence()
	var halos := presence.get_node(^"CoreHalos")
	presence.glide_from(Vector2(40, 0), 0.05)
	assert_eq(halos.position, Vector2(40, 0), "halo starts offset at the old node's relative position")
	await get_tree().create_timer(0.15).timeout
	assert_true(halos.position.distance_to(Vector2.ZERO) < 0.01, "halo glides back to zero")

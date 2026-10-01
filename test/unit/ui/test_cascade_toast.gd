extends GutTest

## A forced-dealloc cascade announces itself ONCE, after its loop, with the
## summed HP chip and wound — and the floater layer turns that one fact into one
## merged toast at the core: the chip in the damage style, the wound as a small
## suffix in the wound tint. The shadow (a preview) and an entity's death strip
## (`charge=false`) announce nothing.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _DIRECTOR_SCENE := preload("res://ui/floating_number_layer/floater_director.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = []
	# Line core(N0) – N1 – N2 – N3; the cascade under test is N1..N3.
	for i in 4:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	for i in 3:
		var e := _EDGE_SCENE.instantiate() as Edge
		e.from = _nodes[i]
		e.to = _nodes[i + 1]
		_graph.edges_container.add_child(e)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Victim"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)
	await get_tree().process_frame
	for n in _nodes:
		_alloc.force_allocate(_entity, n)
	_entity.core_location = _nodes[0]
	_entity.stat_board.health.base_value = 100.0
	_entity.stat_board.health.set_current(100.0)
	_entity.stat_board.dealloc_damage.base_value = 1.0


func _cascade_nodes(combat: EntityCombat) -> Array[NodeCombat]:
	var out: Array[NodeCombat] = []
	for i in range(1, 4):
		out.append(combat.shadow_for(_nodes[i]) if combat.host == null else _nodes[i].get_combat())
	return out


# ── The source ───────────────────────────────────────────────────────────────

func test_live_cascade_emits_once_with_the_sums() -> void:
	watch_signals(Events)
	var combat := _entity.get_combat()
	combat.apply_cascade(_cascade_nodes(combat), _alloc)
	assert_signal_emit_count(Events, "entity_cascade_charged", 1, "one cascade, one announcement")
	assert_signal_emitted_with_parameters(Events, "entity_cascade_charged", [_entity, 3, 3])


func test_shadow_cascade_emits_nothing() -> void:
	watch_signals(Events)
	var shadow := _entity.get_combat().snapshot()
	shadow.apply_cascade(_cascade_nodes(shadow))
	shadow.free_shadow()
	assert_signal_emit_count(Events, "entity_cascade_charged", 0, "a preview never toasts")


func test_uncharged_cascade_emits_nothing() -> void:
	watch_signals(Events)
	var combat := _entity.get_combat()
	combat.apply_cascade(_cascade_nodes(combat), _alloc, false)
	assert_signal_emit_count(Events, "entity_cascade_charged", 0, "a death strip sums to 0")


# ── The toast ────────────────────────────────────────────────────────────────

func test_director_raises_one_merged_toast() -> void:
	var director := _DIRECTOR_SCENE.instantiate() as FloaterDirector
	director.vision_system = null
	add_child_autofree(director)
	Events.entity_cascade_charged.emit(_entity, 3, 3)
	var toasts: Array[FloaterToast] = []
	for t in director.renderer.get_children():
		if t is FloaterToaster:
			for c in (t as FloaterToaster).get_node("VBoxContainer").get_children():
				toasts.append(c as FloaterToast)
	assert_eq(toasts.size(), 1, "one toast per cascade, no separate WOUNDS toast")
	if toasts.size() != 1:
		return
	assert_eq(toasts[0].label.text, "3", "the chip, in the damage style")
	assert_eq(toasts[0].suffix.text, "+3 W", "the wound rides as the suffix")
	assert_true(toasts[0].suffix.visible, "and the suffix is shown")

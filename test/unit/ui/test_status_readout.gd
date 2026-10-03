extends GutTest

## A row's count reaches the local viewer only when its def's `visible_if`
## holds for one of the machine's eyes; otherwise every reader shows
## presence — [method StatusReadout.shown_power] answers `-1`, the tooltip
## row drops the number, and the node tint blends as if power were 1.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _ROW_SCENE := preload("res://ui/tooltip_fan/status_row.tscn")

var _def: StatusDef
var _viewer_a: Entity
var _viewer_b: Entity
var _row_a: NodeStatus
var _row_b: NodeStatus


func before_each() -> void:
	_def = StatusDef.new()
	_def.id = &"test_scout"
	_def.display_name = "Scouted"
	_def.tint = Color(0.2, 0.9, 0.3)
	_def.power_max = 10.0
	_def.group_by = "camp_id"
	_def.visible_if = "camp_id == viewer_camp_id"
	_viewer_a = _viewer(&"camp_a")
	_viewer_b = _viewer(&"camp_b")
	_row_a = _row(9, &"camp_a")
	_row_b = _row(2, &"camp_b")


func _viewer(camp: StringName) -> Entity:
	var e: Entity = autofree(Entity.new())
	var f := Faction.new()
	f.id = camp
	e.faction = f
	return e


func _row(power: int, camp: StringName) -> NodeStatus:
	var r := NodeStatus.new(_def, power, camp)
	r.camp_id = camp
	return r


func _viewers(e: Entity) -> Array[Entity]:
	var out: Array[Entity] = [e]
	return out


# (a) a camp-A viewer reads A's count, B is presence only.
func test_own_camp_reads_count_foreign_camp_is_presence() -> void:
	assert_eq(StatusReadout.shown_power(_row_a, _viewers(_viewer_a)), 9)
	assert_eq(StatusReadout.shown_power(_row_b, _viewers(_viewer_a)), -1)


# (d) swapping the eyes to camp B flips (a).
func test_swapping_viewers_flips_what_is_read() -> void:
	assert_eq(StatusReadout.shown_power(_row_a, _viewers(_viewer_b)), -1)
	assert_eq(StatusReadout.shown_power(_row_b, _viewers(_viewer_b)), 2)


func test_any_viewer_reading_it_shows_the_count() -> void:
	var both: Array[Entity] = [_viewer_b, _viewer_a]
	assert_eq(StatusReadout.shown_power(_row_a, both), 9)
	assert_eq(StatusReadout.shown_power(_row_b, both), 2)


func test_no_eyes_means_no_fog_counts_shown() -> void:
	assert_eq(StatusReadout.shown_power(_row_b, [] as Array[Entity]), 2)


func test_shared_row_always_reads_its_count() -> void:
	_def.group_by = ""
	_def.visible_if = ""
	var shared := NodeStatus.new(_def, 7)
	assert_eq(StatusReadout.shown_power(shared, _viewers(_viewer_b)), 7)


# (b) the tooltip row for B, seen by camp A, carries no digit.
func test_presence_row_text_has_no_digit() -> void:
	var node := _live_node()
	node.status_viewers = _viewers(_viewer_a)
	node.get_combat().apply_status(_def, 2.0, &"camp_b", 0)
	var status: NodeStatus = node.get_combat().get_statuses()[0]
	var row := _ROW_SCENE.instantiate() as StatusRow
	add_child_autofree(row)
	row.bind(status, node.get_combat())
	assert_eq(row._label.text, "Scouted")
	var digits := RegEx.create_from_string("\\d")
	assert_null(digits.search(row._label.text), "presence leaks no count")


# (c) a node holding only B tints at the power-1 blend, same as a 1-stack row.
func test_presence_tint_matches_a_one_stack_row() -> void:
	var node := _live_node()
	node.status_viewers = _viewers(_viewer_a)
	node.get_combat().apply_status(_def, 1.0, &"camp_a", 0)
	var one_stack: Color = node.node_visuals().status_tint
	node.get_combat().release_statuses()
	node.get_combat().apply_status(_def, 9.0, &"camp_b", 0)
	assert_eq(node.node_visuals().status_tint, one_stack, "9 foreign stacks tint like 1")
	node.status_viewers = _viewers(_viewer_b)
	assert_ne(node.node_visuals().status_tint, one_stack, "own camp's 9 tints at full count")


func _live_node() -> SkillNode:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	var owner_e: Entity = autofree(Entity.new())
	owner_e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.add_child(owner_e)
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(node)
	alloc.force_allocate(owner_e, node)
	return node

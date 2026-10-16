extends GutTest

## [StatusOverlay] (ui/status_overlay/): the projected-damage segment and the
## icon row a bar draws for its host's status rows. Reads the overlay's
## computed model ([member StatusOverlay.segments] / [member StatusOverlay.icons]),
## never pixels.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _OVERLAY_SCENE := preload("res://ui/status_overlay/status_overlay.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


## A status whose projection is a fixed amount per stack — the overlay's maths
## is under test here, not any real DoT's balance.
class FixedDef extends StatusDef:
	var per_stack := 1.0

	func projected_damage(_host, power: float) -> float:
		return power * per_stack


var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_node.name = "N0"
	_graph.skill_nodes_container.add_child(_node)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_entity = autofree(Entity.new())
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)
	await get_tree().process_frame
	_alloc.force_allocate(_entity, _node)
	_entity.core_location = _node
	await get_tree().process_frame


func _def(id: StringName, per_stack: float, with_icon := true, display_max := 0.0) -> FixedDef:
	var d := FixedDef.new()
	d.id = id
	d.display_name = String(id).capitalize()
	d.power_max = 10.0
	d.decay = FlatDecay.new(1.0)
	d.per_stack = per_stack
	d.display_max = display_max
	var ident := Identity.new()
	ident.id = id
	ident.tint = Color(0.2, 0.9, 0.3)
	ident.icon = PlaceholderTexture2D.new() if with_icon else null
	d.identity = ident
	return d


func _standalone_overlay(size: Vector2) -> StatusOverlay:
	var frame := Control.new()
	frame.size = size
	add_child_autofree(frame)
	var o := _OVERLAY_SCENE.instantiate() as StatusOverlay
	frame.add_child(o)
	return o


func _segment_width(o: StatusOverlay) -> float:
	var w := 0.0
	for s in o.segments:
		w += s.rect.size.x
	return w


func _icon_ids(o: StatusOverlay) -> Array[StringName]:
	var out: Array[StringName] = []
	for e in o.icons:
		out.append(e.id)
	return out


# ── 1. Segment ───────────────────────────────────────────────────────────────

func test_segment_is_projected_over_max_and_ends_at_the_fill_tip() -> void:
	var o := _standalone_overlay(Vector2(100, 10))
	var host := _node.get_combat()
	o.bind(host, _node.statuses_changed)
	o.set_fill(30.0, 60.0)
	host.apply_status(_def(&"poison", 2.0), 3.0)
	var projected := host.projected_status_damage()
	assert_gt(projected, 0.0, "fixture: the row projects damage")
	assert_eq(o.segments.size(), 1, "one damaging row, one band")
	assert_almost_eq(_segment_width(o), projected / 60.0 * 100.0, 0.01,
			"band width = projected / max of the bar's width")
	assert_almost_eq(o.segments[-1].rect.end.x, 50.0, 0.01, "band ends at the fill tip")
	assert_eq(o.segments[0].color, Color(0.2, 0.9, 0.3), "coloured by the identity tint")


func test_segment_follows_the_drawn_fill() -> void:
	var o := _standalone_overlay(Vector2(100, 10))
	var host := _node.get_combat()
	o.bind(host, _node.statuses_changed)
	host.apply_status(_def(&"poison", 1.0), 2.0)
	o.set_fill(45.0, 60.0)
	assert_almost_eq(o.segments[-1].rect.end.x, 75.0, 0.01, "a fill move re-tips the band")


# ── 2. Two hosts, never merged ──────────────────────────────────────────────

func test_core_bar_draws_entity_rows_and_node_bar_draws_node_rows() -> void:
	var node_overlay := _node.get_node("Visuals/HealthBar/StatusOverlay") as StatusOverlay
	var core_bar := _node.get_node("Visuals/CoreHealthBar") as ProgressBar
	var core_overlay := core_bar.get_node("StatusOverlay") as StatusOverlay
	assert_not_null(node_overlay, "the node bar composes an overlay")
	assert_not_null(core_overlay, "the core bar composes an overlay")
	if node_overlay == null or core_overlay == null:
		return
	_node.get_combat().apply_status(_def(&"shell_rot", 1.0), 2.0)
	var body := _entity.get_combat()
	body.apply_status(_def(&"body_rot", 2.0), 3.0)
	assert_eq(_icon_ids(node_overlay), [&"shell_rot"] as Array[StringName], "node bar: node rows only")
	assert_eq(_icon_ids(core_overlay), [&"body_rot"] as Array[StringName], "core bar: entity rows only")
	var hp_max := float(_entity.stat_board.health.value)
	assert_almost_eq(_segment_width(core_overlay),
			body.projected_status_damage() / hp_max * core_overlay.size.x, 0.01,
			"core band = entity projection against health")


# ── 3. Icon row ──────────────────────────────────────────────────────────────

func test_icon_row_lists_iconned_rows_in_order_with_counts_when_stacks_matter() -> void:
	var o := _standalone_overlay(Vector2(100, 10))
	var host := _node.get_combat()
	o.bind(host, _node.statuses_changed)
	o.set_fill(60.0, 60.0)
	host.apply_status(_def(&"stacky", 0.0, true, 5.0), 3.0)
	host.apply_status(_def(&"blank", 0.0, false), 1.0)
	host.apply_status(_def(&"single", 0.0, true, 0.0), 1.0)
	assert_eq(_icon_ids(o), [&"stacky", &"single"] as Array[StringName],
			"one entry per iconned row, row order, iconless skipped")
	assert_eq(o.icons[0].count, 3, "display_max > 1 shows the stack count")
	assert_eq(o.icons[1].count, -1, "display_max <= 1 shows no count")
	assert_lt(o.icons[0].rect.position.x, o.icons[1].rect.position.x, "laid out left to right")
	assert_eq(o.icons[0].rect.size, Vector2(o.icon_size, o.icon_size), "icon_size knob")
	assert_almost_eq(o.icons[1].rect.position.x - o.icons[0].rect.end.x, o.icon_gap, 0.01, "icon_gap knob")
	assert_true(o.segments.is_empty(), "damageless rows draw no band")


# ── 4. Zero rows ─────────────────────────────────────────────────────────────

func test_zero_rows_hides_the_overlay() -> void:
	var o := _standalone_overlay(Vector2(100, 10))
	var host := _node.get_combat()
	o.bind(host, _node.statuses_changed)
	o.set_fill(60.0, 60.0)
	assert_false(o.visible, "no rows: hidden, so no _draw")
	var d := _def(&"poison", 1.0)
	host.apply_status(d, 2.0)
	assert_true(o.visible, "a row shows it")
	host.remove_status(&"poison")
	assert_false(o.visible, "the last row gone: hidden again")

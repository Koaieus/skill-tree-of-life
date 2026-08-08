extends GutTest

## Regression for #400: a panel whose content grows past its authored envelope
## can push its unit's forced [member FanUnit.arrival_axis] out of
## [method FanAnchor.solve_route]'s satisfiable window. When that happens the
## solver falls back to `AUTO` *and* warns — and because [FanAnchorDriver]
## reroutes every participating unit every `_process` frame, an unsatisfiable
## forced axis floods the console for as long as the fixture is bound, not
## just once. Mounts the REAL `fan.tscn` (the same scene [TooltipFan] mounts)
## with the densest real content (8 addons) and asserts every unit that
## authors a forced axis still gets it honoured, not silently downgraded.

const _FAN := preload("res://ui/tooltip_fan/fan.tscn")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _BALANCED_CORE := preload("res://entity/core/balanced_core.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _ADDON_SCENES: Array[PackedScene] = [
	preload("res://skill_node/addons/spike_ring_addon.tscn"),
	preload("res://skill_node/addons/skill_dust_addon.tscn"),
	preload("res://skill_node/addons/bunker_addon.tscn"),
	preload("res://skill_node/addons/fortification_addon.tscn"),
]


func test_bound_content_at_max_addons_keeps_every_forced_axis_satisfiable() -> void:
	var graph := _GRAPH_SCENE.instantiate()
	add_child(graph)
	autofree(graph)
	var node := _NODE_SCENE.instantiate()
	graph.add_skill_node(node)
	var entity := Entity.new()
	entity.stat_board = _BOARD.duplicate(true) as StatBoard
	entity.core_class = _BALANCED_CORE
	entity.core_location = node
	entity.faction = _PLAYER_FACTION
	entity.display_name = "Dusk"
	entity.level = 12
	add_child(entity)
	autofree(entity)
	node.owned_by = entity
	for i in 8:
		node.add_child(_ADDON_SCENES[i % _ADDON_SCENES.size()].instantiate())

	var fan: Node = _FAN.instantiate()
	add_child(fan)
	autofree(fan)
	for m in fan.find_children("*", "FanUnit", true, false):
		var unit := m as FanUnit
		unit.bind(node, graph)
		unit.participating = unit.has_content()
	var driver := fan as FanAnchorDriver
	driver.node_radius = node.radius
	driver.refresh()
	for f in 3:
		await get_tree().process_frame

	for unit in fan.find_children("*", "FanUnit", true, false):
		var fan_unit := unit as FanUnit
		if fan_unit.arrival_axis == FanAnchor.Axis.AUTO:
			continue
		var trace: FanTrace = unit.get_node_or_null("%Trace")
		var panel: FanPanel = unit.get_node_or_null("%Panel")
		if trace == null or panel == null:
			continue
		var rect := FanAnchor.panel_rect_of(panel)
		var solved := FanAnchor.solve_route(trace.from_point, rect, trace.route_params(),
			fan_unit.arrival_axis, fan_unit.anchor_slide, fan_unit.trunk_length)
		var want_horizontal: bool = fan_unit.arrival_axis == FanAnchor.Axis.HORIZONTAL
		var got_horizontal: bool = solved.edge == FanAnchor.Edge.LEFT or solved.edge == FanAnchor.Edge.RIGHT
		assert_eq(got_horizontal, want_horizontal,
			"%s's forced axis must stay satisfiable at max bound content, not silently fall back to AUTO" % unit.name)

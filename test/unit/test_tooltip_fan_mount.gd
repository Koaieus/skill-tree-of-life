extends GutTest

## The sandbox tooltip mount: the real TooltipFan inside a world SubViewport,
## driven by explicit hover calls (never the global Events), gate held open,
## only the pinned units fanning out.

const _MOUNT_PATH := "res://addons/sandbox_host/components/tooltip_fan_mount.tscn"
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _mount
var _viewport: SubViewport
var _graph: Graph
var _rich: SkillNode
var _bare: SkillNode
var _entity: Entity


func before_each() -> void:
	var scene: PackedScene = load(_MOUNT_PATH) if ResourceLoader.exists(_MOUNT_PATH) else null
	assert_not_null(scene, "the mount scene exists")
	if scene == null:
		return
	_mount = scene.instantiate()
	add_child_autofree(_mount)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(800, 600)
	add_child_autofree(_viewport)
	_graph = _GRAPH_SCENE.instantiate()
	_viewport.add_child(_graph)
	_entity = Entity.new()
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_entity)
	_rich = _SKILL_NODE_SCENE.instantiate()
	_rich.position = Vector2(200, 200)
	_graph.skill_nodes_container.add_child(_rich)
	_bare = _SKILL_NODE_SCENE.instantiate()
	_bare.position = Vector2(500, 300)
	_graph.skill_nodes_container.add_child(_bare)
	# Owned core with an aura on it: every unit of fan.tscn has content, so the
	# filter — not a lack of content — is what keeps the rest down.
	_entity.core_location = _rich
	_rich.owned_by = _entity
	var effect := StatEffect.new()
	effect.display_name = "Aura"
	var mod := StatModifier.new()
	mod.stat_id = &"armor"
	mod.operation = StatModifier.Operation.ADD_BASE
	mod.value = 3.0
	_entity.grant_effect(effect).context.grant(mod, _rich)
	_mount.mount(_viewport, _graph)


func after_each() -> void:
	if is_instance_valid(_entity):
		_entity.core_location = null


func _participating() -> Array[StringName]:
	var out: Array[StringName] = []
	if _mount.fan == null or _mount.fan._current_fan == null:
		return out
	for n in _mount.fan._current_fan.find_children("*", "FanUnit", true, false):
		if (n as FanUnit).participating:
			out.append(n.name)
	out.sort()
	return out


func test_mount_puts_a_bound_fan_inside_the_world_viewport() -> void:
	if _mount == null:
		return
	assert_not_null(_mount.fan, "mount() built a fan")
	assert_eq(_mount.fan.get_viewport(), _viewport, "the fan shares the nodes' viewport")
	assert_eq(_mount.fan.graph, _graph, "bound to the live graph")
	assert_false(_mount.fan.listen_to_events, "driven by the mount, deaf to every other tab's hovers")


func test_hover_fans_out_exactly_the_pinned_units() -> void:
	if _mount == null:
		return
	_mount.hover(_rich)
	assert_eq(_participating(), [&"EffectReadout", &"NodeStats"] as Array[StringName])
	var stats: FanUnit = _mount.fan._current_fan.find_child("NodeStats", true, false)
	var frames := 0
	while stats.state == FanUnit.State.HIDDEN and frames < 120:
		await get_tree().process_frame
		frames += 1
	assert_ne(stats.state, FanUnit.State.HIDDEN, "the gate is held open: no Shift needed")


func test_a_global_hover_event_does_not_reach_the_mounted_fan() -> void:
	if _mount == null:
		return
	Events.skill_node_hovered.emit(_rich)
	assert_null(_mount.fan._current_fan, "another tab's hover leaves this fan alone")
	Events.skill_node_unhovered.emit()


func test_hovering_the_same_node_again_keeps_the_fan() -> void:
	if _mount == null:
		return
	_mount.hover(_rich)
	var first: Node = _mount.fan._current_fan
	_mount.hover(_rich)
	assert_same(_mount.fan._current_fan, first, "same node is a no-op")
	_mount.unhover()
	assert_null(_mount.fan._current_fan, "unhover retires it")


func test_motion_over_the_container_hovers_what_the_pick_returns() -> void:
	if _mount == null:
		return
	var container := Control.new()
	add_child_autofree(container)
	_mount.attach_motion(container, func(pos: Vector2) -> SkillNode:
		return _rich if pos.x < 300.0 else null)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(100, 100)
	container.gui_input.emit(motion)
	assert_not_null(_mount.fan._current_fan, "pointer over a node hovers it")
	motion.position = Vector2(400, 100)
	container.gui_input.emit(motion)
	assert_null(_mount.fan._current_fan, "pointer over empty space unhovers")


func test_remount_replaces_the_fan() -> void:
	if _mount == null:
		return
	var old: TooltipFan = _mount.fan
	_mount.hover(_rich)
	_mount.mount(_viewport, _graph)
	assert_ne(_mount.fan, old, "a rebuild mounts a fresh fan")
	assert_false(is_instance_valid(old) and not old.is_queued_for_deletion(), "the old one is retired")

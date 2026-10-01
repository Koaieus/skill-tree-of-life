extends GutTest

## NodeHighlightOverlay mounts one Indicator scene per node whose role has a
## scene in its IndicatorTheme, diffing on every repaint signal; every other
## role keeps the plain ring.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _THEME_SCRIPT_PATH := "res://ui/indicator/indicator_theme.gd"


class RoleMapProvider extends HighlightProvider:
	var roles: Dictionary = {}

	func get_node_role(node: SkillNode) -> HighlightRole:
		return roles.get(node, HighlightRole.NONE)


var _graph: Graph
var _nodes: Array[SkillNode]
var _ctl: HighlightController
var _overlay: NodeHighlightOverlay


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = []
	for i in 5:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(100.0 * i, 50.0)
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	await get_tree().process_frame
	_ctl = autofree(HighlightController.new())
	_overlay = NodeHighlightOverlay.new()
	_overlay.highlight_controller = _ctl
	_overlay.graph = _graph
	_graph.add_child(_overlay)


func _indicators() -> Array[Node]:
	# Script-chain lookup, not `is Indicator`: the class must not be named
	# before it exists, or this file is a parse error GUT silently skips.
	var out: Array[Node] = []
	for c in _overlay.get_children():
		var s := c.get_script() as Script
		while s != null:
			if s.get_global_name() == &"Indicator":
				out.append(c)
				break
			s = s.get_base_script()
	return out


func _hostile_on(sn: SkillNode) -> RoleMapProvider:
	var p := RoleMapProvider.new()
	p.roles[sn] = HighlightProvider.HighlightRole.HOSTILE_TARGET
	return p


func test_one_hostile_target_gives_one_indicator_at_the_node() -> void:
	var sn := _nodes[2]
	_ctl.provider = _hostile_on(sn)
	var found := _indicators()
	assert_eq(found.size(), 1)
	if found.size() != 1:
		return
	var ind := found[0] as Node2D
	assert_eq(ind.position, _overlay.to_local(sn.global_position))
	assert_eq(float(ind.get("radius")), sn.radius)


func test_retarget_moves_the_one_indicator() -> void:
	var p := _hostile_on(_nodes[1])
	_ctl.provider = p
	p.roles.clear()
	p.roles[_nodes[3]] = HighlightProvider.HighlightRole.HOSTILE_TARGET
	p.state_changed.emit()
	var found := _indicators()
	assert_eq(found.size(), 1)
	if found.size() == 1:
		assert_eq((found[0] as Node2D).position, _overlay.to_local(_nodes[3].global_position))


func test_same_target_repaint_keeps_the_instance() -> void:
	var p := _hostile_on(_nodes[1])
	_ctl.provider = p
	var first := _indicators()
	p.state_changed.emit()
	var second := _indicators()
	assert_eq(second.size(), 1)
	if first.size() == 1 and second.size() == 1:
		assert_same(second[0], first[0], "a repaint with no role change must not re-instance")


func test_clearing_provider_gives_zero() -> void:
	_ctl.provider = _hostile_on(_nodes[0])
	_ctl.provider = null
	assert_eq(_indicators().size(), 0)


func test_mass_deallocate_forfeit_gives_zero() -> void:
	var req := MassActionRequest.new(null, MassActionRequest.Verb.DEALLOCATE, _nodes)
	var p := MassActionHighlightProvider.new()
	p.configure(req, _graph)
	_ctl.provider = p
	assert_eq(p.get_node_role(_nodes[0]), HighlightProvider.HighlightRole.FORFEIT)
	assert_eq(_indicators().size(), 0)


func test_empty_theme_gives_zero() -> void:
	var theme_script := load(_THEME_SCRIPT_PATH) as Script
	assert_not_null(theme_script, "indicator_theme.gd must exist")
	if theme_script == null:
		return
	_overlay.set("default_theme", theme_script.new())
	_ctl.provider = _hostile_on(_nodes[2])
	assert_eq(_indicators().size(), 0)
	# Control: the shipped theme mounts one, so zero above is the map's doing.
	_overlay.set("default_theme", load("res://ui/indicator/themes/default.tres"))
	_ctl.provider = _hostile_on(_nodes[4])
	assert_eq(_indicators().size(), 1)

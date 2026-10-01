extends GutTest

## NodeHighlightOverlay mounts one Indicator scene per node whose role has a
## scene in its IndicatorTheme, diffing on every repaint signal; every other
## role keeps the plain ring.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _THEME_SCRIPT_PATH := "res://ui/indicator/indicator_theme.gd"
const _THEMES_DIR := "res://ui/indicator/themes/"
const _PLAIN_RING_PATH := "res://ui/indicator/plain_ring.tscn"
const _DASHED_RING_PATH := "res://ui/indicator/dashed_ring.tscn"


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


func test_mass_deallocate_forfeit_mounts_dashed_rings_not_reticles() -> void:
	var req := MassActionRequest.new(null, MassActionRequest.Verb.DEALLOCATE, _nodes)
	var p := MassActionHighlightProvider.new()
	p.configure(req, _graph)
	_ctl.provider = p
	assert_eq(p.get_node_role(_nodes[0]), HighlightProvider.HighlightRole.FORFEIT)
	var found := _indicators()
	assert_eq(found.size(), _nodes.size())
	for ind in found:
		assert_eq(ind.scene_file_path, _DASHED_RING_PATH)


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


# --- per-mode themes (#1297) --------------------------------------------------
# Dynamic get/set/call throughout: the theme key, facing/order/charge and the
# `themes` export are the seams under test, named before they exist.

const _SCENE_A := preload("res://ui/indicator/target_reticle.tscn")
const _SCENE_B := preload("res://ui/indicator/indicator_base.tscn")


class KeyedProvider extends HighlightProvider:
	var key: StringName = &"default"
	var roles: Dictionary = {}
	var facings: Dictionary = {}
	var orders: Dictionary = {}
	var fills: Dictionary = {}

	func get_theme_key() -> StringName:
		return key

	func get_node_role(node: SkillNode) -> HighlightRole:
		return roles.get(node, HighlightRole.NONE)

	func get_node_facing(node: SkillNode) -> Vector2:
		return facings.get(node, Vector2.ZERO)

	func get_node_order(node: SkillNode) -> int:
		return orders.get(node, -1)

	func get_node_range_fill(node: SkillNode) -> float:
		return fills.get(node, 1.0)


func _theme(role: HighlightProvider.HighlightRole, scene: PackedScene) -> IndicatorTheme:
	var t := IndicatorTheme.new()
	if scene != null:
		t.scenes[role] = scene
	return t


func _origin_on(sn: SkillNode, key: StringName) -> KeyedProvider:
	var p := KeyedProvider.new()
	p.key = key
	p.roles[sn] = HighlightProvider.HighlightRole.ORIGIN
	return p


func test_theme_key_picks_the_keyed_theme_scene() -> void:
	var themes: Dictionary[StringName, IndicatorTheme] = {
		&"ranged": _theme(HighlightProvider.HighlightRole.ORIGIN, _SCENE_A),
	}
	_overlay.set("themes", themes)
	_overlay.default_theme = _theme(HighlightProvider.HighlightRole.ORIGIN, _SCENE_B)
	_ctl.provider = _origin_on(_nodes[1], &"ranged")
	var found := _indicators()
	assert_eq(found.size(), 1)
	if found.size() == 1:
		assert_eq(found[0].scene_file_path, _SCENE_A.resource_path)


func test_unmapped_key_falls_back_to_default_then_ring() -> void:
	var themes: Dictionary[StringName, IndicatorTheme] = {
		&"ranged": _theme(HighlightProvider.HighlightRole.ORIGIN, _SCENE_A),
	}
	_overlay.set("themes", themes)
	_overlay.default_theme = _theme(HighlightProvider.HighlightRole.ORIGIN, _SCENE_B)
	_ctl.provider = _origin_on(_nodes[1], &"melee")
	var found := _indicators()
	assert_eq(found.size(), 1)
	if found.size() == 1:
		assert_eq(found[0].scene_file_path, _SCENE_B.resource_path)
	_overlay.default_theme = _theme(HighlightProvider.HighlightRole.ORIGIN, null)
	_ctl.provider = _origin_on(_nodes[2], &"melee")
	assert_eq(_indicators().size(), 0, "no keyed and no default entry keeps the plain ring")


func test_theme_change_on_a_live_node_swaps_the_instance() -> void:
	var themes: Dictionary[StringName, IndicatorTheme] = {
		&"ranged": _theme(HighlightProvider.HighlightRole.ORIGIN, _SCENE_A),
	}
	_overlay.set("themes", themes)
	_overlay.default_theme = _theme(HighlightProvider.HighlightRole.ORIGIN, _SCENE_B)
	var p := _origin_on(_nodes[1], &"melee")
	_ctl.provider = p
	p.key = &"ranged"
	p.state_changed.emit()
	var found := _indicators()
	assert_eq(found.size(), 1)
	if found.size() == 1:
		assert_eq(found[0].scene_file_path, _SCENE_A.resource_path)


func test_overlay_pushes_facing_order_and_charge() -> void:
	_overlay.default_theme = _theme(HighlightProvider.HighlightRole.ORIGIN, _SCENE_A)
	var p := KeyedProvider.new()
	var want := {
		_nodes[0]: [Vector2(1, 0), 0, 0.25],
		_nodes[3]: [Vector2(0, -1), 2, 0.75],
	}
	for sn in want:
		p.roles[sn] = HighlightProvider.HighlightRole.ORIGIN
		p.facings[sn] = want[sn][0]
		p.orders[sn] = want[sn][1]
		p.fills[sn] = want[sn][2]
	_ctl.provider = p
	var found := _indicators()
	assert_eq(found.size(), 2)
	for ind in found:
		var sn: SkillNode = null
		for n in want:
			if (ind as Node2D).position == _overlay.to_local(n.global_position):
				sn = n
		assert_not_null(sn)
		if sn == null:
			continue
		assert_eq(ind.get("facing"), want[sn][0])
		assert_eq(ind.get("order"), want[sn][1])
		assert_almost_eq(float(ind.get("charge")), want[sn][2], 0.0001)


func test_gate_cut_reports_its_base_theme_key_facing_and_order() -> void:
	var gate := GateCutHighlightProvider.new()
	var melee := MeleeAttackPlan.new()
	melee.mode = BattleSystem.AttackMode.MELEE
	gate.base = melee
	assert_eq(gate.call("get_theme_key"), &"melee")
	var stub := KeyedProvider.new()
	stub.key = &"ranged"
	stub.facings[_nodes[1]] = Vector2(0.6, 0.8)
	stub.orders[_nodes[1]] = 3
	gate.base = stub
	assert_eq(gate.call("get_theme_key"), &"ranged")
	assert_eq(gate.call("get_node_facing", _nodes[1]), Vector2(0.6, 0.8))
	assert_eq(gate.call("get_node_order", _nodes[1]), 3)
	gate.base = null
	assert_eq(gate.call("get_theme_key"), &"default")


# --- every role mounts a scene (#1301) ----------------------------------------

# Roles that never mount a node indicator: NONE is "no highlight", PATH is an
# edge role.
const _SCENELESS_ROLES: Array[HighlightProvider.HighlightRole] = [
	HighlightProvider.HighlightRole.NONE,
	HighlightProvider.HighlightRole.PATH,
]


func test_every_node_role_resolves_to_a_scene_through_the_shipped_themes() -> void:
	var themes: Array[IndicatorTheme] = []
	for f in DirAccess.get_files_at(_THEMES_DIR):
		if f.ends_with(".tres"):
			var t := load(_THEMES_DIR + f) as IndicatorTheme
			if t != null:
				themes.append(t)
	assert_gt(themes.size(), 0)
	for role in HighlightProvider.HighlightRole.values():
		if role in _SCENELESS_ROLES:
			continue
		var found := false
		for t in themes:
			if t.scene_for(role) != null:
				found = true
				break
		assert_true(found, "role %s has no indicator scene in any theme"
				% HighlightProvider.HighlightRole.find_key(role))


func test_allocatable_alone_mounts_one_plain_ring_and_no_inline_ring() -> void:
	var p := RoleMapProvider.new()
	p.roles[_nodes[3]] = HighlightProvider.HighlightRole.ALLOCATABLE
	_ctl.provider = p
	var found := _indicators()
	assert_eq(found.size(), 1)
	if found.size() == 1:
		assert_eq(found[0].scene_file_path, _PLAIN_RING_PATH)
		assert_eq(found[0].position, _overlay.to_local(_nodes[3].global_position))
	# The inline role ring's knobs are gone with its draw_arc: the overlay draws
	# range rings only, and no ring-band export is left to tune.
	for prop in ["ring_inner_offset", "ring_width", "ring_segments"]:
		assert_false(prop in _overlay, "overlay still carries %s" % prop)


func test_core_move_theme_marks_origin_and_reachable() -> void:
	var t := load(_THEMES_DIR + "core_move.tres") as IndicatorTheme
	assert_not_null(t)
	if t == null:
		return
	assert_eq(t.scene_for(HighlightProvider.HighlightRole.ORIGIN).resource_path,
			"res://ui/indicator/core_move_origin.tscn")
	assert_eq(t.scene_for(HighlightProvider.HighlightRole.REACHABLE).resource_path,
			"res://ui/indicator/tick_ring.tscn")

extends GutTest

## Status rows keyed by `(def.id, key)` (#1343): [member StatusDef.group_by]
## computes the key from the applier, [member StatusDef.visible_if] gates who
## reads a row's count, spread/spill move stacks row-to-row under the same
## key, and a save round-trips the rows with their key and applier.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _CAMP_STATUS := preload("res://test/fixtures/status/test_camp_status.tres")

var _owner: Entity


func before_each() -> void:
	_owner = autofree(Entity.new())


func _node() -> NodeCombat:
	var sn: SkillNode = autofree(SkillNode.new())
	sn.owned_by = _owner
	return sn.get_combat()


func _def(group_by: String = "", visible_if: String = "") -> StatusDef:
	var d := StatusDef.new()
	d.id = &"grouped"
	d.power_max = 0.0
	d.decay = null
	d.reapply = StatusDef.Reapply.ACCUMULATE
	d.group_by = group_by
	d.visible_if = visible_if
	return d


func _row(n: NodeCombat, id: StringName, key: Variant) -> NodeStatus:
	for r in n.get_statuses():
		if r.def.id == id and typeof(r.key) == typeof(key) and r.key == key:
			return r
	return null


# ── (a) group_by keys the row ───────────────────────────────────────────────

func test_camp_keyed_def_files_one_row_per_camp() -> void:
	var d := _def("camp_id")
	var n := _node()
	n.apply_status(d, 1.0, &"A", 1)
	n.apply_status(d, 1.0, &"A", 2)
	n.apply_status(d, 1.0, &"B", 3)
	assert_eq(n.get_statuses().size(), 2, "one row per camp")
	assert_eq(n.get_status_power(d.id, &"A"), 2.0, "camp A accumulated")
	assert_eq(n.get_status_power(d.id, &"B"), 1.0, "camp B its own row")
	var a := _row(n, d.id, &"A")
	assert_not_null(a, "row A carries its key")
	if a != null:
		assert_eq([a.camp_id, a.applier_id], [&"A", 2], "the latest applier's fields")


func test_empty_group_by_is_one_shared_row() -> void:
	var d := _def()
	var n := _node()
	n.apply_status(d, 1.0, &"A", 1)
	n.apply_status(d, 1.0, &"A", 2)
	n.apply_status(d, 1.0, &"B", 3)
	assert_eq(n.get_statuses().size(), 1, "one shared row")
	assert_eq(n.get_status_power(d.id), 3.0, "all three accumulate")
	assert_eq(n.get_statuses()[0].key, true, "the shared key is true")


func test_false_group_by_is_refused_and_lands_nothing() -> void:
	var d := _def("false")
	var n := _node()
	n.apply_status(d, 1.0, &"A", 1)
	assert_push_error("independent rows are not built")
	assert_eq(n.get_statuses().size(), 0, "a refused key is a no-op apply")


func test_remove_status_drops_every_row_and_remove_row_one() -> void:
	var d := _def("camp_id")
	var n := _node()
	n.apply_status(d, 1.0, &"A", 1)
	n.apply_status(d, 1.0, &"B", 2)
	n.remove_row(d.id, &"A")
	assert_eq(n.get_status_power(d.id, &"A"), 0.0, "row A removed")
	assert_eq(n.get_status_power(d.id, &"B"), 1.0, "row B untouched")
	n.apply_status(d, 1.0, &"A", 1)
	n.remove_status(d.id)
	assert_eq(n.get_statuses().size(), 0, "remove_status drops every row of the def")


func test_status_instance_lands_under_the_attackers_camp() -> void:
	var d := _def("camp_id")
	var n := _node()
	var attacker: Entity = autofree(Entity.new())
	var camp := Faction.new()
	camp.id = &"raiders"
	attacker.faction = camp
	attacker.entity_id = 7
	var si := StatusInstance.new()
	si.def = d
	si.power = 2.0
	si.attacker = attacker
	si.land_on(n, null)
	var row := _row(n, d.id, &"raiders")
	assert_not_null(row, "the landing filed under the attacker's camp")
	if row != null:
		assert_eq([row.power, row.applier_id], [2, 7], "power and applier id")


# ── (b) visible_if gates the count ──────────────────────────────────────────

func test_visible_if_shows_own_camp_rows_only() -> void:
	var d := _def("camp_id", "camp_id == viewer_camp_id")
	var n := _node()
	n.apply_status(d, 1.0, &"A", 1)
	n.apply_status(d, 1.0, &"B", 2)
	var a := _row(n, d.id, &"A")
	var b := _row(n, d.id, &"B")
	assert_not_null(a, "row A")
	assert_not_null(b, "row B")
	if a == null or b == null:
		return
	assert_true(d.count_visible(a, &"A", 1), "viewer A reads row A")
	assert_false(d.count_visible(b, &"A", 1), "viewer A does not read row B")
	assert_true(_def("camp_id").count_visible(b, &"A", 1), "empty visible_if: every viewer reads")


# ── (c) spread / spill move stacks under the same key ───────────────────────

func test_spill_rule_moves_a_camp_row_under_its_key() -> void:
	var d := _def("camp_id")
	var r := _node()
	var s := _node()
	r.apply_status(d, 4.0, &"A", 1)
	r.apply_status(d, 2.0, &"B", 2)
	for camp: StringName in [&"A", &"B"]:
		var field := StackField.new(d, SkillNode.Ownership.MINE, {r: [s], s: [r]}, camp)
		var transfers := SpillSpread.new().on_removed(field, [r] as Array[NodeCombat], StatusSpread.CAUSE_DEATH)
		SpreadApplier.apply(d, transfers)
	assert_eq(s.get_status_power(d.id, &"A"), 4.0, "A's stacks land under A")
	assert_eq(s.get_status_power(d.id, &"B"), 2.0, "B's stacks land under B")
	assert_eq(s.get_status_power(d.id), 0.0, "nothing lands on the shared row")


func test_diffusion_rule_moves_a_camp_row_under_its_key() -> void:
	var d := _def("camp_id")
	var u := _node()
	var v := _node()
	u.apply_status(d, 6.0, &"A", 1)
	var field := StackField.new(d, SkillNode.Ownership.MINE, {u: [v], v: [u]}, &"A")
	var rule := FractionDiffusion.new()
	rule.fraction = 1.0
	var transfers := rule.on_tick(field)
	assert_gt(transfers.size(), 0, "precondition: the gap moves stacks")
	SpreadApplier.apply(d, transfers)
	assert_gt(v.get_status_power(d.id, &"A"), 0.0, "diffused stacks land under A")
	assert_eq(v.get_status_power(d.id), 0.0, "nothing lands on the shared row")


func test_dealloc_spill_driver_keeps_each_camps_row() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	var a := Entity.new()
	a.name = "A"
	a.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(a)
	await get_tree().process_frame
	var n: Array[SkillNode] = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.position = Vector2(i * 100, 0)
		graph.add_skill_node(sn)
		n.append(sn)
	graph.add_edge(n[0], n[1])
	graph.add_edge(n[0], n[2])
	graph.add_edge(n[1], n[2])
	await get_tree().process_frame
	alloc.force_allocate(a, n[0])
	a.core_location = n[0]
	alloc.force_allocate(a, n[1])
	alloc.force_allocate(a, n[2])
	n[1].get_combat().apply_status(_CAMP_STATUS, 4.0, &"A", 1)
	n[1].get_combat().apply_status(_CAMP_STATUS, 2.0, &"B", 2)
	assert_true(alloc.deallocate(n[1], a), "precondition: the dealloc is legal")
	var id := _CAMP_STATUS.id
	assert_eq([n[0].get_combat().get_status_power(id, &"A"), n[2].get_combat().get_status_power(id, &"A")],
			[2.0, 2.0], "camp A's row spills under A")
	assert_eq([n[0].get_combat().get_status_power(id, &"B"), n[2].get_combat().get_status_power(id, &"B")],
			[1.0, 1.0], "camp B's row spills under B")


# ── (d) the disk sweep: every authored expression parses ────────────────────

func test_every_authored_group_by_and_visible_if_parses() -> void:
	var violations: Array[String] = []
	for dir in ["res://effects/status", "res://test/fixtures/status"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".tres"):
				continue
			var sd := load(dir.path_join(f)) as StatusDef
			if sd == null:
				continue
			var e1 := StatusDef.parse_error(sd.group_by, StatusDef.GROUP_BY_INPUTS)
			if not e1.is_empty():
				violations.append("%s: group_by '%s': %s" % [f, sd.group_by, e1])
			var e2 := StatusDef.parse_error(sd.visible_if, StatusDef.VISIBLE_IF_INPUTS)
			if not e2.is_empty():
				violations.append("%s: visible_if '%s': %s" % [f, sd.visible_if, e2])
	assert_eq(violations, [] as Array[String], "every authored expression parses")
	assert_ne(StatusDef.parse_error("camp_idd", StatusDef.GROUP_BY_INPUTS), "",
			"a typo'd input is caught")
	assert_ne(StatusDef.parse_error("viewer_id", StatusDef.GROUP_BY_INPUTS), "",
			"a viewer input is not a group_by input")


# ── (e) save → load round-trips the rows ────────────────────────────────────

func _graph() -> Graph:
	var graph: Graph = autofree(_GRAPH_SCENE.instantiate())
	add_child(graph)
	await get_tree().process_frame
	var cfg := GraphProcgenConfig.new()
	cfg.topology = GraphProcgenTopology.new()
	cfg.topology.node_count = 12
	cfg.seed = 20261003
	cfg.shape = GraphProcgenShape.new()
	cfg.shape.shape_mask = CircularShapeMask.new()
	await GraphProcgen.generate(cfg, graph)
	return graph


func _owner_on(graph: Graph) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(e)
	return e


func test_snapshot_round_trips_a_two_camp_node() -> void:
	var source := await _graph()
	var target := await _graph()
	var src_owner := _owner_on(source)
	_owner_on(target)
	var node: SkillNode = source.get_skill_nodes()[0]
	node.owned_by = src_owner
	node.get_combat().apply_status(_CAMP_STATUS, 3.0, &"A", 4)
	node.get_combat().apply_status(_CAMP_STATUS, 1.0, &"B", 5)
	GraphSnapshot.decode(GraphSnapshot.encode(source), target)
	var decoded := target.get_by_stable_id(source.get_stable_id(node))
	var got := []
	for r in decoded.get_combat().get_statuses():
		got.append([r.def.id, r.power, r.key, r.camp_id, r.applier_id])
	got.sort_custom(func(x, y): return String(x[2]) < String(y[2]))
	assert_eq(got, [[&"test_camp_status", 3, &"A", &"A", 4], [&"test_camp_status", 1, &"B", &"B", 5]],
			"both rows survive with key and applier")

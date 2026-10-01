extends GutTest

## The two routes a SkillNode grants a stat through, gated by data on the
## StatDef: `local_grantable` (the node's own board — addon `local_modifiers`,
## effect node grants) and `entity_grantable` (the owner's board — a node's
## `modifiers`, addon `entity_modifiers`). Both doors push_error and reject the
## whole modifier. Fixtures use throwaway defs, never the shipped table, except
## where the shipped content is the subject (registry check, content lint).

const _BOARD := preload("res://entity/default_entity_board.tres")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")

const LOCAL_OK := &"t_grant_local_ok"
const LOCAL_NO := &"t_grant_local_no"
const ENT_NO := &"t_grant_entity_no"
const PARENT := &"t_grant_parent"

var _registered: Array[StringName] = []


func after_each() -> void:
	for id in _registered:
		StatRegistry.unregister_def(id)
	_registered.clear()


func _def(id: StringName, local: bool, entity: bool, parents: Array[StringName] = []) -> StatDef:
	var d := StatDef.new()
	d.id = id
	d.value_type = StatDef.ValueType.FLOAT
	d.local_grantable = local
	d.entity_grantable = entity
	d.parent_ids = parents
	StatRegistry.register_def(d)
	_registered.append(id)
	return d


func _mod(stat_id: StringName, value: float = 1.0) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value
	return m


func _bundle(children: Array[StatModifier]) -> CompositeStatModifier:
	var c := CompositeStatModifier.new()
	c.children = children
	return c


func _make_node() -> SkillNode:
	var n: SkillNode = _NODE_SCENE.instantiate()
	autofree(n)
	return n


func _make_entity() -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "T"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	return ent


# ── 1. The local door ────────────────────────────────────────────────────────

func test_local_modifier_on_non_local_stat_is_rejected() -> void:
	_def(LOCAL_NO, false, true)
	var n := _make_node()
	n.add_local_modifier(_mod(LOCAL_NO, 5.0))
	assert_push_error(String(LOCAL_NO))
	assert_null(n.node_board.get_stat(LOCAL_NO) if n.node_board != null else null,
		"nothing was minted for a rejected local grant")


func test_local_modifier_on_local_stat_reads_back() -> void:
	_def(LOCAL_OK, true, true)
	var n := _make_node()
	n.add_local_modifier(_mod(LOCAL_OK, 5.0))
	assert_push_error_count(0)
	assert_eq(float(n.get_local_value(LOCAL_OK)), 5.0)


# ── 2. The entity door, both bodies ──────────────────────────────────────────

func test_add_entity_modifier_rejects_non_entity_grantable() -> void:
	var ent := _make_entity()
	var n := _make_node()
	n.owned_by = ent
	var before: float = ent.stat_board.skill_points.value
	n.add_entity_modifier(_mod(&"skill_points"))
	assert_push_error("skill_points")
	assert_eq(ent.stat_board.skill_points.value, before)
	assert_eq(n.modifiers.size(), 0, "the rejected modifier is not carried either")


func test_apply_entity_modifiers_to_rejects_non_entity_grantable() -> void:
	_def(ENT_NO, false, false)
	var n := _make_node()
	var m := _mod(ENT_NO)
	n.modifiers = [m]
	var b := StatBoard.new()
	b._ensure_stat(ENT_NO)
	n.apply_entity_modifiers_to(b)
	assert_push_error(String(ENT_NO))
	assert_eq(float(b.get_stat(ENT_NO).get_value()), 0.0)


# ── 3. A parent inherits its descendants' veto ───────────────────────────────

func test_parent_with_non_grantable_descendant_is_rejected() -> void:
	_def(PARENT, false, true)
	_def(ENT_NO, false, false, [PARENT])
	assert_false(StatRegistry.is_entity_grantable(PARENT), "the veto climbs to the parent")
	var n := _make_node()
	n.modifiers = [_mod(PARENT)]
	var b := StatBoard.new()
	b._ensure_stat(PARENT)
	b._ensure_stat(ENT_NO)
	n.apply_entity_modifiers_to(b)
	assert_push_error(String(PARENT))
	assert_eq(float(b.get_stat(ENT_NO).get_value()), 0.0, "nothing folded into the child")


# ── 4. A bundle is all-or-nothing ────────────────────────────────────────────

func test_composite_with_one_illegal_leaf_is_rejected_whole_locally() -> void:
	_def(LOCAL_OK, true, true)
	_def(LOCAL_NO, false, true)
	var n := _make_node()
	n.add_local_modifier(_bundle([_mod(LOCAL_OK, 3.0), _mod(LOCAL_NO, 3.0)]))
	assert_push_error(String(LOCAL_NO))
	assert_eq(float(n.get_local_value(LOCAL_OK)), 0.0, "the legal leaf did not land either")


func test_composite_with_one_illegal_leaf_is_rejected_whole_on_entity() -> void:
	_def(LOCAL_OK, true, true)
	_def(ENT_NO, false, false)
	var n := _make_node()
	n.modifiers = [_bundle([_mod(LOCAL_OK, 3.0), _mod(ENT_NO, 3.0)])]
	var b := StatBoard.new()
	b._ensure_stat(LOCAL_OK)
	b._ensure_stat(ENT_NO)
	n.apply_entity_modifiers_to(b)
	assert_push_error(String(ENT_NO))
	assert_eq(float(b.get_stat(LOCAL_OK).get_value()), 0.0, "the legal leaf did not land either")


# ── 5. Registry load check ───────────────────────────────────────────────────

func test_def_living_nowhere_is_reported() -> void:
	_def(LOCAL_NO, false, true)
	var homeless := StatRegistry.check_residency()
	assert_push_error(String(LOCAL_NO))
	assert_has(homeless, LOCAL_NO)


func test_every_shipped_def_has_a_home() -> void:
	assert_eq(StatRegistry.check_residency(), [] as Array[StringName])


# ── 6. Content lint ──────────────────────────────────────────────────────────

var _violations: PackedStringArray = []


func _check(m: StatModifier, local: bool, where: String) -> void:
	if m == null:
		return
	for leaf in m.flatten():
		var ok := StatRegistry.is_local_grantable(leaf.stat_id) if local \
			else StatRegistry.is_entity_grantable(leaf.stat_id)
		if not ok:
			_violations.append("%s: %s grant of '%s'" % [where, "local" if local else "entity", leaf.stat_id])


func _scenes_in(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	return out


func _check_effects(effects: Array, where: String) -> void:
	for e in effects:
		if e == null:
			continue
		# An aura grants onto node boards; a plain effect onto the entity's.
		for m in e.modifiers:
			_check(m, e is AuraEffect, where)


func test_shipped_content_passes_both_predicates() -> void:
	_violations = []
	var addon_paths := _scenes_in("res://skill_node/addons/defs")
	assert_gt(addon_paths.size(), 0, "found no addon scenes")
	for p in addon_paths:
		var a := (load(p) as PackedScene).instantiate()
		autofree(a)
		if a is SkillNodeAddon:
			for m in a.get_local_modifiers():
				_check(m, true, p)
			for m in a.get_entity_modifiers():
				_check(m, false, p)
			_check_effects(a.effects, p)
	var node_paths := PackedStringArray()
	for dir in ["res://skill_node", "res://entity/keystone/instances", "res://entity/keystone",
			"res://skill_node/keystone/instances", "res://skill_node/keystone"]:
		node_paths.append_array(_scenes_in(dir))
	var seen_nodes := 0
	for p in node_paths:
		var n := (load(p) as PackedScene).instantiate()
		autofree(n)
		if not (n is SkillNode):
			continue
		seen_nodes += 1
		for m in n.modifiers:
			_check(m, false, p)
		_check_effects(n.effects, p)
	assert_gt(seen_nodes, 1, "found the base node and the keystones")
	for f in DirAccess.get_files_at("res://effects/status"):
		if not f.ends_with(".tres"):
			continue
		var sd := load("res://effects/status".path_join(f)) as StatusDef
		if sd != null and sd.resistance_stat_id != &"" \
				and not StatRegistry.is_local_grantable(sd.resistance_stat_id):
			_violations.append("%s: resistance '%s' is read per node" % [f, sd.resistance_stat_id])
	var pools := 0
	for f in DirAccess.get_files_at("res://procgen/pools"):
		if not f.ends_with(".tres"):
			continue
		var pack := load("res://procgen/pools".path_join(f)) as StatPack
		if pack == null:
			continue
		for pool in pack.pools:
			pools += 1
			if pool != null and not StatRegistry.is_entity_grantable(pool.stat_id):
				_violations.append("%s: rolls entity grant of '%s'" % [f, pool.stat_id])
	assert_gt(pools, 0, "found the procgen roll pools")
	assert_eq(_violations, PackedStringArray(), "\n".join(_violations))


# ── 7. dealloc_damage is read per node ───────────────────────────────────────

func test_local_dealloc_damage_changes_only_that_nodes_chip() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var nodes: Array[SkillNode] = []
	for i in 3:
		var sn := _NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		graph.skill_nodes_container.add_child(sn)
		nodes.append(sn)
	for pair in [[0, 1], [1, 2]]:
		var e := _EDGE_SCENE.instantiate() as Edge
		e.from = nodes[pair[0]]
		e.to = nodes[pair[1]]
		graph.edges_container.add_child(e)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	var ent := _make_entity()
	graph.add_child(ent)
	await get_tree().process_frame
	for n in nodes:
		alloc.force_allocate(ent, n)
	ent.core_location = nodes[0]
	ent.stat_board.health.base_value = 100.0
	ent.stat_board.health.set_current(100.0)
	ent.stat_board.dealloc_damage.base_value = 1.0
	nodes[2].add_local_modifier(_mod(&"dealloc_damage", 3.0))
	var cascade: Array[NodeCombat] = [nodes[1].get_combat(), nodes[2].get_combat()]
	var entries := ent.get_combat().apply_cascade(cascade, alloc)
	assert_eq(entries.size(), 2)
	var chips := {}
	for entry in entries:
		chips[entry.node] = entry.chip / float(entry.allocation_level)
	assert_eq(chips.get(nodes[1]), 1.0, "an ungranted node chips the entity baseline")
	assert_eq(chips.get(nodes[2]), 4.0, "the granting node chips baseline + its local grant")

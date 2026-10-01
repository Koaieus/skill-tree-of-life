extends GutTest

## A temp upgrade is the addon itself with a shorter lifecycle: it stays a
## real child of its carrier, but its modifiers never reach a board. The
## swing folds them as overlays through [BladeVertexFill] instead, scaled to
## the carrier's stake like a permanent addon's.

## A `var`, not a `const`: the parser constant-folds `CONST.kinds[i]`.
var _catalog: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _CLAMP_SCENE := preload("res://skill_node/addons/defs/clamp_addon.tscn")
const _SPIKE_SCENE := preload("res://skill_node/addons/defs/spike_ring_addon.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity


func _spawn(nm: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	return sn


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_entity = Entity.new()
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)


## Source - joint - tip - outside, all allocated; source pivots, joint and tip
## are members (particles 0, 1, 2), outside stays off the blade.
func _setup(budget: float = 8.0) -> Dictionary:
	_entity.stat_board.blade_size.base_value = budget
	var source := _spawn("Source")
	var joint := _spawn("Joint")
	var tip := _spawn("Tip")
	var outside := _spawn("Outside")
	_graph.add_edge(source, joint)
	_graph.add_edge(joint, tip)
	_graph.add_edge(tip, outside)
	await get_tree().process_frame
	for sn in [source, joint, tip, outside]:
		_alloc.force_allocate(_entity, sn)
	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = _entity
	plan.set_pivot(source)
	plan.toggle_member(joint)
	plan.toggle_member(tip)
	return {"plan": plan, "source": source, "joint": joint, "tip": tip, "outside": outside}


func _modifier(stat_id: StringName, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.value = value
	return m


## A test-only temp: the clamp's def and scene, authored with extra modifiers.
func _temp_addon(entity_mods: Array[StatModifier], local_mods: Array[StatModifier] = []) -> SkillNodeAddon:
	var addon := _CLAMP_SCENE.instantiate() as SkillNodeAddon
	addon.entity_modifiers = entity_mods
	addon.local_modifiers = local_mods
	addon.is_temporary = true
	return addon


## Every stat on [param board]: its value and its wire form (base + modifiers).
func _board_print(board: StatBoard) -> Dictionary:
	var out := {}
	if board == null:
		return out
	for id in board.get_stat_ids():
		out[id] = [board.get_value(id), var_to_str(board.get_stat(id).to_dict())]
	return out


func _world_print(ctx: Dictionary) -> Array:
	var out: Array = [_board_print(_entity.stat_board)]
	for key in ["source", "joint", "tip", "outside"]:
		out.append(_board_print((ctx[key] as SkillNode).node_board))
	return out


func _column(state: BladeState, arr: StringName) -> Array:
	return Array(state.get(arr))


# 1 ────────────────────────────────────────────────────────────────────────

func test_a_temp_upgrade_leaves_every_board_unchanged() -> void:
	var ctx: Dictionary = await _setup()
	var plan: MeleeAttackPlan = ctx.plan
	_entity.stat_board.poison_aspect.base_value = 2.0
	var before := _world_print(ctx)
	assert_true(plan.apply_temp_upgrade(ctx.joint, preload("res://skill_node/addons/defs/toxin_addon.tscn")))
	assert_true(plan.apply_temp_upgrade(ctx.tip, preload("res://skill_node/addons/defs/spike_ring_addon.tscn")))
	assert_eq(_world_print(ctx), before,
			"a temp's modifiers never reach the entity board or any node board")


# 2 ────────────────────────────────────────────────────────────────────────

func test_temp_spike_ring_raises_the_vertex_like_a_permanent_twin() -> void:
	var ctx: Dictionary = await _setup()
	var plan: MeleeAttackPlan = ctx.plan
	var outside: SkillNode = ctx.outside
	outside.add_child(_SPIKE_SCENE.instantiate())
	var permanent_dmg := float(outside.get_local_value(&"blade_damage"))
	var permanent_blunt := float(outside.get_local_value(&"blunting"))
	var bare := plan.build_blade_state()
	assert_true(plan.apply_temp_upgrade(ctx.joint, preload("res://skill_node/addons/defs/spike_ring_addon.tscn")))
	var state := plan.build_blade_state()
	assert_ne(state.vertex_damage[1], bare.vertex_damage[1], "the temp moves its vertex")
	assert_almost_eq(state.vertex_damage[1], permanent_dmg, 0.001,
			"a temp spike ring reads exactly as a permanent one on the same node")
	assert_almost_eq(state.vertex_blunting[1], permanent_blunt, 0.001,
			"its synthesized blunting reaches the swing too")
	assert_eq(state.vertex_damage[2], bare.vertex_damage[2], "a local temp stays on its vertex")


# 3 ────────────────────────────────────────────────────────────────────────

func test_temp_scales_with_its_carriers_stake() -> void:
	var ctx: Dictionary = await _setup()
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	var outside: SkillNode = ctx.outside
	outside.add_child(_SPIKE_SCENE.instantiate())
	var authored_dmg := float(outside.get_local_value(&"blade_damage"))
	for sn: SkillNode in [joint, outside]:
		sn.stake_level = 3
		sn.allocation_level = 3
	await get_tree().process_frame
	var permanent_dmg := float(outside.get_local_value(&"blade_damage"))
	assert_ne(permanent_dmg, authored_dmg, "the stake-3 law is not the identity here")
	assert_true(plan.apply_temp_upgrade(joint, preload("res://skill_node/addons/defs/spike_ring_addon.tscn")))
	var state := plan.build_blade_state()
	assert_almost_eq(state.vertex_damage[1], permanent_dmg, 0.001,
			"a temp on a stake-3 carrier contributes the permanent addon's stake-3 value")


# 4 ────────────────────────────────────────────────────────────────────────

func test_entity_wide_temp_raises_every_vertex_and_nothing_outside() -> void:
	var ctx: Dictionary = await _setup()
	var plan: MeleeAttackPlan = ctx.plan
	var outside: SkillNode = ctx.outside
	var outside_before := float(outside.get_local_value(&"blade_damage"))
	var board_before: float = _entity.stat_board.get_value(&"blade_damage")
	var bare := plan.build_blade_state()
	var mods: Array[StatModifier] = [_modifier(&"blade_damage", 1.0)]
	(ctx.joint as SkillNode).add_child(_temp_addon(mods))
	var state := plan.build_blade_state()
	for i in 3:
		assert_gt(state.vertex_damage[i], bare.vertex_damage[i],
				"vertex %d (temp-less included) gets the entity-wide temp" % i)
	assert_eq(float(outside.get_local_value(&"blade_damage")), outside_before,
			"a node off the blade is untouched")
	assert_eq(_entity.stat_board.get_value(&"blade_damage"), board_before,
			"and so is the entity board")


# 5 ────────────────────────────────────────────────────────────────────────

func test_entity_wide_strength_temp_is_inert() -> void:
	var ctx: Dictionary = await _setup()
	var plan: MeleeAttackPlan = ctx.plan
	var before := _world_print(ctx)
	var bare := plan.build_blade_state()
	var blades_before := plan.max_blades()
	var mods: Array[StatModifier] = [_modifier(&"strength", 50.0)]
	(ctx.joint as SkillNode).add_child(_temp_addon(mods))
	var state := plan.build_blade_state()
	assert_eq(_column(state, &"vertex_damage"), _column(bare, &"vertex_damage"))
	assert_eq(_column(state, &"vertex_blunting"), _column(bare, &"vertex_blunting"))
	assert_eq(plan.max_blades(), blades_before)
	assert_eq(_world_print(ctx), before, "no board moves")


# 6 ────────────────────────────────────────────────────────────────────────

func test_budget_reads_ignore_temps() -> void:
	var ctx: Dictionary = await _setup()
	var plan: MeleeAttackPlan = ctx.plan
	var toxin := preload("res://skill_node/addons/defs/toxin_addon.tscn")
	_entity.stat_board.poison_aspect.base_value = 2.0
	var blades_before := plan.max_blades()
	var cap_before := plan.currency_cap(&"poison_aspect")
	var no_entity: Array[StatModifier] = []
	var local: Array[StatModifier] = [_modifier(&"blade_size", 2.0)]
	(ctx.source as SkillNode).add_child(_temp_addon(no_entity, local))
	assert_eq(plan.max_blades(), blades_before, "a temp local blade_size on the pivot is no budget")
	assert_true(plan.apply_temp_upgrade(ctx.joint, toxin))
	assert_eq(plan.currency_cap(&"poison_aspect"), cap_before,
			"a temp toxin's poison_aspect is never its own cap")
	assert_eq(plan.max_blades(), blades_before)


# 7 ────────────────────────────────────────────────────────────────────────

func test_temp_spike_ring_adds_no_spike_power() -> void:
	var ctx: Dictionary = await _setup()
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	var before := joint.get_spike_power()
	assert_true(plan.apply_temp_upgrade(joint, preload("res://skill_node/addons/defs/spike_ring_addon.tscn")))
	assert_eq(joint.get_spike_power(), before, "a temp is blade-local, never defensive")


# 8 ────────────────────────────────────────────────────────────────────────

func test_snapshot_round_trip_drops_temp_addons() -> void:
	var source: Graph = autofree(_GRAPH_SCENE.instantiate())
	add_child(source)
	var target: Graph = autofree(_GRAPH_SCENE.instantiate())
	add_child(target)
	await get_tree().process_frame
	var a := _SKILL_NODE_SCENE.instantiate() as SkillNode
	var b := _SKILL_NODE_SCENE.instantiate() as SkillNode
	source.add_skill_node(a)
	source.add_skill_node(b)
	source.add_edge(a, b)
	await get_tree().process_frame
	var temp := _SPIKE_SCENE.instantiate() as SkillNodeAddon
	temp.is_temporary = true
	a.add_child(temp)
	b.add_child(_CLAMP_SCENE.instantiate())
	GraphSnapshot.decode(GraphSnapshot.encode(source), target)
	var da := target.get_by_stable_id(source.get_stable_id(a))
	var db := target.get_by_stable_id(source.get_stable_id(b))
	assert_not_null(da)
	assert_false(da.has_addon(SpikeRingAddon), "a temp addon never crosses the snapshot")
	assert_true(db.has_addon(ClampAddon), "a permanent one still does")

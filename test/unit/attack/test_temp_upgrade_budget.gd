extends GutTest

## Every temp-upgrade currency is a pooled per-swing budget: the price is
## authored on the addon scene ([member SkillNodeAddon.temp_cost_blade_size],
## [member SkillNodeAddon.temp_cost_aspects]), each currency's cap is read
## live, and every carried temp spends its cost vector against it.

var _catalog: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SECOND_DOT_SCENE := preload("res://test/fixtures/addons/second_dot_addon.tscn")
const _BUNKER_SCENE := preload("res://skill_node/addons/defs/bunker_addon.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_entity = Entity.new()
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)


func _spawn(nm: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	return sn


## Source plus a chain of `count` allocated nodes; the first `selected` of them
## are blade members of a fresh plan (all of them when `selected` < 0).
func _setup_chain(budget: float, count: int, selected: int = -1) -> Dictionary:
	_entity.stat_board.blade_size.base_value = budget
	var source := _spawn("Source")
	var members: Array[SkillNode] = []
	var prev := source
	for i in count:
		var m := _spawn("M%d" % i)
		_graph.add_edge(prev, m)
		members.append(m)
		prev = m
	await get_tree().process_frame
	_alloc.force_allocate(_entity, source)
	for m in members:
		_alloc.force_allocate(_entity, m)
	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = _entity
	plan.set_pivot(source)
	var n := count if selected < 0 else selected
	for i in n:
		plan.toggle_member(members[i])
	return {"plan": plan, "source": source, "members": members}


# 1 ────────────────────────────────────────────────────────────────────────

func test_poison_aspect_admits_that_many_toxins_then_denies() -> void:
	var ctx: Dictionary = await _setup_chain(40.0, 6)
	var plan: MeleeAttackPlan = ctx.plan
	var members: Array[SkillNode] = []
	members.assign(ctx.members)
	var toxin := preload("res://skill_node/addons/defs/toxin_addon.tscn")
	_entity.stat_board.poison_aspect.base_value = 3.0
	var n := floori(_entity.stat_board.get_value(&"poison_aspect"))
	assert_gt(n, 0, "the board grants some poison_aspect")
	assert_lt(n, members.size(), "room for one past the cap")
	for i in n:
		assert_true(plan.apply_temp_upgrade(members[i], toxin), "toxin %d fits the aspect" % i)
	assert_eq(plan.currency_remaining(&"poison_aspect"), 0)
	assert_false(plan.can_apply_temp_upgrade(members[n], toxin), "one past the aspect")
	assert_eq(plan.temp_upgrade_denial_reason(members[n], toxin), "temp_upgrade_denied_aspect")


# 2 ────────────────────────────────────────────────────────────────────────

func test_two_kinds_sharing_an_aspect_draw_one_pool() -> void:
	var ctx: Dictionary = await _setup_chain(40.0, 3)
	var plan: MeleeAttackPlan = ctx.plan
	var members: Array[SkillNode] = []
	members.assign(ctx.members)
	var toxin := preload("res://skill_node/addons/defs/toxin_addon.tscn")
	var second := _SECOND_DOT_SCENE
	_entity.stat_board.poison_aspect.base_value = 2.0
	assert_eq(SkillNodeAddon.temp_costs_of(_SECOND_DOT_SCENE).get(&"poison_aspect", 0), 1,
			"the fixture DoT spends poison_aspect too")
	assert_true(plan.apply_temp_upgrade(members[0], toxin))
	assert_true(plan.apply_temp_upgrade(members[1], second))
	assert_eq(plan.currency_spent(&"poison_aspect"), 2)
	assert_false(plan.can_apply_temp_upgrade(members[2], toxin), "a third toxin: pool spent")
	assert_false(plan.can_apply_temp_upgrade(members[2], second), "a third DoT: pool spent")
	assert_eq(plan.temp_upgrade_denial_reason(members[2], second), "temp_upgrade_denied_aspect")


# 3 ────────────────────────────────────────────────────────────────────────

func test_members_and_temp_blade_costs_share_one_budget() -> void:
	var ctx: Dictionary = await _setup_chain(3.0, 3, 2)
	var plan: MeleeAttackPlan = ctx.plan
	var members: Array[SkillNode] = []
	members.assign(ctx.members)
	var clamp := preload("res://skill_node/addons/defs/clamp_addon.tscn")
	assert_eq(plan.max_blades(), 3)
	assert_true(plan.apply_temp_upgrade(members[0], clamp), "the clamp fills the last unit")
	assert_eq(plan.currency_spent(&"blade_size"),
			plan.blade_nodes.size() + SkillNodeAddon.temp_costs_of(clamp)[&"blade_size"])
	assert_eq(plan.currency_remaining(&"blade_size"), 0)
	plan.toggle_member(members[2])
	assert_false(plan.blade_nodes.has(members[2]), "a member past the shared budget is refused")
	assert_lte(plan.currency_spent(&"blade_size"), plan.max_blades())


# 4 ────────────────────────────────────────────────────────────────────────

func test_an_aspect_cost_over_the_cap_is_denied_with_blade_budget_left() -> void:
	var ctx: Dictionary = await _setup_chain(40.0, 1)
	var plan: MeleeAttackPlan = ctx.plan
	var member: SkillNode = ctx.members[0]
	var toxin := preload("res://skill_node/addons/defs/toxin_addon.tscn")
	_entity.stat_board.poison_aspect.base_value = 0.0
	assert_gt(plan.currency_remaining(&"blade_size"),
			SkillNodeAddon.temp_costs_of(toxin)[&"blade_size"], "blade budget to spare")
	assert_false(plan.can_apply_temp_upgrade(member, toxin))
	assert_false(plan.has_temp_upgrade_budget(toxin))
	assert_eq(plan.temp_upgrade_denial_reason(member, toxin), "temp_upgrade_denied_aspect")


# 5 ────────────────────────────────────────────────────────────────────────

func test_a_scene_not_temp_placeable_is_refused() -> void:
	var ctx: Dictionary = await _setup_chain(40.0, 1)
	var plan: MeleeAttackPlan = ctx.plan
	var member: SkillNode = ctx.members[0]
	var bunker := _BUNKER_SCENE
	assert_false(SkillNodeAddon.temp_placeable_of(_BUNKER_SCENE))
	assert_true(member.can_attach_addon(_BUNKER_SCENE.resource_path), "the slot is open")
	assert_false(plan.can_apply_temp_upgrade(member, bunker))
	assert_false(plan.has_temp_upgrade_budget(bunker))


# 6 ────────────────────────────────────────────────────────────────────────

func test_the_scene_cache_reads_what_an_instance_says() -> void:
	for def in _catalog.offered():
		var addon := def.instantiate() as SkillNodeAddon
		assert_eq(SkillNodeAddon.temp_costs_of(def), addon.get_temp_costs(),
				"%s: cached costs" % def.resource_path)
		assert_true(addon.temp_placeable, "%s is temp_placeable" % def.resource_path)
		assert_true(SkillNodeAddon.temp_placeable_of(def), "%s: cached placeable" % def.resource_path)
		addon.free()

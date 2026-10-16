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
	_entity.stat_board.facet(&"poison", StatDef.Role.ASPECT).base_value = 3.0
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
	_entity.stat_board.facet(&"poison", StatDef.Role.ASPECT).base_value = 2.0
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
	_entity.stat_board.facet(&"poison", StatDef.Role.ASPECT).base_value = 0.0
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


# 7 ── escalating temp cost: the n-th temp of a kind costs base + (n-1)·step ──

const _CLAMP_SCENE := preload("res://skill_node/addons/defs/clamp_addon.tscn")
const _BUTTON_SCENE := preload("res://ui/hud/command_tray/bodies/temp_upgrade_button.tscn")


## A clamp kind priced by the test, not the shipped scene. The path encodes
## (base, step) because [method SkillNodeAddon._scene_record] caches by path.
func _clamp_priced(base: int, step: int) -> PackedScene:
	var inst := _CLAMP_SCENE.instantiate() as SkillNodeAddon
	inst.temp_cost_blade_size = base
	inst.temp_cost_step_blade_size = step
	var ps := PackedScene.new()
	ps.pack(inst)
	inst.free()
	ps.take_over_path("res://test/_tmp/clamp_b%d_s%d.tscn" % [base, step])
	return ps


static func _closed_form(k: int, base: int, step: int) -> int:
	return k * base + step * k * (k - 1) / 2


func test_k_temp_clamps_spend_the_linear_escalation() -> void:
	var b := 2
	var s := 3
	var kind := _clamp_priced(b, s)
	var ctx: Dictionary = await _setup_chain(60.0, 4)
	var plan: MeleeAttackPlan = ctx.plan
	var members: Array[SkillNode] = []
	members.assign(ctx.members)
	for k in range(1, 5):
		assert_eq(plan.next_temp_costs(kind)[&"blade_size"], b + (k - 1) * s, "price of temp %d" % k)
		assert_true(plan.apply_temp_upgrade(members[k - 1], kind), "temp %d fits" % k)
		assert_eq(plan.temp_upgrade_cost_total(), _closed_form(k, b, s), "%d temps spend the closed form" % k)
		assert_eq(plan.temp_upgrade_cost_for(kind), _closed_form(k, b, s))
		assert_eq(plan.currency_spent(&"blade_size"), members.size() + _closed_form(k, b, s))


func test_removing_the_first_of_three_spends_as_two() -> void:
	var b := 2
	var s := 3
	var kind := _clamp_priced(b, s)
	var ctx: Dictionary = await _setup_chain(60.0, 3)
	var plan: MeleeAttackPlan = ctx.plan
	var members: Array[SkillNode] = []
	members.assign(ctx.members)
	for m in members:
		assert_true(plan.apply_temp_upgrade(m, kind))
	plan.remove_temp_upgrade(members[0])
	assert_eq(plan.temp_upgrade_cost_total(), _closed_form(2, b, s), "the rest re-price as two")
	assert_eq(plan.next_temp_costs(kind)[&"blade_size"], b + 2 * s)


func test_a_step_zero_kind_never_escalates() -> void:
	var b := 2
	var kind := _clamp_priced(b, 0)
	var ctx: Dictionary = await _setup_chain(60.0, 4)
	var plan: MeleeAttackPlan = ctx.plan
	var members: Array[SkillNode] = []
	members.assign(ctx.members)
	for k in range(1, 5):
		assert_eq(plan.next_temp_costs(kind)[&"blade_size"], b)
		assert_true(plan.apply_temp_upgrade(members[k - 1], kind))
		assert_eq(plan.temp_upgrade_cost_total(), k * b)


func test_the_next_temp_is_refused_below_its_price_while_a_member_fits() -> void:
	var b := 1
	var s := 2
	var k := 2
	var kind := _clamp_priced(b, s)
	var next_price := b + k * s
	var budget := 3 + _closed_form(k, b, s) + next_price - 1
	var ctx: Dictionary = await _setup_chain(float(budget), 4, 3)
	var plan: MeleeAttackPlan = ctx.plan
	var members: Array[SkillNode] = []
	members.assign(ctx.members)
	for i in k:
		assert_true(plan.apply_temp_upgrade(members[i], kind), "temp %d fits" % (i + 1))
	assert_eq(plan.currency_remaining(&"blade_size"), next_price - 1)
	assert_false(plan.can_apply_temp_upgrade(members[2], kind), "one short of the escalated price")
	assert_false(plan.has_temp_upgrade_budget(kind))
	plan.toggle_member(members[3])
	assert_true(plan.blade_nodes.has(members[3]), "a plain member at 1 still fits")


func test_the_tray_card_reads_the_next_price() -> void:
	var b := 1
	var s := 2
	var kind := _clamp_priced(b, s)
	var ctx: Dictionary = await _setup_chain(60.0, 3)
	var plan: MeleeAttackPlan = ctx.plan
	var members: Array[SkillNode] = []
	members.assign(ctx.members)
	var btn := _BUTTON_SCENE.instantiate() as TempUpgradeButton
	add_child_autofree(btn)
	for k in range(0, 3):
		btn.costs = plan.next_temp_costs(kind)
		var price := b + k * s
		assert_eq(btn._cost_text(), "%d blade node%s" % [price, "" if price == 1 else "s"])
		plan.apply_temp_upgrade(members[k], kind)


func test_the_ai_rollout_charges_what_the_plan_charges() -> void:
	_entity.stat_board.blade_size.base_value = 6.0
	var pivot := _spawn("Pivot")
	var chain: Array[SkillNode] = []
	var prev := pivot
	for i in 5:
		var n := _spawn("N%d" % i)
		n.global_position = Vector2(50.0 * (i + 1), 0.0)
		_graph.add_edge(prev, n)
		chain.append(n)
		prev = n
	await get_tree().process_frame
	_alloc.force_allocate(_entity, pivot)
	_entity.core_location = pivot
	for n in chain:
		_alloc.force_allocate(_entity, n)
	var adjacency := AiBladeRollout._owned_adjacency(_entity)
	var archetype := AiBladeRollout._build_archetype(pivot, adjacency, chain[-1].global_position, 6, 3)
	var members: Array[SkillNode] = []
	members.assign(archetype.members)
	var clamps: Array[SkillNode] = []
	clamps.assign(archetype.clamps)
	assert_gte(clamps.size(), 2, "the archetype buys an escalated clamp")
	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = _entity
	plan.set_pivot(pivot)
	for m in members:
		plan.toggle_member(m)
	assert_eq(plan.blade_nodes.size(), members.size(), "every proposed member fits")
	for c in clamps:
		assert_true(plan.apply_temp_upgrade(c, _CLAMP_SCENE), "the plan accepts the AI's clamp on %s" % c.name)
	assert_eq(plan.currency_spent(&"blade_size"), int(archetype.get(&"spent", -1)),
			"the AI's spend is the plan's spend")
	assert_lte(plan.currency_spent(&"blade_size"), plan.max_blades())

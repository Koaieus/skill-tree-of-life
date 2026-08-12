extends GutTest

## #406 — MeleeAttackPlan's plan-local, this-swing-only Clamp/Spikes upgrades:
## shared blade_size budget, addon_slots gating, automatic cleanup on reset(),
## and preview/resolve parity via BladeTempUpgrade.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _CLAMP_SCENE := preload("res://skill_node/addons/clamp_addon.tscn")

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


## Builds source-joint-tip, allocated to _entity, wired into a plan with
## joint+tip as blade_nodes (source is the pivot). `budget` overrides
## blade_size directly (fixture entity is STR 10 / no core bonus, so the real
## default would be 1 — too small to exercise these checks deterministically).
func _setup_plan(budget: float = 3.0, select_tip: bool = true) -> Dictionary:
	_entity.stat_board.blade_size.base_value = budget
	var source := _spawn("Source")
	var joint := _spawn("Joint")
	var tip := _spawn("Tip")
	_graph.add_edge(source, joint)
	_graph.add_edge(joint, tip)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, source)
	_alloc.force_allocate(_entity, joint)
	_alloc.force_allocate(_entity, tip)

	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = _entity
	# Drive selection through the real click flow (not a direct blade_nodes
	# assignment) so the plan's internal GraphMirror stays consistent —
	# _deselect_blade depends on it.
	plan._on_node_left_clicked(source)
	plan._on_node_left_clicked(joint)
	if select_tip:
		plan._on_node_left_clicked(tip)
	return {"plan": plan, "source": source, "joint": joint, "tip": tip}


# ── Budget ─────────────────────────────────────────────────────────────────

func test_apply_temp_upgrade_within_budget_succeeds() -> void:
	# budget 3, 2 members already selected -> exactly 1 room left, enough for
	# one Clamp (cost 1).
	var ctx: Dictionary = await _setup_plan(3.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	assert_true(plan.can_apply_temp_upgrade(joint, BladeTempUpgrade.CLAMP))
	assert_true(plan.apply_temp_upgrade(joint, BladeTempUpgrade.CLAMP),
			"a combo at or under budget must be accepted")
	assert_eq(plan.temp_upgrades[joint], BladeTempUpgrade.CLAMP)


func test_apply_temp_upgrade_rejected_over_budget() -> void:
	# budget 3, 2 members already selected -> 1 room left. Spikes cost 2, so
	# this must be rejected without spending anything.
	var ctx: Dictionary = await _setup_plan(3.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	assert_false(plan.can_apply_temp_upgrade(joint, BladeTempUpgrade.SPIKE))
	assert_false(plan.apply_temp_upgrade(joint, BladeTempUpgrade.SPIKE))
	assert_eq(plan.temp_upgrade_cost_total(), 0,
			"a denied apply must not spend budget")


func test_apply_temp_upgrade_rejected_once_budget_already_spent() -> void:
	# budget 3, 2 members -> 1 room. Spend it on joint's Clamp; a second Clamp
	# on tip must now be rejected even though tip itself has an open slot.
	var ctx: Dictionary = await _setup_plan(3.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	var tip: SkillNode = ctx.tip
	assert_true(plan.apply_temp_upgrade(joint, BladeTempUpgrade.CLAMP))
	assert_false(plan.can_apply_temp_upgrade(tip, BladeTempUpgrade.CLAMP))
	assert_false(plan.apply_temp_upgrade(tip, BladeTempUpgrade.CLAMP))


func test_spent_temp_upgrade_budget_blocks_a_new_member_selection() -> void:
	# budget 3, only 1 member (joint) selected -> 2 room. Spend all of it on a
	# Spikes upgrade; selecting a second member (tip) must now be refused even
	# though tip is a valid neighbor with an open slot — the two spends share
	# one pool by design (#406's confirmed decision).
	var ctx: Dictionary = await _setup_plan(3.0, false)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	var tip: SkillNode = ctx.tip
	assert_true(plan.apply_temp_upgrade(joint, BladeTempUpgrade.SPIKE))
	assert_eq(plan.get_node_role(tip), HighlightProvider.HighlightRole.NONE,
			"a node that would exceed the combined budget must not read as selectable")
	plan._on_node_left_clicked(tip)
	assert_false(plan.blade_nodes.has(tip),
			"member selection must respect budget already spent on temp upgrades")


# ── Slot gate ──────────────────────────────────────────────────────────────

func test_apply_temp_upgrade_rejected_when_addon_slots_full() -> void:
	var ctx: Dictionary = await _setup_plan(10.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	# force_allocate gives allocation_level 1 -> addon_slots == 1. Filling it
	# with a real addon leaves no open slot for a temp upgrade, even though
	# budget is generous.
	var clamp := _CLAMP_SCENE.instantiate() as ClampAddon
	joint.add_child(clamp)
	await get_tree().process_frame

	assert_false(plan.can_apply_temp_upgrade(joint, BladeTempUpgrade.CLAMP),
			"a node at addon_slots capacity must refuse a temp upgrade")
	assert_false(plan.apply_temp_upgrade(joint, BladeTempUpgrade.CLAMP))
	assert_eq(plan.temp_upgrade_cost_total(), 0,
			"a denied apply must not spend budget")


# ── Cleanup ────────────────────────────────────────────────────────────────

func test_reset_clears_temp_upgrades_and_leaves_no_real_addon() -> void:
	var ctx: Dictionary = await _setup_plan(3.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	assert_true(plan.apply_temp_upgrade(joint, BladeTempUpgrade.CLAMP))
	var addons_before := joint.get_addons().size()
	plan.reset()
	assert_true(plan.temp_upgrades.is_empty(),
			"reset() must clear the temp-upgrade dictionary")
	assert_eq(joint.get_addons().size(), addons_before,
			"a temp upgrade must never attach a real SkillNodeAddon")


func test_deselecting_member_refunds_its_temp_upgrade() -> void:
	var ctx: Dictionary = await _setup_plan(3.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	assert_true(plan.apply_temp_upgrade(joint, BladeTempUpgrade.CLAMP))
	plan._on_node_left_clicked(joint)  # toggle off — same as a real deselect click
	assert_false(plan.temp_upgrades.has(joint),
			"dropping a member must refund any temp upgrade it carried")


# ── Preview / resolve parity ──────────────────────────────────────────────

func test_temp_clamp_matches_permanent_clamp_constraints() -> void:
	var ctx: Dictionary = await _setup_plan(3.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	assert_true(plan.apply_temp_upgrade(joint, BladeTempUpgrade.CLAMP))
	var state := plan.build_blade_state()
	# selection order is [source, joint, tip] -> indices 0, 1, 2. joint (idx 1)
	# neighbors source (0) and tip (2); the weld brace joins them.
	var found_brace := false
	for c in state.constraints:
		if c is BladeDistanceConstraint:
			var dc := c as BladeDistanceConstraint
			if (dc.a == 0 and dc.b == 2) or (dc.a == 2 and dc.b == 0):
				found_brace = true
	assert_true(found_brace,
			"a temp Clamp must produce the same weld brace a permanent Clamp would")


func test_temp_spike_adds_the_same_bonus_a_real_spike_would() -> void:
	# Spikes cost 2; budget 4 leaves exactly 2 room after the 2 selected members.
	var ctx: Dictionary = await _setup_plan(4.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	var base_dmg := float(joint.get_local_value(&"blade_damage"))
	assert_true(plan.apply_temp_upgrade(joint, BladeTempUpgrade.SPIKE))
	var state := plan.build_blade_state()
	assert_almost_eq(state.vertex_damage[1], base_dmg + 1.5, 0.001,
			"temp Spike must add the procgen SpikeRingAddon's authored bonus (+1.5 blade_damage)")


func test_skill_blade_preview_matches_build_blade_state_for_temp_upgrades() -> void:
	var ctx: Dictionary = await _setup_plan(3.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	var source: SkillNode = ctx.source
	var tip: SkillNode = ctx.tip
	assert_true(plan.apply_temp_upgrade(joint, BladeTempUpgrade.CLAMP))

	var resolve_state := plan.build_blade_state()

	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	add_child_autofree(blade)
	var nodes: Array[SkillNode] = [source, joint, tip]
	blade.build_from_skill_nodes(
			nodes, source, plan.get_induced_edges(), _entity, plan.temp_upgrades)

	assert_eq(_constraint_pairs(blade.state), _constraint_pairs(resolve_state),
			"preview (SkillBlade) and resolve (build_blade_state) must produce the exact same constraint set for identical temp upgrades")


## Sorted (a, b) index pairs, so two constraint arrays can be compared by
## content rather than just by size.
func _constraint_pairs(state: BladeState) -> Array:
	var pairs: Array = []
	for c in state.constraints:
		if c is BladeDistanceConstraint:
			var dc := c as BladeDistanceConstraint
			var a: int = min(dc.a, dc.b)
			var b: int = max(dc.a, dc.b)
			pairs.append([a, b])
	pairs.sort()
	return pairs

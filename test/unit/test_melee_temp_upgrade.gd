extends GutTest

## A `var`, not a `const`: the parser constant-folds `CONST.kinds[i]`.
var _catalog: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")

## #406 — MeleeAttackPlan's temp Clamp/Spikes upgrades: shared blade_size
## budget, addon_slots gating, and a REAL SkillNodeAddon attached/freed
## exactly like a permanent one (owner's retracted-design correction — see
## the #406 issue comments). Preview/resolve parity falls out of the normal
## addon-dispatch loop (#405) since a temp upgrade is a real `_addons` entry,
## not a separately-dispatched shadow structure.

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
	plan.set_pivot(source)
	plan.toggle_member(joint)
	if select_tip:
		plan.toggle_member(tip)
	return {"plan": plan, "source": source, "joint": joint, "tip": tip}


# ── Budget ─────────────────────────────────────────────────────────────────

func test_apply_temp_upgrade_within_budget_succeeds() -> void:
	# budget 3, 2 members already selected -> exactly 1 room left, enough for
	# one Clamp (cost 1).
	var ctx: Dictionary = await _setup_plan(3.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	assert_true(plan.can_apply_temp_upgrade(joint, _catalog.by_id(&"clamp")))
	assert_true(plan.apply_temp_upgrade(joint, _catalog.by_id(&"clamp")),
			"a combo at or under budget must be accepted")
	var found_temp := false
	for a in joint.get_addons():
		if a.is_temporary:
			found_temp = true
			assert_eq(a.get_kind(), _catalog.by_id(&"clamp").scene.resource_path,
					"the attached temp addon must be the requested kind")
	assert_true(found_temp, "apply_temp_upgrade must attach a REAL SkillNodeAddon")


func test_apply_temp_upgrade_rejected_over_budget() -> void:
	# budget 3, 2 members already selected -> 1 room left. Spikes cost 2, so
	# this must be rejected without spending anything.
	var ctx: Dictionary = await _setup_plan(3.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	assert_false(plan.can_apply_temp_upgrade(joint, _catalog.by_id(&"spike_ring")))
	assert_false(plan.apply_temp_upgrade(joint, _catalog.by_id(&"spike_ring")))
	assert_eq(plan.temp_upgrade_cost_total(), 0,
			"a denied apply must not spend budget")


func test_apply_temp_upgrade_rejected_once_budget_already_spent() -> void:
	# budget 3, 2 members -> 1 room. Spend it on joint's Clamp; a second Clamp
	# on tip must now be rejected even though tip itself has an open slot.
	var ctx: Dictionary = await _setup_plan(3.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	var tip: SkillNode = ctx.tip
	assert_true(plan.apply_temp_upgrade(joint, _catalog.by_id(&"clamp")))
	assert_false(plan.can_apply_temp_upgrade(tip, _catalog.by_id(&"clamp")))
	assert_false(plan.apply_temp_upgrade(tip, _catalog.by_id(&"clamp")))


func test_spent_temp_upgrade_budget_blocks_a_new_member_selection() -> void:
	# budget 3, only 1 member (joint) selected -> 2 room. Spend all of it on a
	# Spikes upgrade; selecting a second member (tip) must now be refused even
	# though tip is a valid neighbor with an open slot — the two spends share
	# one pool by design (#406's confirmed decision).
	var ctx: Dictionary = await _setup_plan(3.0, false)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	var tip: SkillNode = ctx.tip
	assert_true(plan.apply_temp_upgrade(joint, _catalog.by_id(&"spike_ring")))
	assert_eq(plan.get_node_role(tip), HighlightProvider.HighlightRole.NONE,
			"a node that would exceed the combined budget must not read as selectable")
	plan.toggle_member(tip)
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
	var clamp_addon := _CLAMP_SCENE.instantiate() as ClampAddon
	joint.add_child(clamp_addon)
	await get_tree().process_frame

	assert_false(plan.can_apply_temp_upgrade(joint, _catalog.by_id(&"clamp")),
			"a node at addon_slots capacity must refuse a temp upgrade")
	assert_false(plan.apply_temp_upgrade(joint, _catalog.by_id(&"clamp")))
	assert_eq(plan.temp_upgrade_cost_total(), 0,
			"a denied apply must not spend budget")


func test_unique_addon_blocks_temp_upgrade_of_same_type() -> void:
	# Generous slots (2) so slot budget alone wouldn't block it — only
	# ClampAddon's `unique` collision should.
	var ctx: Dictionary = await _setup_plan(10.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	joint.node_board.get_stat(&"addon_slots").base_value = 2.0
	var permanent := _CLAMP_SCENE.instantiate() as ClampAddon
	joint.add_child(permanent)
	await get_tree().process_frame

	assert_false(plan.can_apply_temp_upgrade(joint, _catalog.by_id(&"clamp")),
			"a permanent Clamp already on the node must block a temp Clamp too (unique)")
	assert_false(plan.apply_temp_upgrade(joint, _catalog.by_id(&"clamp")))
	assert_eq(plan.temp_upgrade_cost_total(), 0)


func test_pivot_is_not_a_valid_temp_upgrade_target() -> void:
	var ctx: Dictionary = await _setup_plan(10.0)
	var plan: MeleeAttackPlan = ctx.plan
	var source: SkillNode = ctx.source
	assert_false(plan.can_apply_temp_upgrade(source, _catalog.by_id(&"clamp")),
			"the pivot drives the swing and is never a valid temp-upgrade target")
	assert_false(plan.apply_temp_upgrade(source, _catalog.by_id(&"clamp")))


# ── Cleanup ────────────────────────────────────────────────────────────────

func test_reset_frees_the_real_temp_addon() -> void:
	var ctx: Dictionary = await _setup_plan(3.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	var addons_before := joint.get_addons().size()
	assert_true(plan.apply_temp_upgrade(joint, _catalog.by_id(&"clamp")))
	assert_eq(joint.get_addons().size(), addons_before + 1,
			"a temp upgrade must attach a real SkillNodeAddon while it's active")
	plan.reset()
	assert_eq(joint.get_addons().size(), addons_before,
			"reset() must free the attached temp addon")


func test_toggle_temp_upgrade_removes_an_existing_one_of_the_same_kind() -> void:
	# Same click-to-toggle shape as blade-member selection (#406 manual-test
	# feedback: removing a temp upgrade shouldn't require canceling the
	# whole blade).
	var ctx: Dictionary = await _setup_plan(3.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	var addons_before := joint.get_addons().size()
	assert_true(plan.toggle_temp_upgrade(joint, _catalog.by_id(&"clamp")),
			"first toggle must apply")
	assert_eq(joint.get_addons().size(), addons_before + 1)
	assert_true(plan.toggle_temp_upgrade(joint, _catalog.by_id(&"clamp")),
			"second toggle on the same node/kind must remove it")
	assert_eq(joint.get_addons().size(), addons_before,
			"toggling off must free the attached temp addon")


func test_deselecting_member_refunds_its_temp_upgrade() -> void:
	var ctx: Dictionary = await _setup_plan(3.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	var addons_before := joint.get_addons().size()
	assert_true(plan.apply_temp_upgrade(joint, _catalog.by_id(&"clamp")))
	plan.toggle_member(joint)  # toggle off
	assert_eq(joint.get_addons().size(), addons_before,
			"dropping a member must free any temp upgrade it carried")


func test_cancel_attack_frees_attached_temp_addon() -> void:
	var ctx: Dictionary = await _setup_plan(3.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	assert_true(plan.apply_temp_upgrade(joint, _catalog.by_id(&"clamp")))
	var addons_with_upgrade := joint.get_addons().size()

	var battle := BattleSystem.new()
	battle.temp_upgrade_catalog = _catalog
	add_child_autofree(battle)
	battle.attack_plan = plan
	battle.cancel_attack()

	assert_eq(joint.get_addons().size(), addons_with_upgrade - 1,
			"cancel_attack() must not leak an attached temp addon")


# ── Preview / resolve parity ──────────────────────────────────────────────

func test_temp_clamp_matches_permanent_clamp_constraints() -> void:
	var ctx: Dictionary = await _setup_plan(3.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	assert_true(plan.apply_temp_upgrade(joint, _catalog.by_id(&"clamp")))
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
	var tip: SkillNode = ctx.tip
	# Compare against an actual PERMANENT SpikeRingAddon on an equivalent node
	# rather than hardcoding its authored modifier math (operation/value) here
	# — the retracted BladeTempUpgrade dispatcher hardcoded that math (read
	# the modifier's raw `.value` and added it flat), which was itself a
	# latent bug/approximation that never actually matched a permanent
	# Spike's real effect. Going through the real stat pipeline (#406's
	# correction) fixes that for free, and this assertion stays correct no
	# matter how the addon's authored bonus is tuned later.
	var permanent := _SPIKE_SCENE.instantiate() as SpikeRingAddon
	tip.add_child(permanent)
	await get_tree().process_frame
	var permanent_dmg := float(tip.get_local_value(&"blade_damage"))

	assert_true(plan.apply_temp_upgrade(joint, _catalog.by_id(&"spike_ring")))
	var state := plan.build_blade_state()
	assert_almost_eq(state.vertex_damage[1], permanent_dmg, 0.001,
			"temp Spike must apply the same authored blade_damage bonus a permanent Spike would")


func test_skill_blade_preview_matches_build_blade_state_for_temp_upgrades() -> void:
	var ctx: Dictionary = await _setup_plan(3.0)
	var plan: MeleeAttackPlan = ctx.plan
	var joint: SkillNode = ctx.joint
	var source: SkillNode = ctx.source
	var tip: SkillNode = ctx.tip
	assert_true(plan.apply_temp_upgrade(joint, _catalog.by_id(&"clamp")))

	var resolve_state := plan.build_blade_state()

	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	add_child_autofree(blade)
	var nodes: Array[SkillNode] = [source, joint, tip]
	blade.build_from_skill_nodes(nodes, source, plan.get_induced_edges(), _entity, plan.vertex_fill)

	assert_eq(_constraint_pairs(blade.state), _constraint_pairs(resolve_state),
			"preview (SkillBlade) and resolve (build_blade_state) must produce the exact same constraint set for identical temp upgrades — they're the same real-addon ledger now, not two dispatch paths")


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


# ── Aspect cap (#1268) ──────────────────────────────────────────────────────

const _TOXIN_SCENE := preload("res://skill_node/addons/defs/toxin_addon.tscn")


## Source plus a chain of `count` allocated members, all selected on a plan.
func _setup_chain(budget: float, count: int) -> Dictionary:
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
	for m in members:
		plan.toggle_member(m)
	return {"plan": plan, "source": source, "members": members}


func _modifier(stat_id: StringName, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.value = value
	return m


## A temp addon (clamp's def) authored with one extra entity modifier.
func _temp_addon_with(mod: StatModifier) -> SkillNodeAddon:
	var addon := _CLAMP_SCENE.instantiate() as SkillNodeAddon
	addon.entity_modifiers = [mod] as Array[StatModifier]
	addon.temp_upgrade_def = _catalog.by_id(&"clamp")
	return addon


func test_poison_aspect_caps_toxins_per_swing() -> void:
	var ctx: Dictionary = await _setup_chain(20.0, 3)
	var plan: MeleeAttackPlan = ctx.plan
	var members: Array[SkillNode] = []
	members.assign(ctx.members)
	var toxin := _catalog.by_id(&"toxin")
	_entity.stat_board.poison_aspect.base_value = 2.0
	assert_true(plan.apply_temp_upgrade(members[0], toxin), "first toxin fits the aspect")
	assert_true(plan.apply_temp_upgrade(members[1], toxin), "second toxin fits the aspect")
	assert_eq(plan.temp_upgrade_count_for(toxin), 2)
	assert_false(plan.can_apply_temp_upgrade(members[2], toxin),
			"a third toxin runs past poison_aspect 2")
	assert_eq(plan.temp_upgrade_denial_reason(members[2], toxin), "temp_upgrade_denied_aspect")


func test_zero_poison_aspect_refuses_any_toxin() -> void:
	var ctx: Dictionary = await _setup_chain(20.0, 1)
	var plan: MeleeAttackPlan = ctx.plan
	var member: SkillNode = ctx.members[0]
	_entity.stat_board.poison_aspect.base_value = 0.0
	assert_false(plan.can_apply_temp_upgrade(member, _catalog.by_id(&"toxin")))
	assert_false(plan.has_temp_upgrade_budget(_catalog.by_id(&"toxin")))


func test_clamp_without_an_aspect_is_limited_only_by_budget() -> void:
	var ctx: Dictionary = await _setup_chain(20.0, 3)
	var plan: MeleeAttackPlan = ctx.plan
	var clamp := _catalog.by_id(&"clamp")
	assert_eq(clamp.aspect_stat_id, &"", "clamp is uncapped")
	for m in ctx.members:
		assert_true(plan.apply_temp_upgrade(m, clamp), "budget 20 fits every clamp")


func test_a_temp_toxin_grants_no_poison_aspect_but_a_permanent_one_does() -> void:
	var ctx: Dictionary = await _setup_chain(20.0, 2)
	var plan: MeleeAttackPlan = ctx.plan
	_entity.stat_board.poison_aspect.base_value = 1.0
	var before: float = _entity.stat_board.get_value(&"poison_aspect")
	assert_true(plan.apply_temp_upgrade(ctx.members[0], _catalog.by_id(&"toxin")))
	assert_eq(_entity.stat_board.get_value(&"poison_aspect"), before,
			"a temp toxin's modifiers never reach the board, so never its own cap")
	var permanent := _TOXIN_SCENE.instantiate() as SkillNodeAddon
	(ctx.members[1] as SkillNode).add_child(permanent)
	assert_eq(_entity.stat_board.get_value(&"poison_aspect"), before + 1.0,
			"a permanent toxin on an allocated node still raises poison_aspect")


func test_a_temp_addon_grants_no_blade_size() -> void:
	var ctx: Dictionary = await _setup_chain(5.0, 1)
	var plan: MeleeAttackPlan = ctx.plan
	var before := plan.max_blades()
	(ctx.members[0] as SkillNode).add_child(_temp_addon_with(_modifier(&"blade_size", 1.0)))
	assert_eq(plan.max_blades(), before, "a temp addon never feeds the budget it is paid from")


func test_a_temp_addon_entity_wide_blade_damage_folds_into_the_swing_not_the_board() -> void:
	var ctx: Dictionary = await _setup_chain(5.0, 1)
	var plan: MeleeAttackPlan = ctx.plan
	var member: SkillNode = ctx.members[0]
	var before: float = _entity.stat_board.get_value(&"blade_damage")
	var bare := plan.build_blade_state()
	var addon := _temp_addon_with(_modifier(&"blade_damage", 1.0))
	member.add_child(addon)
	assert_eq(_entity.stat_board.get_value(&"blade_damage"), before,
			"a temp addon's entity modifier never reaches the board")
	var state := plan.build_blade_state()
	for i in state.vertex_damage.size():
		assert_gt(state.vertex_damage[i], bare.vertex_damage[i],
				"it folds into every vertex of the swing instead")
	member.remove_child(addon)
	addon.free()
	assert_eq(Array(plan.build_blade_state().vertex_damage), Array(bare.vertex_damage),
			"and drops on detach")

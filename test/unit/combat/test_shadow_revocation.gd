extends GutTest

## Shadow MITIGATION parity (#520 — see docs/domain/attack-timeline.md). #518
## closed shadow ATTRITION parity: a shadow agreed with the live path on WHICH
## nodes a cascade strips and what leaving cost. It did not revoke what those
## nodes were granting, so a shadow's wave N+1 resolved against pre-cascade
## armour. These pin that it now does.
##
## Fixture — one defender, deliberately with NO cut vertex:
## [codeblock]
##   C(core) ── A ── B
##      └── E1 ── E2 ─┘
## [/codeblock]
## A carries an entity-scoped `armor` modifier. Killing A revokes that grant
## WITHOUT islanding anything (B is still reachable the long way round), which
## separates the thing under test from #518's cascade set. It also moves B from
## 2 hops to 3, which is what makes the distance-scaled aura's VALUES — not just
## its membership — observable.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

const _NODE_ARMOR: float = 5.0
const _HIT: float = 12.0

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _defender: Entity
var _c: SkillNode
var _a: SkillNode
var _b: SkillNode
var _e1: SkillNode
var _e2: SkillNode
var _worlds: Array[CombatWorld] = []


func before_each() -> void:
	_worlds = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_c = _new_node("C")
	_a = _new_node("A")
	_b = _new_node("B")
	_e1 = _new_node("E1")
	_e2 = _new_node("E2")
	_graph.add_edge(_c, _a)
	_graph.add_edge(_a, _b)
	_graph.add_edge(_c, _e1)
	_graph.add_edge(_e1, _e2)
	_graph.add_edge(_e2, _b)

	_a.modifiers.append(_armor_mod(_NODE_ARMOR))

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_battle = BattleSystem.new()
	_battle.allocation_system = _alloc
	_battle.graph = _graph
	add_child_autofree(_battle)

	_defender = autofree(Entity.new()) as Entity
	_defender.display_name = "Defender"
	_defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_defender)
	await get_tree().process_frame

	for n in [_c, _a, _b, _e1, _e2]:
		_alloc.force_allocate(_defender, n)
	_defender.core_location = _c
	_defender.stat_board.armor.base_value = 0.0


func after_each() -> void:
	for w in _worlds:
		w.free_shadow()


func _new_node(n: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = n
	sn.position = Vector2(_graph.get_skill_nodes().size() * 100.0, 0.0)
	_graph.add_skill_node(sn)
	return sn


func _armor_mod(value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BONUS
	m.value = value
	return m


func _shadow() -> CombatWorld:
	var w := CombatWorld.shadow()
	_worlds.append(w)
	return w


func _damage(amount: float) -> DamageInstance:
	var d := DamageInstance.new()
	d.type = DamageInstance.Type.PHYSICAL
	d.amount = amount
	return d


## Deal `amount` to `node` in `world` and report what actually landed after
## mitigation — the number the whole issue is about.
func _strike(world: CombatWorld, node: SkillNode, amount: float) -> float:
	var d := _damage(amount)
	world.combat_for(node).take_damage(amount, d)
	return d.effective_amount


## Kill A outright in `world`, which revokes its armour grant.
func _kill_a(world: CombatWorld) -> void:
	var slice := world.combat_for(_a)
	_strike(world, _a, slice.get_max_hp() + _NODE_ARMOR + 100.0)
	assert_false(slice.is_allocated(), "fixture: A must actually die")


# ── the acceptance ───────────────────────────────────────────────────────────

func test_wave_after_a_shadow_cascade_lands_more_than_the_wave_before() -> void:
	var w := _shadow()
	var before := _strike(w, _c, _HIT)
	_kill_a(w)
	var after := _strike(w, _c, _HIT)

	assert_almost_eq(before, _HIT - _NODE_ARMOR, 0.001, "wave N is mitigated by A's armour")
	assert_gt(after, before, "#520: wave N+1 must land MORE — A's armour is gone")
	assert_almost_eq(after, _HIT, 0.001, "and exactly the unmitigated number")


func test_and_it_lands_the_same_amount_the_live_path_does() -> void:
	var w := _shadow()
	var sim_before := _strike(w, _c, _HIT)
	_kill_a(w)
	var sim_after := _strike(w, _c, _HIT)

	var live := CombatWorld.live()
	var live_before := _strike(live, _c, _HIT)
	_kill_a(live)
	var live_after := _strike(live, _c, _HIT)

	assert_almost_eq(sim_before, live_before, 0.001)
	assert_almost_eq(sim_after, live_after, 0.001,
			"the shadow's post-cascade mitigation is the real one, not an estimate")


func test_a_shadow_cascade_leaves_the_real_grant_bookkeeping_byte_identical() -> void:
	# The regression #520's `_scaled_sets.erase` finding predicts: a shadow
	# borrowing the mutating helpers would corrupt live state here.
	var effects_before: int = _defender.get_effects().size()
	var scaled_before: int = _a._scaled_sets.size()
	var scaled_effects_before: int = _a._scaled_effect_sets.size()
	var armor_before: float = float(_c.get_local_value(&"armor"))
	var owner_before := _a.owned_by

	_kill_a(_shadow())

	assert_eq(_defender.get_effects().size(), effects_before,
			"the real entity's effect ledger is untouched")
	assert_eq(_a._scaled_sets.size(), scaled_before, "and the real node's _scaled_sets")
	assert_eq(_a._scaled_effect_sets.size(), scaled_effects_before)
	assert_almost_eq(float(_c.get_local_value(&"armor")), armor_before, 0.001,
			"the real board still carries the armour the shadow revoked")
	assert_same(_a.owned_by, owner_before)


func test_a_distance_scaled_aura_recomputes_its_VALUES_on_a_shadow() -> void:
	# ProportionalScale over HopMetric, measured on the OWNED subgraph: B sits 2
	# hops from the core through A, and 3 once A is gone. Membership does not
	# change — B stays owned either way — so only a real re-derivation moves the
	# number. A revocation ledger replaying a diff could not do this, which is
	# the trap attack-timeline.md writes up.
	var aura := AuraEffect.new()
	aura.metric = HopMetric.new()
	aura.distance_scale = ProportionalScale.new()
	(aura.distance_scale as ProportionalScale).per_unit = 1.0
	aura.modifiers.append(_armor_mod(-1.0))
	_defender.grant_effect(aura)

	var w := _shadow()
	var b_before: float = float(w.combat_for(_b).get_local_value(&"armor"))
	_kill_a(w)
	var b_after: float = float(w.combat_for(_b).get_local_value(&"armor"))

	assert_almost_eq(b_before, _NODE_ARMOR - 2.0, 0.001, "2 hops via A, minus A's own +5")
	assert_almost_eq(b_after, -3.0, 0.001,
			"3 hops the long way round, and A's +5 revoked with it")
	assert_almost_eq(float(_b.get_local_value(&"armor")), b_before, 0.001,
			"the real B never moved")


func test_a_shadow_aura_grants_land_on_the_shadow_s_nodes_not_the_real_ones() -> void:
	# The failure mode this guards is silent: EffectContext used to reach
	# `node.add_local_modifier` directly, so a shadow recompute would have
	# stacked modifiers onto the live node board every time it ran.
	var aura := AuraEffect.new()
	aura.modifiers.append(_armor_mod(3.0))
	_defender.grant_effect(aura)
	var real_local_before: int = _b._local_modifiers.size()

	var w := _shadow()
	_kill_a(w)  # forces at least one recompute on the shadow

	assert_eq(_b._local_modifiers.size(), real_local_before,
			"a shadow recompute must not add a single modifier to a real node board")


func test_tags_granted_during_a_shadow_recompute_stay_on_the_shadow() -> void:
	var aura := TagAuraEffect.new()
	aura.tag = &"shadow_only"
	_defender.grant_effect(aura)
	# The live grant already tagged the real nodes; what must not happen is the
	# shadow's own recompute touching them again, or its revoke clearing them.
	var real_tagged: bool = _b.has_tag(&"shadow_only")

	var w := _shadow()
	_kill_a(w)

	assert_eq(_b.has_tag(&"shadow_only"), real_tagged,
			"the real node's tag refcount is the live world's alone")

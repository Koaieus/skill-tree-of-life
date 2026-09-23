extends GutTest

## D-9 gated/ramping node regen + D-10 CoreClass healing aura (#270, ported
## onto AuraEffect as HealAuraEffect in #720).
##
## Fixtures follow .claude/rules/scene-composition.md (instantiate scenes,
## don't hand-compose) and .claude/rules/graph.md (populate a Graph via
## add_skill_node / add_edge so Navigator/EntityNavigator actually mirror it).
##
## Below drives `_on_turn_started` by name deliberately (#989): this file
## tests the upkeep/regen formula, not the `TurnManager.turn_started` wiring
## that invokes it — that connect is asserted once, in
## `test/integration/test_game_root_wiring.gd::test_entity_signals_connect_on_spawn`.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = Entity.new()
	autofree(_entity)
	_entity.display_name = "Regenerator"
	# Flat board: formula test arranges its own stat inputs, tuned CON must not ride in.
	_entity.stat_board = TestBoards.flat_entity_board()
	# Keep the turn upkeep from levelling up mid-test. WIS 10 gives
	# xp_per_turn = floor(10/2) = 5 against an xp cap of exactly 5, so any
	# _on_turn_started() that isn't skipped levels the entity, which grants
	# +1 CON, which raises node_health by 1 — and since D-31 that cap rise
	# correctly ratchets +1 into every owned node's current HP. Harmless in
	# play, but it lands on top of the regen/aura numbers these tests assert
	# exactly. Nothing here tests levelling, so take the variable off the table.
	_entity.stat_board.xp.base_value = 100000.0
	# These tests drive ONE _on_turn_started() and read its effects, so the
	# entity must be past the first-turn upkeep skip before the first call.
	_entity.turns_taken = 1
	_graph.add_child(_entity)

	await get_tree().process_frame  # entity._ready wires navigator


func _make_node(node_name: String) -> SkillNode:
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	n.name = node_name
	_graph.add_skill_node(n)
	return n


func _hp_pool(node: SkillNode) -> PoolStat:
	return node.node_board.get_stat(&"node_health") as PoolStat if node.node_board != null else null


func _true_damage(node: SkillNode, amount: float) -> void:
	var dmg := DamageInstance.new()
	dmg.amount = amount
	dmg.type = DamageInstance.Type.TRUE
	node.take_damage(amount, dmg)


# ── D-9: gated base regen ────────────────────────────────────────────────

func test_damaged_this_turn_gets_no_base_heal_and_resets_stacks() -> void:
	var n := _make_node("N0")
	_alloc.force_allocate(_entity, n)
	var hp := _hp_pool(n)
	n.regen_stacks = 2  # pretend it was mid-ramp
	_true_damage(n, 4.0)
	var before := hp.current
	n.apply_turn_regen()
	assert_almost_eq(hp.current, before, 0.001, "a node damaged this turn gets no base heal")
	assert_eq(n.regen_stacks, 0, "taking damage resets regen_stacks to 0")


func test_ramp_grows_over_three_undamaged_turns() -> void:
	var n := _make_node("N0")
	_alloc.force_allocate(_entity, n)
	var hp := _hp_pool(n)
	_entity.stat_board.node_healing.base_value = 2.0
	_entity.stat_board.node_healing_ramp.base_value = 1.0
	_true_damage(n, 9.0)  # current = 1, plenty of headroom under max = 10
	# The turn damage lands, the gate still applies once (D-9): no heal, stack stays 0.
	n.apply_turn_regen()
	assert_almost_eq(hp.current, 1.0, 0.001, "gate turn: still no heal")
	assert_eq(n.regen_stacks, 0)

	n.apply_turn_regen()  # turn 1: node_healing + 0*ramp = 2
	assert_almost_eq(hp.current, 3.0, 0.001, "turn 1 heals node_healing alone")
	assert_eq(n.regen_stacks, 1)

	n.apply_turn_regen()  # turn 2: node_healing + 1*ramp = 3
	assert_almost_eq(hp.current, 6.0, 0.001, "turn 2 heals node_healing + ramp")
	assert_eq(n.regen_stacks, 2)

	n.apply_turn_regen()  # turn 3: node_healing + 2*ramp = 4
	assert_almost_eq(hp.current, 10.0, 0.001, "turn 3 heals node_healing + 2*ramp")
	assert_eq(n.regen_stacks, 3)


func test_regen_stacks_resets_on_reaching_full_hp() -> void:
	var n := _make_node("N0")
	_alloc.force_allocate(_entity, n)
	var hp := _hp_pool(n)
	_true_damage(n, 1.0)
	n.apply_turn_regen()  # gate turn, no heal
	n.apply_turn_regen()  # heals back to full (small damage + default node_healing)
	assert_true(hp.current >= hp.value, "should be back at full HP")
	n.apply_turn_regen()  # next upkeep observes "already full" and resets the stack
	assert_eq(n.regen_stacks, 0, "reaching full HP resets regen_stacks")


func test_regen_stacks_resets_on_taking_damage_mid_ramp() -> void:
	var n := _make_node("N0")
	_alloc.force_allocate(_entity, n)
	_true_damage(n, 8.0)
	n.apply_turn_regen()  # gate turn
	n.apply_turn_regen()  # ramp turn 1
	n.apply_turn_regen()  # ramp turn 2
	assert_gt(n.regen_stacks, 0, "sanity: ramp actually built up")
	_true_damage(n, 1.0)
	n.apply_turn_regen()
	assert_eq(n.regen_stacks, 0, "taking damage mid-ramp resets regen_stacks")


func test_turn_start_no_longer_refills_to_full() -> void:
	var n := _make_node("N0")
	_alloc.force_allocate(_entity, n)
	var hp := _hp_pool(n)
	_true_damage(n, 8.0)
	_entity._on_turn_started(_entity)
	assert_lt(hp.current, hp.value,
			"regression guard: turn start must not refill to full (D-9 removed that sweep)")


# ── D-10: CoreClass healing aura (HealAuraEffect on AuraEffect, #720) ─────
#
# Driven through Entity._on_turn_started — the production path — never a
# hand-rolled `_distances`/`values_from` call. Every node is pre-damaged
# (`_true_damage`) immediately before the turn so D-9's base-regen gate reads
# "damaged this turn" and contributes exactly 0, isolating the aura's own
# heal as a clean before/after delta.

func _chain(core: SkillNode, length: int, entity: Entity, alloc: AllocationSystem) -> Array[SkillNode]:
	var chain: Array[SkillNode] = [core]
	var prev := core
	for i in length:
		var n := _make_node("chain_%d" % i)
		_graph.add_edge(prev, n)
		alloc.force_allocate(entity, n)
		chain.append(n)
		prev = n
	return chain


## Builds a `HealAuraEffect` over an owned-subgraph hop reach with an
## `ExpressionScale` formula — the same two knobs (`reach`, `distance_scale`)
## every authored aura uses, `metric` left `null` (reach's own hop distances).
func _heal_aura(base: float, max_hops: int, formula: String,
		discard: AuraEffect.Discard = AuraEffect.Discard.NON_POSITIVE,
		con_coefficient: float = 0.0) -> HealAuraEffect:
	var aura := HealAuraEffect.new()
	aura.base = base
	aura.con_coefficient = con_coefficient
	var reach := HopRangeFinder.new()
	reach.max_hops = max_hops
	aura.reach = reach
	var scale := ExpressionScale.new()
	scale.formula = formula
	aura.distance_scale = scale
	aura.discard = discard
	return aura


## Pins `constitution` to an exact value via a SET modifier — bypasses the
## default board's own level-derived CON intrinsic so a test can dial CON
## without also faking level (a derived-value override wants SET, per
## `.claude/rules/stat-knobs-and-bins.md`). Later calls win ties by
## insertion order (same [StatModifier] priority), so calling this twice
## simulates "CON rose between turns."
func _set_con(value: float) -> void:
	var mod := StatModifier.new()
	mod.stat_id = &"constitution"
	mod.operation = StatModifier.Operation.SET
	mod.value = value
	_entity.stat_board.add_modifier(mod)


## +[param delta] max node HP via an entity-board modifier — headroom so a
## heal can land in full without clipping against the cap, and pre-damage can
## be read back as an exact "gate suppressed the base term" delta.
func _bump_node_health_cap(delta: float) -> void:
	var mod := StatModifier.new()
	mod.stat_id = &"node_health"
	mod.operation = StatModifier.Operation.ADD_BASE
	mod.value = delta
	_entity.stat_board.node_health.add_modifier(mod)


func test_aura_falloff_by_hop() -> void:
	var core := _make_node("Core")
	_alloc.force_allocate(_entity, core)
	_entity.core_location = core
	var chain := _chain(core, 3, _entity, _alloc)  # hop1, hop2, hop3
	_bump_node_health_cap(90.0)
	var aura := _heal_aura(10.0, 3, "v * (1 - d / max)")
	_entity.grant_effect(aura)

	for n in chain:
		_true_damage(n, 50.0)
	_entity._on_turn_started(_entity)

	# LinearScale-equivalent formula: base * (1 - d/max) = 10, 6.667, 3.333, 0
	# for base 10 / max_hops 3 — floored once, here, per ADR 0017 (health is
	# an INT quantity end to end), and the rim (hop == max_hops) computes
	# exactly 0 and heals nothing.
	assert_almost_eq(_hp_pool(core).current, 60.0, 0.001, "core's own node heals base (hop 0)")
	assert_almost_eq(_hp_pool(chain[1]).current, 56.0, 0.001, "hop 1: 6.667 floors to 6")
	assert_almost_eq(_hp_pool(chain[2]).current, 53.0, 0.001, "hop 2: 3.333 floors to 3")
	assert_almost_eq(_hp_pool(chain[3]).current, 50.0, 0.001, "hop 3 (== max_hops) computes 0, heals nothing")


func test_aura_base_and_range_independent() -> void:
	var core := _make_node("Core")
	_alloc.force_allocate(_entity, core)
	_entity.core_location = core
	# max_hops 2 (not 3): every d/max below divides evenly, so flooring
	# (ADR 0017) can't break the "doubling base doubles the heal" relationship
	# the way it would at a hop whose raw value isn't already integral.
	var chain := _chain(core, 2, _entity, _alloc)
	_bump_node_health_cap(290.0)  # headroom across two turns' worth of damage+heal

	var aura := _heal_aura(10.0, 2, "v * (1 - d / max)")
	_entity.grant_effect(aura)

	var nodes: Array[SkillNode] = [core, chain[1], chain[2]]
	for n in nodes:
		_true_damage(n, 50.0)
	var before_weak: Dictionary[SkillNode, float] = {}
	for n in nodes:
		before_weak[n] = _hp_pool(n).current
	_entity._on_turn_started(_entity)
	var weak_core_heal: float = _hp_pool(core).current - before_weak[core]
	var weak_hop1_heal: float = _hp_pool(chain[1]).current - before_weak[chain[1]]

	# Raising base alone must not change coverage — same `reach`, only the
	# magnitude scales. Re-damage every node so the D-9 gate isolates turn 2's
	# heal the same way it isolated turn 1's.
	aura.base = 20.0
	for n in nodes:
		_true_damage(n, 50.0)
	var before_strong: Dictionary[SkillNode, float] = {}
	for n in nodes:
		before_strong[n] = _hp_pool(n).current
	_entity._on_turn_started(_entity)
	var strong_core_heal: float = _hp_pool(core).current - before_strong[core]
	var strong_hop1_heal: float = _hp_pool(chain[1]).current - before_strong[chain[1]]
	var strong_hop2_heal: float = _hp_pool(chain[2]).current - before_strong[chain[2]]

	assert_almost_eq(strong_core_heal, weak_core_heal * 2.0, 0.001,
			"doubling base doubles the healed amount at hop 0")
	assert_almost_eq(strong_hop1_heal, weak_hop1_heal * 2.0, 0.001,
			"doubling base doubles the healed amount at hop 1")
	assert_almost_eq(strong_hop2_heal, 0.0, 0.001,
			"coverage unchanged: the rim (hop == max_hops) still computes 0")


func test_aura_hop_distance_uses_owned_subgraph() -> void:
	var core := _make_node("Core")
	_alloc.force_allocate(_entity, core)
	_entity.core_location = core
	# Owned route: core -> a1 -> a2 -> a3 -> target (4 hops, all owned).
	var chain := _chain(core, 3, _entity, _alloc)
	var a3 := chain[3]
	var target := _make_node("Target")
	_graph.add_edge(a3, target)
	_alloc.force_allocate(_entity, target)
	# Enemy shortcut: core -> enemy -> target (2 hops), but `enemy` is unowned
	# so it never enters entity.navigator — the owned-subgraph BFS must not
	# see this path.
	var enemy := _make_node("Enemy")
	_graph.add_edge(core, enemy)
	_graph.add_edge(enemy, target)

	_bump_node_health_cap(90.0)
	# max_hops 3 would reach a global-shortcut 2-hop target, not a 4-hop one.
	var aura := _heal_aura(10.0, 3, "v * (1 - d / max)")
	_entity.grant_effect(aura)

	for n in [core, chain[1], target]:
		_true_damage(n, 50.0)
	_entity._on_turn_started(_entity)

	assert_almost_eq(_hp_pool(target).current, 50.0, 0.001,
			"target is 4 owned-hops away (out of range); a global shortcut through unowned territory must not shrink that — no heal lands")
	assert_almost_eq(_hp_pool(chain[1]).current, 56.0, 0.001, "sanity: owned hop-1 node still measured correctly")


func test_aura_heals_through_damage_gate_and_grants_no_ramp() -> void:
	var core := _make_node("Core")
	# Give this node lots of headroom so the aura heal can't clip against max
	# and distort the "exactly the aura's value" assertion.
	_bump_node_health_cap(90.0)

	_alloc.force_allocate(_entity, core)
	_entity.core_location = core
	var hp := _hp_pool(core)
	assert_almost_eq(hp.value, 100.0, 0.001, "sanity: max bumped to 100")

	var aura := _heal_aura(10.0, 3, "v * (1 - d / max)")
	_entity.grant_effect(aura)

	# Damage well below max so the aura's heal has headroom to land in full —
	# healing 10 after only 5 damage would clip against the cap regardless of
	# max's absolute size, which would muddy "exactly the aura's value".
	_true_damage(core, 50.0)
	assert_almost_eq(hp.current, 50.0, 0.001)

	_entity._on_turn_started(_entity)

	# Base term is gated to 0 (damaged this turn); only the aura's hop-0 value
	# (10.0) lands, and it heals through the gate rather than being suppressed.
	assert_almost_eq(hp.current, 60.0, 0.001,
			"aura heals through combat: gate suppresses the base term only")
	assert_eq(core.regen_stacks, 0, "aura healing must not grant ramp")


## New coverage (#720 acceptance 2): the Balanced formula's exact ladder, and
## proof the reach bound is the walk bound — a node one hop past `max_hops`
## is never visited at all, not merely healed for 0.
func test_aura_exact_ladder_5_minus_d_over_four_hops() -> void:
	var core := _make_node("Core")
	_alloc.force_allocate(_entity, core)
	_entity.core_location = core
	var chain := _chain(core, 5, _entity, _alloc)  # hop1..hop5
	_bump_node_health_cap(40.0)

	var aura := _heal_aura(5.0, 4, "5 - d")
	_entity.grant_effect(aura)

	for n in chain:
		_true_damage(n, 20.0)
	_entity._on_turn_started(_entity)

	# Cap is 10 (default) + 40 = 50; damage 20 leaves 30 headroom before heal.
	assert_almost_eq(_hp_pool(core).current, 35.0, 0.001, "hop 0 heals 5")
	assert_almost_eq(_hp_pool(chain[1]).current, 34.0, 0.001, "hop 1 heals 4")
	assert_almost_eq(_hp_pool(chain[2]).current, 33.0, 0.001, "hop 2 heals 3")
	assert_almost_eq(_hp_pool(chain[3]).current, 32.0, 0.001, "hop 3 heals 2")
	assert_almost_eq(_hp_pool(chain[4]).current, 31.0, 0.001, "hop 4 heals 1")
	assert_almost_eq(_hp_pool(chain[5]).current, 30.0, 0.001,
			"hop 5 is past max_hops 4 — never visited by the walk, no heal")


## New coverage (#720 acceptance 2): a formula that goes negative past its own
## zero ring, under `discard NONE` (nothing excluded from the walk) — the
## clamp in `HealAuraEffect._on_turn_start`, not `discard`, is what keeps a
## negative result from ever landing as damage.
func test_aura_clamps_negative_result_to_zero_regardless_of_discard() -> void:
	var core := _make_node("Core")
	_alloc.force_allocate(_entity, core)
	_entity.core_location = core
	var chain := _chain(core, 4, _entity, _alloc)  # hop1..hop4
	_bump_node_health_cap(40.0)

	var aura := _heal_aura(3.0, 4, "3 - d", AuraEffect.Discard.NONE)
	_entity.grant_effect(aura)

	for n in chain:
		_true_damage(n, 20.0)
	var before_hop3 := _hp_pool(chain[3]).current
	var before_hop4 := _hp_pool(chain[4]).current
	_entity._on_turn_started(_entity)

	assert_almost_eq(_hp_pool(chain[3]).current, before_hop3, 0.001,
			"hop 3: '3 - d' computes exactly 0, heals nothing")
	assert_almost_eq(_hp_pool(chain[4]).current, before_hop4, 0.001,
			"hop 4: '3 - d' computes -1 under discard NONE — clamped to 0, never damages")


## New coverage (#720 acceptance 3): an allocation/deallocation inside reach,
## between turns, must not throw and must not double-heal — HealAuraEffect's
## `_grant_to` is a no-op, so the inherited #626 incremental topology paths
## (and the full-rebuild fallback they take when `metric` is null) do nothing
## for this channel regardless of which one runs.
func test_alloc_dealloc_inside_reach_is_a_no_op_for_the_heal_channel() -> void:
	var core := _make_node("Core")
	_alloc.force_allocate(_entity, core)
	_entity.core_location = core
	var chain := _chain(core, 2, _entity, _alloc)  # hop1, hop2
	_bump_node_health_cap(40.0)

	var aura := _heal_aura(5.0, 4, "5 - d")
	_entity.grant_effect(aura)

	var extra := _make_node("Extra")
	_graph.add_edge(chain[2], extra)
	_alloc.force_allocate(_entity, extra)
	_alloc.force_deallocate(extra)

	for n in chain:
		_true_damage(n, 20.0)
	_entity._on_turn_started(_entity)

	# Cap is 10 (default) + 40 = 50; damage 20 leaves 30 headroom before heal.
	assert_almost_eq(_hp_pool(core).current, 35.0, 0.001,
			"heal still lands normally after the no-op topology churn")


# ── D-10: sub-linear CON scaling (#896) ───────────────────────────────────
#
# `con_coefficient` widens the value handed to `distance_scale.scale` from
# `base` alone to `base + con_coefficient * sqrt(CON)`, CON read live off
# `ctx.entity.stat_board` every `_on_turn_start`. Hand-built effects only —
# never pin `balanced_core.tres`'s authored coefficient in a test.

## Acceptance 1: base 0, con_coefficient 2, max_hops 2, CON 16 — the same
## numbers the issue specifies. `v = 0 + 2*sqrt(16) = 8`; `LinearScale`'s
## `v * (1 - d/max)` reads `v` as a straight multiplier: floor(8*1) = 8 at
## hop 0, floor(8*0.5) = 4 at hop 1.
func test_con_scaling_hand_built_effect_matches_acceptance_numbers() -> void:
	var core := _make_node("Core")
	_alloc.force_allocate(_entity, core)
	_entity.core_location = core
	var chain := _chain(core, 2, _entity, _alloc)  # hop1, hop2
	_bump_node_health_cap(40.0)
	_set_con(16.0)

	var aura := _heal_aura(0.0, 2, "v * (1 - d / max)", AuraEffect.Discard.NON_POSITIVE, 2.0)
	_entity.grant_effect(aura)

	for n in [core, chain[1], chain[2]]:
		_true_damage(n, 20.0)
	# Snapshot AFTER damage (and after the D-31 cap-ratchet `_set_con` above
	# already applied) so the delta below isolates exactly this turn's heal —
	# raising CON also raises `node_health`'s cap (and ratchets current with
	# it, `mod_con_to_node_health`), which is a real but separate effect from
	# this test's subject.
	var before_core := _hp_pool(core).current
	var before_hop1 := _hp_pool(chain[1]).current
	_entity._on_turn_started(_entity)

	assert_almost_eq(_hp_pool(core).current - before_core, 8.0, 0.001,
			"hop 0: floor(2*sqrt(16)*1) = 8 healed")
	assert_almost_eq(_hp_pool(chain[1]).current - before_hop1, 4.0, 0.001,
			"hop 1: floor(2*sqrt(16)*0.5) = 4 healed")


## Acceptance 2: raising CON via a board modifier between two turns raises
## the NEXT turn's heal — proves the read is live off the board every
## `_on_turn_start`, never cached on the resource at grant time.
func test_con_scaling_reads_board_live_between_turns() -> void:
	var core := _make_node("Core")
	_alloc.force_allocate(_entity, core)
	_entity.core_location = core
	_bump_node_health_cap(200.0)
	_set_con(4.0)  # sqrt(4) = 2 -> v = 3*2 = 6

	var aura := _heal_aura(0.0, 1, "v", AuraEffect.Discard.NON_POSITIVE, 3.0)
	_entity.grant_effect(aura)

	_true_damage(core, 50.0)
	var before_first := _hp_pool(core).current
	_entity._on_turn_started(_entity)
	assert_almost_eq(_hp_pool(core).current - before_first, 6.0, 0.001,
			"CON 4: floor(3*sqrt(4)) = 6 healed")

	_set_con(16.0)  # sqrt(16) = 4 -> v = 3*4 = 12; SET ties break last-in
	_true_damage(core, 50.0)
	var before_second := _hp_pool(core).current
	_entity._on_turn_started(_entity)
	var healed_second: float = _hp_pool(core).current - before_second

	assert_almost_eq(healed_second, 12.0, 0.001,
			"raising CON between turns raises next turn's heal — the read is live, not cached")


## Acceptance 3: reach/coverage at CON 16 and CON 400 is identical — a node
## just past `max_hops` stays unhealed at either CON, because only the
## magnitude scales with CON; `max_hops` (the reach bound) never does.
func test_con_scaling_never_moves_max_hops_reach() -> void:
	var core := _make_node("Core")
	_alloc.force_allocate(_entity, core)
	_entity.core_location = core
	var chain := _chain(core, 3, _entity, _alloc)  # hop1..hop3
	_bump_node_health_cap(400.0)

	var aura := _heal_aura(0.0, 2, "v * (1 - d / max)", AuraEffect.Discard.NON_POSITIVE, 5.0)
	_entity.grant_effect(aura)
	var far := chain[3]  # hop 3, one past max_hops 2 either way

	_set_con(16.0)
	_true_damage(far, 100.0)
	var before_low_con := _hp_pool(far).current
	_entity._on_turn_started(_entity)
	assert_almost_eq(_hp_pool(far).current, before_low_con, 0.001,
			"hop 3 (beyond max_hops 2) untouched at CON 16")

	_set_con(400.0)
	_true_damage(far, 100.0)
	var before_high_con := _hp_pool(far).current
	_entity._on_turn_started(_entity)
	assert_almost_eq(_hp_pool(far).current, before_high_con, 0.001,
			"hop 3 stays untouched at CON 400 too — max_hops never scales with CON")


## Acceptance 4: `con_coefficient 0` reproduces #720's `base`-only numbers —
## covered by every pre-existing `_heal_aura(...)` call above with no fifth
## argument, since the helper now defaults `con_coefficient` to 0.0 and those
## tests pass unmodified.

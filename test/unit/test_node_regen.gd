extends GutTest

## D-9 gated/ramping node regen + D-10 CoreClass healing aura (#270).
##
## Fixtures follow .claude/rules/scene-composition.md (instantiate scenes,
## don't hand-compose) and .claude/rules/graph.md (populate a Graph via
## add_skill_node / add_edge so Navigator/EntityNavigator actually mirror it).

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
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
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# Keep the turn upkeep from levelling up mid-test. WIS 10 gives
	# xp_per_turn = floor(10/2) = 5 against an xp cap of exactly 5, so the very
	# first _on_turn_started() levels the entity, which grants +1 CON, which
	# raises node_health by 1 — and since D-31 that cap rise correctly ratchets
	# +1 into every owned node's current HP. Harmless in play, but it lands on
	# top of the regen/aura numbers these tests assert exactly. Nothing here
	# tests levelling, so take the variable off the table.
	_entity.stat_board.xp.base_value = 100000.0
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


# ── D-10: CoreClass healing aura ─────────────────────────────────────────

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


func test_aura_falloff_by_hop() -> void:
	var core := _make_node("Core")
	_alloc.force_allocate(_entity, core)
	_entity.core_location = core
	var chain := _chain(core, 3, _entity, _alloc)  # hop1, hop2, hop3
	var aura := HealAura.new()
	aura.base = 10.0
	aura.hop_range = 3.0

	var values := aura.values_from(core, _entity.navigator)
	# value_at_hop(h) = base * (1 - h/range): 10, 6.667, 3.333, 0 for base 10 / range 3.
	assert_almost_eq(values.get(core, -1.0), 10.0, 0.001, "core's own node heals base (hop 0)")
	assert_almost_eq(values.get(chain[1], -1.0), 20.0 / 3.0, 0.001, "hop 1")
	assert_almost_eq(values.get(chain[2], -1.0), 10.0 / 3.0, 0.001, "hop 2")
	assert_false(values.has(chain[3]), "hop 3 (== range) clamps to 0 and is omitted")


func test_aura_base_and_range_independent() -> void:
	var core := _make_node("Core")
	_alloc.force_allocate(_entity, core)
	_entity.core_location = core
	var chain := _chain(core, 3, _entity, _alloc)

	var weak := HealAura.new()
	weak.base = 10.0
	weak.hop_range = 3.0
	var strong := HealAura.new()
	strong.base = 20.0
	strong.hop_range = 3.0  # same range, only base doubles

	var weak_values := weak.values_from(core, _entity.navigator)
	var strong_values := strong.values_from(core, _entity.navigator)

	# Same coverage set (which nodes are touched) ...
	assert_eq(weak_values.keys().size(), strong_values.keys().size(),
			"raising base alone must not change how many nodes are covered")
	for node in weak_values:
		assert_true(strong_values.has(node), "coverage set must be identical")
	# ... but the healed amounts scale with base.
	assert_almost_eq(strong_values[core], 20.0, 0.001)
	assert_almost_eq(strong_values[chain[1]], 40.0 / 3.0, 0.001)
	assert_almost_eq(strong_values[chain[1]], weak_values[chain[1]] * 2.0, 0.001,
			"doubling base doubles the healed amount at a given hop")


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

	var aura := HealAura.new()
	aura.base = 10.0
	aura.hop_range = 3.0  # would reach a global-shortcut 2-hop target, not a 4-hop one

	var values := aura.values_from(core, _entity.navigator)
	assert_false(values.has(target),
			"target is 4 owned-hops away (out of range); a global shortcut through unowned territory must not shrink that")
	assert_almost_eq(values.get(chain[1], -1.0), 20.0 / 3.0, 0.001, "sanity: owned hop-1 node still measured correctly")


func test_aura_heals_through_damage_gate_and_grants_no_ramp() -> void:
	var core := _make_node("Core")
	# Give this node lots of headroom so the aura heal can't clip against max
	# and distort the "exactly the aura's value" assertion.
	var big_max := StatModifier.new()
	big_max.stat_id = &"node_health"
	big_max.operation = StatModifier.Operation.ADD_BASE
	big_max.value = 90.0
	_entity.stat_board.node_health.add_modifier(big_max)

	_alloc.force_allocate(_entity, core)
	_entity.core_location = core
	var hp := _hp_pool(core)
	assert_almost_eq(hp.value, 100.0, 0.001, "sanity: max bumped to 100")

	var cc := CoreClass.new()
	var aura := HealAura.new()
	aura.base = 10.0
	aura.hop_range = 3.0
	cc.aura = aura
	_entity.core_class = cc

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

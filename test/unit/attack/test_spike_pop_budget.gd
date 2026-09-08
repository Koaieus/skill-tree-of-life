extends GutTest

## #778 acceptance: the spikes pop budget contact rule, sparse turn-start
## regen, and the ownership-change reset. These fixtures pin a FIXED cap /
## regen via a test-authored SET modifier (same technique
## test_blade_pop_resolver.gd / test_spike_pop.gd use for blade_damage) —
## the addon's own stake-scaled grant is an owner-tunable curve, covered
## separately (ordering only) by test_spike_grant.gd.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


func _spawn_node(graph: Node, nm: String) -> SkillNode:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = nm
	graph.skill_nodes_container.add_child(node)
	return node


func _make_entity(graph: Node) -> Entity:
	var board: EntityStatBoard = _BOARD.duplicate(true)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	entity.turns_taken = 1  # past the first-turn upkeep skip
	graph.add_child(entity)
	return entity


## Mints/overrides `node`'s node-local `spikes` cap at exactly `cap` via a SET
## modifier, bypassing SpikeRingAddon's stake-scaled formula so these tests
## pin the SHAPE of the contact rule against a number the fixture controls.
func _set_spikes_cap(node: SkillNode, cap: float) -> void:
	var mod := StatModifier.new()
	mod.stat_id = &"spikes"
	mod.operation = StatModifier.Operation.SET
	mod.value = cap
	node.add_local_modifier(mod)


func _set_regen(node: SkillNode, amount: float) -> void:
	var mod := StatModifier.new()
	mod.stat_id = &"spike_regen"
	mod.operation = StatModifier.Operation.SET
	mod.value = amount
	node.add_local_modifier(mod)


func _spikes_pool(node: SkillNode) -> PoolStat:
	return node.get_combat().board().get_stat(&"spikes") as PoolStat


func _ev(t: float, particle_idx: int, target: SkillNode) -> BladeHitEvent:
	return BladeHitEvent.new(t, particle_idx, -1, target)


## A star: pivot(0) with three independent spokes (1, 2, 3) — popping one
## spoke must not disconnect the others (unlike a chain, where it would).
func _star_state() -> BladeState:
	var positions: Array[Vector2] = [
			Vector2.ZERO, Vector2(50, 0), Vector2(0, 50), Vector2(-50, 0)]
	var radii: Array[float] = [16.0, 16.0, 16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
	return BladeState.build(positions, 0, edges, radii)


## Two independent spines off the pivot: 0-1-2 and 0-3-4. Popping 1 must
## disconnect only 2 (its own downstream) — 3/4 keep swinging untouched.
func _two_spine_state() -> BladeState:
	var positions: Array[Vector2] = [
			Vector2.ZERO, Vector2(50, 0), Vector2(100, 0),
			Vector2(0, 50), Vector2(0, 100)]
	var radii: Array[float] = [16.0, 16.0, 16.0, 16.0, 16.0]
	var edges: Array[Vector2i] = [
			Vector2i(0, 1), Vector2i(1, 2), Vector2i(0, 3), Vector2i(3, 4)]
	return BladeState.build(positions, 0, edges, radii)


func _setup(cap: float) -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var attacker := _make_entity(graph)
	var defender := _make_entity(graph)
	var spiked := _spawn_node(graph, "Spiked")
	await get_tree().process_frame
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(defender, spiked)
	_set_spikes_cap(spiked, cap)
	return {"graph": graph, "alloc": alloc, "attacker": attacker, "defender": defender, "spiked": spiked}


## Acceptance 1: a cap-2 node pops two plain vertices, then admits the third.
func test_cap_two_pops_two_plain_vertices_then_admits_third() -> void:
	var ctx: Dictionary = await _setup(2.0)
	var spiked: SkillNode = ctx.spiked
	var gate := BladePopResolver.LiveGate.new(_star_state(), ctx.attacker)
	assert_false(gate.admit(_ev(0.1, 1, spiked), CombatWorld.live()), "first contact pops")
	assert_false(gate.admit(_ev(0.2, 2, spiked), CombatWorld.live()), "second contact pops")
	assert_true(gate.admit(_ev(0.3, 3, spiked), CombatWorld.live()),
			"budget spent -- the third contact deals damage instead")
	assert_eq(gate.result.pops.size(), 2, "exactly two killing contacts")


## Acceptance 2: a blunting-2 vertex against 1 remaining spike drains the
## remainder and passes through -- no pop.
func test_partial_remainder_drains_without_popping() -> void:
	var ctx: Dictionary = await _setup(1.0)
	var spiked: SkillNode = ctx.spiked
	var gate := BladePopResolver.LiveGate.new(_star_state(), ctx.attacker, {1: 2.0})
	assert_true(gate.admit(_ev(0.1, 1, spiked), CombatWorld.live()),
			"remainder < blunting: drains through, no pop, damage lands")
	assert_eq(_spikes_pool(spiked).current, 0.0, "remaining spikes drained to exactly 0")
	assert_eq(gate.result.pops.size(), 0, "no killing contact recorded")


## Acceptance 3: the pool does NOT refill between two swings in the same turn.
func test_pool_does_not_refill_between_two_swings_same_turn() -> void:
	var ctx: Dictionary = await _setup(1.0)
	var spiked: SkillNode = ctx.spiked
	var gate1 := BladePopResolver.LiveGate.new(_star_state(), ctx.attacker)
	assert_false(gate1.admit(_ev(0.1, 1, spiked), CombatWorld.live()), "first swing pops")
	var gate2 := BladePopResolver.LiveGate.new(_star_state(), ctx.attacker)
	assert_true(gate2.admit(_ev(0.1, 1, spiked), CombatWorld.live()),
			"second swing, same turn: the pool stayed at 0, so this contact lands")


## Acceptance 3 (regen half) + 4: a turn start regenerates exactly the spent
## set by spike_regen, capped at the cap; an owner who never takes a turn
## never regenerates.
func test_turn_start_regenerates_spent_set_but_a_dormant_owner_never_does() -> void:
	var ctx: Dictionary = await _setup(2.0)
	var spiked: SkillNode = ctx.spiked
	var defender: Entity = ctx.defender
	_set_regen(spiked, 1.0)
	var gate := BladePopResolver.LiveGate.new(_star_state(), ctx.attacker)
	gate.admit(_ev(0.1, 1, spiked), CombatWorld.live())
	assert_eq(_spikes_pool(spiked).current, 1.0, "one pop off a cap-2 pool leaves 1")
	# The owner never takes a turn (a "blocker") -- no regen, ever.
	assert_eq(_spikes_pool(spiked).current, 1.0, "no turn served yet, still 1")
	# Now the owner DOES take a turn.
	defender._on_turn_started(defender)
	assert_eq(_spikes_pool(spiked).current, 2.0, "regen 1 tops remaining 1 back to the cap")
	# The spent set was cleared -- a second turn with no new spend is a no-op.
	defender._on_turn_started(defender)
	assert_eq(_spikes_pool(spiked).current, 2.0, "still capped -- nothing left in the spent set")


## Acceptance 5: a two-spine truss sweeping past a single cap-1 node loses
## one vertex on the popped spine and keeps swinging -- the OTHER spine
## survives untouched, nothing on it disintegrates.
func test_two_spine_truss_loses_one_vertex_and_keeps_swinging() -> void:
	var ctx: Dictionary = await _setup(1.0)
	var spiked: SkillNode = ctx.spiked
	var gate := BladePopResolver.LiveGate.new(_two_spine_state(), ctx.attacker)
	assert_false(gate.admit(_ev(0.1, 1, spiked), CombatWorld.live()), "vertex 1 pops")
	assert_eq(_sorted_keys(gate.result.dead_at), [1, 2],
			"only spine A (1, its downstream 2) is lost -- spine B stands untouched")


func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys


## Acceptance 8: deallocating and reallocating a spent node restores its
## budget.
func test_realloc_restores_spent_budget() -> void:
	var ctx: Dictionary = await _setup(2.0)
	var spiked: SkillNode = ctx.spiked
	var defender: Entity = ctx.defender
	var alloc: AllocationSystem = ctx.alloc
	var gate := BladePopResolver.LiveGate.new(_star_state(), ctx.attacker)
	gate.admit(_ev(0.1, 1, spiked), CombatWorld.live())
	assert_eq(_spikes_pool(spiked).current, 1.0, "spent down to 1 of 2")
	alloc.force_deallocate(spiked)
	alloc.force_allocate(defender, spiked)
	assert_eq(_spikes_pool(spiked).current, 2.0, "realloc must restore the full budget")


# ── End-to-end: blunting reaches admit() through a real build_blade_state ────

const _SPIKE_SCENE := preload("res://skill_node/addons/spike_ring_addon.tscn")


## Builds the ATTACKER's blade through the production path: pivot `source`
## plus one spiked `member`, whose SpikeRingAddon raises its own `blunting`
## from the def default 1 to 2. Returns the built BladeState — selection order
## is [source, member], so the spiked vertex is particle 1.
func _spiked_blade_state(ctx: Dictionary) -> BladeState:
	var graph: Node = ctx.graph
	var alloc: AllocationSystem = ctx.alloc
	var attacker: Entity = ctx.attacker
	var source := _spawn_node(graph, "Pivot")
	var member := _spawn_node(graph, "SpikedVertex")
	await get_tree().process_frame
	alloc.force_allocate(attacker, source)
	alloc.force_allocate(attacker, member)
	member.add_child(_SPIKE_SCENE.instantiate() as SpikeRingAddon)
	await get_tree().process_frame

	var plan := MeleeAttackPlan.new()
	plan.attacker = attacker
	plan.source = source
	var members: Array[SkillNode] = [member]
	plan.blade_nodes = members
	return plan.build_blade_state()


## Acceptance 2, end to end (#778's closing gap): a spiked ATTACKING vertex
## carries blunting 2 out of the real blade build, so against a defender
## holding 1 remaining spike it drains the remainder and passes THROUGH
## without popping. Nothing here supplies the override dict — if the
## production fill were missing, the vertex would read blunting 1, pop, and
## this test would fail.
func test_spiked_vertex_blunting_reaches_admit_through_production_build() -> void:
	var ctx: Dictionary = await _setup(1.0)
	var spiked: SkillNode = ctx.spiked
	var state: BladeState = await _spiked_blade_state(ctx)
	assert_not_null(state, "the plan must build a state")
	assert_almost_eq(state.vertex_blunting[0], 1.0, 0.001,
			"plain pivot vertex carries the blunting def default")
	assert_almost_eq(state.vertex_blunting[1], 2.0, 0.001,
			"SpikeRingAddon raises the spiked vertex to blunting 2")

	var gate := BladePopResolver.LiveGate.new(state, ctx.attacker)
	assert_true(gate.admit(_ev(0.1, 1, spiked), CombatWorld.live()),
			"blunting 2 vs 1 remaining: drains through, no pop -- damage lands")
	assert_eq(_spikes_pool(spiked).current, 0.0, "the remainder drained to exactly 0")
	assert_eq(gate.result.pops.size(), 0, "no killing contact recorded")


## The same production-filled state, but the defender holds enough: blunting 2
## against a cap-2 pool DOES pop, and spends the full 2 (a plain vertex would
## only have spent 1 and left the node half-loaded).
func test_spiked_vertex_pops_and_spends_its_full_blunting() -> void:
	var ctx: Dictionary = await _setup(2.0)
	var spiked: SkillNode = ctx.spiked
	var state: BladeState = await _spiked_blade_state(ctx)

	var gate := BladePopResolver.LiveGate.new(state, ctx.attacker)
	assert_false(gate.admit(_ev(0.1, 1, spiked), CombatWorld.live()),
			"blunting 2 vs 2 remaining: the full amount is removed, so it pops")
	assert_eq(_spikes_pool(spiked).current, 0.0, "a blunting-2 pop spends 2, not 1")
	assert_eq(gate.result.pops.size(), 1, "exactly one killing contact")
	assert_almost_eq(gate.result.pops[0].blunting_spent, 2.0, 0.001,
			"the Pop records the full blunting it spent")

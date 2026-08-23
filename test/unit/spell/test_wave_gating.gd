extends GutTest

## #536 (closing #498 step 3, and the gap `spell_resolver.gd` had documented as
## open since #501): a spell must not propagate back into a node THIS SAME CAST
## already killed.
##
## Candidate selection is where magic gates — [OwnerFilter] asks
## `ownership_bit`, and a dead node is nobody's. Resolution used to read
## pre-attack ownership for every wave uniformly, so a cast that killed its seed
## on wave 0 happily bounced back onto the corpse on wave 2. The fix is that
## resolution LANDS each wave in the world it is resolving against (a shadow —
## never the real one) before the next wave's filter runs.
##
## The fixture is one graph and one spell, cast twice; the ONLY difference
## between the two cases is whether wave 0's damage is lethal. That is what
## makes this a test of the gate rather than of the topology — the pre-attack
## world would have allowed the bounce in both.
##
## These build their own fixture rather than using [SpellTestHelper]: the gate
## needs a defender whose owned subgraph a shadow can actually snapshot, which
## means real [method AllocationSystem.force_allocate] ownership (the helper's
## `assign_owner` writes `owned_by` directly and never mirrors), and a
## `core_location` so a cascade has an anchor to island against.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## Node HP comes from the `node_health` scaffold, which defaults to 10. One
## point over it, so wave 0 is lethal by the smallest margin that proves the
## point — and so the core node it also hits barely overflows.
const _LETHAL_POWER := 11.0


func _make_entity(graph: Graph, nm: String) -> Entity:
	var ent := Entity.new()
	ent.display_name = nm
	# Its own one-member camp, or both entities inherit `npc.tres` and read as
	# ALLIED — `owner_enemy()` would then admit nothing at all.
	var camp := Faction.new()
	camp.id = StringName("wave_gating_%s_%d" % [nm, ent.get_instance_id()])
	ent.faction = camp
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	ent.stat_board.get_stat(&"crit_chance").base_value = 0.0
	graph.add_child(ent)
	return ent


## Line 0—1—2. The attacker holds 0 and casts from it; the defender holds 1 and
## 2, with its core on 2 so that 1 is an ordinary node a cascade can strip.
func _setup(lethal: bool) -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate() as Graph
	add_child_autofree(graph)
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		graph.skill_nodes_container.add_child(sn)
	var nodes := graph.get_skill_nodes()
	for pair in [[0, 1], [1, 2]]:
		var e := _EDGE_SCENE.instantiate() as Edge
		e.from = nodes[int(pair[0])]
		e.to = nodes[int(pair[1])]
		graph.edges_container.add_child(e)

	var attacker := _make_entity(graph, "Attacker")
	var defender := _make_entity(graph, "Defender")
	if not lethal:
		# The control: same cast, same filter, nothing dies.
		defender.stat_board.get_stat(&"node_health").base_value = 9999.0
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(attacker, nodes[0])
	attacker.core_location = nodes[0]
	alloc.force_allocate(defender, nodes[1])
	alloc.force_allocate(defender, nodes[2])
	defender.core_location = nodes[2]

	# fan_all + owner_enemy, two hops deep, and a node may be visited twice —
	# which is exactly what lets wave 2 come back to the seed.
	var config := PropagationConfig.new()
	config.step = FanAllStep.new()
	var f := OwnerFilter.new()
	f.ownership_filter = SkillNode.Ownership.HOSTILE
	config.filter = f
	config.max_hops = 2
	config.max_visits_per_node = 2
	var spell := SpellDef.new()
	spell.propagation = config
	spell.on_hit_effects = [DamageEffect.new()]
	spell.power = _LETHAL_POWER

	return {"graph": graph, "attacker": attacker, "nodes": nodes, "spell": spell}


func _hits_on(outcome: AttackOutcome, node: SkillNode) -> int:
	var n := 0
	for hit in outcome.hits:
		if hit.target == node:
			n += 1
	return n


## The control, and the reason the headline below is about the GATE: with
## nothing dying, the walk does come back — seed on wave 0, the neighbour on
## wave 1, the seed again on wave 2.
func test_a_surviving_seed_is_revisited_on_a_later_wave() -> void:
	var ctx: Dictionary = await _setup(false)
	var nodes: Array[SkillNode] = ctx.nodes
	var outcome := SpellResolver.resolve(
			ctx.spell, nodes[1], nodes[0], ctx.attacker, ctx.graph)

	assert_eq(_hits_on(outcome, nodes[1]), 2,
			"wave 0 seeds the node and wave 2 comes back to it")
	assert_eq(_hits_on(outcome, nodes[2]), 1, "wave 1 hits the neighbour once")


## THE headline (#536). Identical cast, identical filter, identical topology —
## the seed just dies on wave 0 this time, and the wave-2 candidate that the
## control proves is otherwise admitted must now be refused.
func test_a_wave_does_not_propagate_back_into_a_node_this_cast_killed() -> void:
	var ctx: Dictionary = await _setup(true)
	var nodes: Array[SkillNode] = ctx.nodes
	var outcome := SpellResolver.resolve(
			ctx.spell, nodes[1], nodes[0], ctx.attacker, ctx.graph)

	assert_eq(_hits_on(outcome, nodes[1]), 1,
			"the seed is hit once and never again — it was dead by wave 2")
	assert_eq(_hits_on(outcome, nodes[2]), 1,
			"the rest of the walk is unaffected: wave 1 still lands")


## The other half of "shadow always": the cast above killed a node, and the REAL
## world must not have noticed. Resolution is where an attack is decided, not
## where it happens — [OutcomeApplier] against [method CombatWorld.live] is the
## only thing that mutates, and only [BattleSystem] drives it.
func test_the_lethal_resolve_leaves_the_real_world_untouched() -> void:
	var ctx: Dictionary = await _setup(true)
	var nodes: Array[SkillNode] = ctx.nodes
	var before := WorldFingerprint.compute(ctx.graph)
	var hp_before: float = nodes[1].get_current_hp()
	assert_gt(hp_before, 0.0, "precondition: the seed starts alive")

	SpellResolver.resolve(ctx.spell, nodes[1], nodes[0], ctx.attacker, ctx.graph)

	assert_eq(WorldFingerprint.compute(ctx.graph), before,
			"a resolve mutates nothing real: %s" % WorldFingerprint.describe(ctx.graph))
	assert_almost_eq(nodes[1].get_current_hp(), hp_before, 0.001,
			"the node the shadow killed is untouched here")
	assert_not_null(nodes[1].owned_by, "and still owned")


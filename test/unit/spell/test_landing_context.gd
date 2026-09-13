extends GutTest

## Pins the shape #356 introduced (hub #849): [LandingContext] is built from
## exactly the landing the resolver has in hand at that moment,
## [code]lctx.cast.outcome[/code] is the same object the crit path and every
## [OnHitEffect] append to, and a reducer's returned payload IS the
## [code]payload[/code] its landing context carries — not a copy, not a
## re-derivation.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


## Records exactly what it returns, so the test can assert the SAME object
## shows up as `lctx.payload` downstream rather than an equal-but-different one.
class _RecordingReducer extends IncidentReducer:
	var last_returned: CastSpell = null
	func reduce(incidents: Array[CastSpell], _cast: PropagationContext) -> CastSpell:
		var merged := _merge_payload_defaults(incidents)
		merged.damage = incidents[0].damage
		last_returned = merged
		return merged


## Records every LandingContext it is handed. Also emits, so the fixture
## behaves like a normal spell rather than a silent no-op.
class _RecordingEffect extends OnHitEffect:
	var seen: Array[LandingContext] = []
	func apply(lctx: LandingContext) -> void:
		seen.append(lctx)
		if lctx.payload.current_node != null and lctx.payload.damage > 0.0:
			var hit := DamageInstance.new()
			hit.amount = lctx.payload.damage
			hit.target = lctx.payload.current_node
			lctx.cast.outcome.hits.append(hit)


func test_landing_context_carries_the_resolvers_own_landing() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.assign_owner(graph, def, [1])
	helper.assign_owner(graph, atk, [0])
	var reducer := _RecordingReducer.new()
	var effect := _RecordingEffect.new()
	var config := helper.make_config(helper.no_spread(), null, reducer, {max_hops = 0})
	var spell := helper.make_spell(config, [effect], 10.0)
	var n := graph.get_skill_nodes()

	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)

	assert_eq(effect.seen.size(), 1, "one landing, one LandingContext")
	var lctx: LandingContext = effect.seen[0]
	assert_eq(lctx.node, n[1], "lctx.node is the node the resolver actually landed on")
	assert_eq(lctx.incidents.size(), 1, "provenance: what arrived, before the merge")
	assert_same(lctx.payload, reducer.last_returned,
			"a reducer's returned payload IS the payload its landing context carries")
	assert_same(lctx.cast.outcome, outcome,
			"lctx.cast.outcome is the same object the crit path and effects append to")


func test_landing_context_convergence_carries_every_incident() -> void:
	# Diamond 0-{1,2}-3: two incidents converge at 3 in the same wave, so the
	# LandingContext built for that landing must carry both, not just the one
	# the reducer folded into its merged payload.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [0, 2], [1, 3], [2, 3]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.give_big_hp(atk)
	helper.assign_owner(graph, def, [1, 2, 3])
	helper.assign_owner(graph, atk, [0])
	var effect := _RecordingEffect.new()
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(),
			helper.sum_reducer(), {max_hops = 2})
	var spell := helper.make_spell(config, [effect], 10.0)
	var n := graph.get_skill_nodes()

	SpellResolver.resolve(spell, n[0], n[0], atk, graph)

	var lctx_3: LandingContext = null
	for lctx in effect.seen:
		if lctx.node == n[3]:
			lctx_3 = lctx
	assert_not_null(lctx_3, "node 3 landed")
	assert_eq(lctx_3.incidents.size(), 2, "both converging arcs are on the record")

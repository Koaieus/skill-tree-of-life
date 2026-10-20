extends GutTest

## The PayloadExtension framework through its stock CarriedScalar: seeded,
## minted down a walk, merged at a convergence, cut off by min_value, and
## reseeded from the landed world (after the wave landed, never before).

const _POISON := preload("res://effects/status/poison.tres")

var h: SpellTestHelper


## Records what the landed world held at each landing it was minted from.
class ProbeReseed extends ScalarReseed:
	var seen: Dictionary = {}  ## SkillNode -> float

	func reseed(value: float, lctx: LandingContext, _scalar: CarriedScalar) -> float:
		seen[lctx.node] = lctx.stacks_of(lctx.node, &"poison")
		return value


func before_each() -> void:
	h = SpellTestHelper.new()


func _scalar(id: StringName, seed_value: float, step: float = 0.0,
		fold: IncidentReducer.StackFold = IncidentReducer.StackFold.MAX) -> CarriedScalar:
	var s := CarriedScalar.new()
	s.id = id
	s.seed_value = seed_value
	s.progression = h.flat_add_progression(step)
	s.fold = fold
	return s


func _value(payload: CastSpell, id: StringName) -> float:
	var st := payload.extra(id) as CarriedScalar.State
	assert_not_null(st, "the payload carries %s" % id)
	return st.value if st != null else NAN


## Seeds a payload at the head of a line and mints it down [param hops] hops.
func _walk(config: PropagationConfig, hops: int) -> Array[CastSpell]:
	var graph := h.make_graph([[0, 1], [1, 2], [2, 3]], self)
	var n := graph.get_skill_nodes()
	var p := CastSpell.blank()
	p.seed_node = n[0]
	p.current_node = n[0]
	p.hops_remaining = 5
	p.visited = [n[0]]
	p.graph = graph
	for ext in config.extensions:
		p.extras.append(ext.seed(PropagationContext.new()))
	var out: Array[CastSpell] = [p]
	for i in hops:
		var landed := out[-1]
		var lctx := LandingContext.for_test(landed, landed.current_node)
		out.append(config.mint(landed, PropagationPick.to(n[i + 1]), lctx))
	return out


func test_a_carried_scalar_steps_down_a_walk() -> void:
	var config := h.make_config(h.fan_all(), null, null, {max_hops = 5})
	config.extensions = [_scalar(&"bites", 3.0, -1.0)]
	var walk := _walk(config, 2)
	assert_eq([_value(walk[0], &"bites"), _value(walk[1], &"bites"), _value(walk[2], &"bites")],
			[3.0, 2.0, 1.0], "seed 3, FlatAdd -1: 3, 2, 1")


func test_two_scalars_coexist_by_id() -> void:
	var config := h.make_config(h.fan_all(), null, null, {max_hops = 5})
	config.extensions = [_scalar(&"a", 3.0, -1.0), _scalar(&"b", 10.0, 5.0)]
	var walk := _walk(config, 1)
	assert_eq(_value(walk[1], &"a"), 2.0)
	assert_eq(_value(walk[1], &"b"), 15.0)
	assert_null(walk[1].extra(&"missing"), "an unknown id reads null")


func _merged(fold: IncidentReducer.StackFold) -> float:
	var ext := _scalar(&"bites", 0.0, 0.0, fold)
	var incidents: Array[CastSpell] = []
	for v in [2.0, 5.0]:
		var inc := CastSpell.blank()
		var parent := ext.seed(PropagationContext.new())
		(parent as CarriedScalar.State).value = v
		inc.extras.append(parent)
		incidents.append(inc)
	return _value(h.sum_reducer().reduce(incidents, PropagationContext.new()), &"bites")


func test_incidents_merge_by_the_scalar_fold() -> void:
	assert_eq(_merged(IncidentReducer.StackFold.MAX), 5.0, "MAX of 2 and 5")
	assert_eq(_merged(IncidentReducer.StackFold.SUM), 7.0, "SUM of 2 and 5")


func test_min_value_marks_the_hop_that_falls_below_terminal() -> void:
	var config := h.make_config(h.fan_all(), null, null, {max_hops = 5})
	var ext := _scalar(&"bites", 2.0, -1.0)
	ext.min_value = 1.0
	config.extensions = [ext]
	var walk := _walk(config, 2)
	assert_gt(walk[1].hops_remaining, 0.0, "the hop that mints 1 walks on")
	assert_eq(_value(walk[2], &"bites"), 0.0)
	assert_eq(walk[2].hops_remaining, 0.0, "the hop that mints 0 is terminal")


func test_a_reseed_reads_the_wave_that_just_landed() -> void:
	# Attacker owns 0; seed 1 → 2 → 3 are the defender's; poison lands per hop.
	var graph := h.make_graph([[0, 1], [1, 2], [2, 3]], self)
	var atk := h.make_entity(graph, "A")
	var def := h.make_entity(graph, "D")
	h.give_big_hp(atk)
	h.give_big_hp(def)
	h.assign_owner(graph, def, [1, 2, 3])
	h.assign_owner(graph, atk, [0])
	var probe := ProbeReseed.new()
	var ext := _scalar(&"probe", 0.0)
	ext.reseed = probe
	var config := h.make_config(h.fan_all(), h.owner_enemy(), null, {max_hops = 2})
	config.extensions = [ext]
	var poison := ApplyStatusEffect.new()
	poison.def = _POISON
	poison.power = 1.0
	var on_hits: Array[OnHitEffect] = [poison]
	var n := graph.get_skill_nodes()
	SpellResolver.resolve(h.make_spell(config, on_hits, 10.0), n[1], n[0], atk, graph)
	assert_true(probe.seen.has(n[1]), "the seed's landing minted through the reseed")
	assert_gt(float(probe.seen.get(n[1], 0.0)), 0.0,
			"the reseed sees the poison this wave landed on the seed")

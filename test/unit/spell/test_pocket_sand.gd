extends GutTest

## Pocket Sand (`attack/spell/defs/pocket_sand.tres`): an aimed cone from the
## cast-from node seeds every hostile node it crosses, fog or not, then the
## sand fans into hostile neighbours for `max_hops` hops. One blindness stack
## per hit; friendly and neutral nodes are never hit. Every bound is read off
## the def, never a literal.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const BLINDNESS := preload("res://effects/status/blindness.tres")

const C := 0      ## caster's cast-from node, aim east
const S1 := 1     ## hostile seed in the cone
const S2 := 2     ## hostile seed in the cone, in the caster's fog
const N := 3      ## neutral, in the cone
const PAST := 4   ## hostile, on the aim line past the reach
const WIDE := 5   ## hostile, inside the reach but outside the cone's angle
const F := 6      ## caster's own node, in the cone, neighbour of S1
const CHAIN := 7  ## first of a hostile chain hanging off S1, out of the cone

var _graph: Graph
var _n: Array[SkillNode] = []
var _blue: Entity
var _chain: Array[int] = []


func _def() -> SpellDef:
	return SpellCatalog.POCKET_SAND


func before_each() -> void:
	var def := _def()
	var targeting := def.targeting as AimedTargeting
	var reach: float = (targeting.range_finder as EuclideanRangeFinder).max_distance
	var half := deg_to_rad((targeting.shape as ConeShape).half_angle_deg)
	var hops := int(def.propagation.max_hops) if def.propagation != null else 0
	# One chain node per hop plus one more the sand must never reach.
	var chain_len := hops + 1
	var wide_angle := minf(half + deg_to_rad(30.0), PI / 2.0 - 0.05)
	var positions := {
		C: Vector2.ZERO,
		S1: Vector2(reach * 0.4, 0),
		S2: Vector2(reach * 0.8, 0),
		N: Vector2(reach * 0.6, 0),
		PAST: Vector2(reach * 2.0, 0),
		WIDE: Vector2.from_angle(wide_angle) * reach * 0.6,
		F: Vector2(reach * 0.2, 0),
	}
	var adj: Array = [[C, F], [F, S1], [S1, N], [N, S2], [S2, PAST], [N, WIDE]]
	_chain = []
	var prev := S1
	for i in chain_len:
		var idx := CHAIN + i
		_chain.append(idx)
		positions[idx] = Vector2(reach * 0.4, -reach * (1.0 + i))
		adj.append([prev, idx])
		prev = idx
	_n = []
	var h := H.new()
	_graph = h.make_graph(adj, self, positions)
	_n.assign(_graph.get_skill_nodes())
	_blue = h.make_entity(_graph, "Blue", Color.BLUE)
	var red := h.make_entity(_graph, "Red", Color.RED)
	h.give_big_hp(red)
	var red_nodes: Array = [PAST, S1, S2, WIDE]
	red_nodes.append_array(_chain)
	h.assign_owner(_graph, red, red_nodes)
	h.assign_owner(_graph, _blue, [C, F])
	# The caster sees barely past its own nodes: S2 sits in the dark.
	for idx in [C, F]:
		var m := StatModifier.new()
		m.stat_id = &"vision_range"
		m.operation = StatModifier.Operation.SET
		m.value = 1.0
		_n[idx].add_local_modifier(m)
	var vision := VisionSystem.new()
	vision.graph = _graph
	vision.viewers = [_blue]
	vision.ease_rate = 0.0
	add_child_autofree(vision)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	vision._recompute()
	assert_false(vision.is_visible(_n[S2]), "fixture: S2 sits in the caster's fog")


func _seeds() -> Array[SkillNode]:
	return (_def().targeting as AimedTargeting).seeds(_blue, _n[C], 0.0, _graph)


## Blindness hits by node, each a list of its stack powers.
func _blinded() -> Dictionary:
	var world := CombatWorld.shadow()
	var out := SpellResolver.resolve_seeds(_def(), _seeds(), _n[C], _blue, _graph, world,
			null, null, 0.0)
	world.free_shadow()
	var hit := {}
	for h in out.hits:
		if h is StatusInstance and h.def == BLINDNESS:
			if not hit.has(h.target):
				hit[h.target] = []
			hit[h.target].append(h.power)
	return hit


func test_cone_seeds_every_hostile_node_it_crosses_fog_included() -> void:
	var seeds := _seeds()
	assert_true(seeds.has(_n[S1]), "S1 is in the cone")
	assert_true(seeds.has(_n[S2]), "S2 is in the cone, fog or not")
	for idx in [C, F, N, PAST, WIDE]:
		assert_false(seeds.has(_n[idx]), "N%d is not a seed" % idx)


func test_sand_hops_into_hostile_neighbours_up_to_max_hops_and_no_further() -> void:
	var hit := _blinded()
	var hops := int(_def().propagation.max_hops)
	for i in hops:
		assert_true(hit.has(_n[_chain[i]]), "chain hop %d is reached" % (i + 1))
	assert_false(hit.has(_n[_chain[hops]]), "hop %d is one past max_hops" % (hops + 1))


func test_every_hit_carries_one_innate_blindness_stack() -> void:
	var hit := _blinded()
	var innate := float((_def().intakes[0] as AspectIntake).innate)
	assert_eq(innate, 1.0, "many small: one stack per hit")
	assert_true(hit.has(_n[S1]) and hit.has(_n[S2]), "both seeds are blinded")
	for node in hit:
		assert_eq(hit[node], [innate], "%s takes exactly one innate stack" % node.name)


func test_no_friendly_or_neutral_node_is_hit() -> void:
	var hit := _blinded()
	for idx in [C, F, N]:
		assert_false(hit.has(_n[idx]), "N%d is never hit" % idx)

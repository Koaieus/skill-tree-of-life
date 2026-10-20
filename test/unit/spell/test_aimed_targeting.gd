@tool
extends GutTest

## AimedTargeting (#1495): the line/cone shapes are pure geometry over a
## hand-placed board, the targeting filters ownership over what they cross,
## and SpellResolver.resolve_seeds starts every crossed node in wave 0.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


func _nodes(graph: Graph) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	out.assign(graph.get_skill_nodes())
	return out


func _names(nodes: Array[SkillNode]) -> Array[String]:
	var out: Array[String] = []
	for n in nodes:
		out.append(String(n.name))
	return out


## Origin N0 at (0,0) aiming east (angle 0), length 400.
##   N1 (100,0)          on the line
##   N2 (200, r+w-2)     disc just inside the band
##   N3 (250, r+w+6)     disc just outside the band
##   N4 (300,0)          on the line
##   N5 (400+r+w+10, 0)  past the end of the segment
##   N6 (-100, 0)        behind the origin
func _line_board() -> Graph:
	var helper := H.new()
	var probe := helper.make_graph([[0, 1]], self)
	var r: float = probe.get_skill_nodes()[0].radius
	var w := 24.0
	return helper.make_graph([[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6]], self, {
		0: Vector2.ZERO,
		1: Vector2(100, 0),
		2: Vector2(200, r + w - 2.0),
		3: Vector2(250, r + w + 6.0),
		4: Vector2(300, 0),
		5: Vector2(400 + r + w + 10.0, 0),
		6: Vector2(-100, 0),
	})


func test_line_crosses_the_band_sorted_and_stops_at_length() -> void:
	var graph := _line_board()
	var n := _nodes(graph)
	var line := LineShape.new()
	line.width = 24.0
	var candidates: Array[SkillNode] = n.slice(1)
	var hit := line.crossed(Vector2.ZERO, 0.0, 400.0, candidates)
	assert_eq(_names(hit), ["N1", "N2", "N4"] as Array[String])


func test_line_max_hits_keeps_the_nearest() -> void:
	var graph := _line_board()
	var n := _nodes(graph)
	var line := LineShape.new()
	line.max_hits = 2
	var candidates: Array[SkillNode] = [n[4], n[2], n[1]]
	var hit := line.crossed(Vector2.ZERO, 0.0, 400.0, candidates)
	assert_eq(_names(hit), ["N1", "N2"] as Array[String])


## Cone east, half-angle 20 deg, length 300:
##   N1 (100, 0)      dead centre
##   N2 (200, 60)     ~16.7 deg, inside
##   N3 (100, 100)    45 deg, outside even with its disc
##   N4 (250, -80)    ~17.7 deg, inside
##   N5 (500, 0)      past the length
func test_cone_crosses_within_half_angle_and_length() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 3], [3, 4], [4, 5]], self, {
		0: Vector2.ZERO,
		1: Vector2(100, 0),
		2: Vector2(200, 60),
		3: Vector2(100, 100),
		4: Vector2(250, -80),
		5: Vector2(500, 0),
	})
	var n := _nodes(graph)
	var cone := ConeShape.new()
	cone.half_angle_deg = 20.0
	var hit := cone.crossed(Vector2.ZERO, 0.0, 300.0, n.slice(1) as Array[SkillNode])
	assert_eq(_names(hit), ["N1", "N2", "N4"] as Array[String])


func _aimed(filter: int, length: float) -> AimedTargeting:
	var t := AimedTargeting.new()
	t.shape = LineShape.new()
	t.ownership_filter = filter
	t.range_finder = EuclideanRangeFinder.new()
	t.range_finder.max_distance = length
	return t


## N0 (attacker's source) aims east through N1 (mine), N2 (neutral),
## N3 and N4 (hostile).
func _ownership_board() -> Array:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 3], [3, 4]], self, {
		0: Vector2.ZERO, 1: Vector2(100, 0), 2: Vector2(200, 0),
		3: Vector2(300, 0), 4: Vector2(400, 0),
	})
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.assign_owner(graph, atk, [0, 1])
	helper.assign_owner(graph, def, [4, 3])
	return [graph, atk]


func test_seeds_hostile_filter_drops_owned_and_neutral() -> void:
	var fx := _ownership_board()
	var graph: Graph = fx[0]
	var n := _nodes(graph)
	var hit := _aimed(8, 450.0).seeds(fx[1], n[0], 0.0, graph)
	assert_eq(_names(hit), ["N3", "N4"] as Array[String])


func test_seeds_any_filter_keeps_every_crossed_node_but_the_source() -> void:
	var fx := _ownership_board()
	var graph: Graph = fx[0]
	var n := _nodes(graph)
	var hit := _aimed(15, 450.0).seeds(fx[1], n[0], 0.0, graph)
	assert_eq(_names(hit), ["N1", "N2", "N3", "N4"] as Array[String])


func test_aimed_kind_and_validity() -> void:
	var fx := _ownership_board()
	var graph: Graph = fx[0]
	var n := _nodes(graph)
	var t := _aimed(8, 320.0)
	assert_eq(t.get_kind(), Targeting.TargetingKind.AIM)
	assert_eq(t.get_range_finder(), t.range_finder)
	var plan := MagicAttackPlan.new()
	plan.attacker = fx[1]
	assert_true(t.is_valid_target(plan, n[0], n[3]), "hostile, in reach")
	assert_false(t.is_valid_target(plan, n[0], n[4]), "hostile, out of reach")
	assert_false(t.is_valid_target(plan, n[0], n[1]), "in reach, but mine")


## Star: source N0, seeds N1..N3 (no edges between them), each with one
## hostile leaf N4..N6 behind it.
func _star() -> Array:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [0, 2], [0, 3], [1, 4], [2, 5], [3, 6]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, atk, [0])
	helper.assign_owner(graph, def, [1, 2, 3, 4, 5, 6])
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.sum_reducer(),
			{max_hops = 1})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	return [graph, atk, spell]


func test_resolve_seeds_starts_every_seed_in_wave_zero() -> void:
	var fx := _star()
	var graph: Graph = fx[0]
	var n := _nodes(graph)
	var seeds: Array[SkillNode] = [n[1], n[2], n[3]]
	var world := CombatWorld.shadow()
	var out := SpellResolver.resolve_seeds(fx[2], seeds, n[0], fx[1], graph, world)
	world.free_shadow()
	var wave0: Array[String] = []
	var wave1: Array[String] = []
	for ev in out.timeline:
		if ev.beat == 0:
			assert_eq(ev.verb, PropagationEvent.Verb.JUMP)
			wave0.append(String(ev.target.name))
			for h in ev.hits:
				assert_eq(h.structural_key, 0.0)
		elif ev.beat == 1:
			wave1.append(String(ev.target.name))
	wave0.sort()
	wave1.sort()
	assert_eq(wave0, ["N1", "N2", "N3"] as Array[String])
	assert_eq(wave1, ["N4", "N5", "N6"] as Array[String], "the spread runs on from each seed")


func test_resolve_seeds_stamps_aim_and_node_cast_does_not() -> void:
	var fx := _star()
	var graph: Graph = fx[0]
	var n := _nodes(graph)
	var spell: SpellDef = fx[2]
	spell.targeting = _aimed(8, 321.0)
	var seeds: Array[SkillNode] = [n[1]]
	var world := CombatWorld.shadow()
	var aimed := SpellResolver.resolve_seeds(spell, seeds, n[0], fx[1], graph, world, null, null, 0.5)
	world.free_shadow()
	assert_not_null(aimed.aim)
	if aimed.aim != null:
		assert_eq(aimed.aim.origin, n[0])
		assert_almost_eq(aimed.aim.angle, 0.5, 0.0001)
		# The finder's reach as scaled from N0, not the raw authored 321.
		var t := spell.targeting as AimedTargeting
		assert_almost_eq(aimed.aim.length, t.length(fx[1], n[0]), 0.0001)
		assert_gt(aimed.aim.length, 0.0)
	var node_cast := SpellResolver.resolve(spell, n[1], n[0], fx[1], graph)
	assert_null(node_cast.aim)


# -- seeds ride the graph's grid (#1704) ------------------------------------

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
## Loaded per board, never `preload`ed: a const pins the cached preset and its
## external modules (`content.tres`) for the whole shard, so a sibling test that
## edits a `duplicate(true)` copy's external module leaks into later readers.
const _PRESET_PATH := "res://procgen/presets/first_level/first_level.tres"
const _PROCGEN_NODES := 150


## Records how many candidates [method AimShape.crossed] was handed.
class SpyCone extends ConeShape:
	var sizes: Array[int] = []

	func crossed(origin: Vector2, angle: float, length: float, nodes: Array[SkillNode]) -> Array[SkillNode]:
		sizes.append(nodes.size())
		return super(origin, angle, length, nodes)


class SpyLine extends LineShape:
	var sizes: Array[int] = []

	func crossed(origin: Vector2, angle: float, length: float, nodes: Array[SkillNode]) -> Array[SkillNode]:
		sizes.append(nodes.size())
		return super(origin, angle, length, nodes)


func _procgen_board() -> Graph:
	var cfg: GraphProcgenConfig = ResourceLoader.load(_PRESET_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = _PROCGEN_NODES
	cfg.seed = 0x1704
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	await GraphProcgen.generate(cfg, graph)
	return graph


## Grid-narrowed seeds equal the shape's exact decision over the whole board
## (same set, same order), and the shape is never handed the whole board.
func _assert_grid_seeds_match_brute_force(graph: Graph, shape: AimShape, sizes: Array[int]) -> void:
	var all := _nodes(graph)
	var t := AimedTargeting.new()
	t.shape = shape
	t.ownership_filter = 15
	t.range_finder = EuclideanRangeFinder.new()
	t.range_finder.max_distance = 400.0
	var third := int(all.size() / 3.0)
	var sources: Array[SkillNode] = [all[0], all[third], all[2 * third], all[all.size() - 1]]
	var total_hits := 0
	for source in sources:
		var rest: Array[SkillNode] = all.filter(func(n: SkillNode) -> bool: return n != source)
		for angle: float in [0.0, 0.9, 2.3, -1.7, PI]:
			var got := t.seeds(null, source, angle, graph)
			var want := shape.crossed(source.global_position, angle, t.length(null, source), rest)
			assert_eq(got, want, "%s from %s at %.1f" % [shape.get_script().get_global_name(), source.name, angle])
			total_hits += got.size()
	assert_gt(total_hits, 0, "the board is dense enough that the shape crosses something")
	var biggest := 0
	for i in range(0, sizes.size(), 2):
		biggest = maxi(biggest, sizes[i])
	assert_lt(biggest, all.size() - 1, "crossed is handed the grid's candidates, never the whole board")


func test_cone_seeds_ride_the_grid_and_match_the_whole_board() -> void:
	var graph: Graph = await _procgen_board()
	var cone := SpyCone.new()
	cone.half_angle_deg = 25.0
	_assert_grid_seeds_match_brute_force(graph, cone, cone.sizes)


func test_line_seeds_ride_the_grid_and_match_the_whole_board() -> void:
	var graph: Graph = await _procgen_board()
	var line := SpyLine.new()
	line.width = 30.0
	_assert_grid_seeds_match_brute_force(graph, line, line.sizes)

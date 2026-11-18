extends GutTest

## Firecracker (#1801): its row names Fire, so a landing plants Heat; the wave
## walks the graph's edges to the hostile neighbours (the reach is the config's
## default), and what blasts is the Burning disc of a node the Heat primes.
## Geometry is derived from the shipped knobs, never literals.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const FIRECRACKER: SpellDef = preload("res://attack/spell/defs/firecracker.tres")

var h: SpellTestHelper
## Index 0 is always the attacker's node, far away unless a test moves it.
const FAR := Vector2(-100000, 0)
## Spacing that keeps every Burning disc off the neighbours.
const APART := 20000.0


func before_each() -> void:
	h = H.new()


func _fire() -> Element:
	return ElementRoster.shared().by_id(&"fire")


## A graph of [param positions] (index -> Vector2; index 0 the attacker's).
## [param edges] are the only edges besides each node's tether to node 0,
## which only exists so every node is minted. Every node but 0 and
## [param friendly] is hostile.
func _board(positions: Dictionary, edges: Array = [], friendly: Array = []) -> Dictionary:
	var adj: Array = []
	for i in positions:
		if i != 0:
			adj.append([0, i])
	adj.append_array(edges)
	var pos := positions.duplicate()
	if not pos.has(0):
		pos[0] = FAR
	var graph := h.make_graph(adj, self, pos)
	var atk := h.make_entity(graph, "A")
	var def := h.make_entity(graph, "D")
	h.give_big_hp(def)
	h.give_big_hp(atk)
	var hostile: Array = []
	for i in positions:
		if i != 0 and not friendly.has(i):
			hostile.append(i)
	h.assign_owner(graph, def, hostile)
	h.assign_owner(graph, atk, [0] + friendly)
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	return {graph = graph, atk = atk, n = graph.get_skill_nodes()}


func _resolve(b: Dictionary, seed_idx: int, spell: SpellDef = FIRECRACKER, inf: Infusion = null) -> AttackOutcome:
	var n: Array = b.n
	return SpellResolver.resolve(spell, n[seed_idx], n[0], b.atk, b.graph, null, inf)


func _landings(outcome: AttackOutcome) -> Array[PropagationEvent]:
	var out: Array[PropagationEvent] = []
	for ev in outcome.timeline:
		if ev.verb != PropagationEvent.Verb.CANCEL:
			out.append(ev)
	return out


func _beats_of(outcome: AttackOutcome, node: SkillNode) -> Array:
	return _landings(outcome).filter(func(ev): return ev.target == node).map(func(ev): return ev.beat)


func _hits_on(outcome: AttackOutcome, node: SkillNode) -> Array:
	return outcome.hits.filter(func(x): return _is_main_hit(x, node))


func _is_main_hit(x: HitInstance, node: SkillNode) -> bool:
	return x.target == node and not (x is CureInstance or x is StatusInstance)


# 1 ---------------------------------------------------------------------------

func test_a_landing_walks_the_edges_to_hostile_neighbours_only() -> void:
	var b := _board({1: Vector2.ZERO, 2: Vector2(APART, 0), 3: Vector2(-APART, 0)}, [[1, 2]])
	var n: Array = b.n
	var outcome := _resolve(b, 1)
	assert_eq(_beats_of(outcome, n[1]), [0], "the seed lands on wave 0")
	assert_eq(_beats_of(outcome, n[2]), [1], "the edge neighbour lands on wave 1")
	assert_true(_beats_of(outcome, n[3]).is_empty(), "a node with no edge to it never does")


func test_a_friendly_neighbour_never_lands() -> void:
	var b := _board({1: Vector2.ZERO, 2: Vector2(APART, 0), 3: Vector2(0, APART)}, [[1, 2], [1, 3]], [3])
	var n: Array = b.n
	var outcome := _resolve(b, 1)
	assert_eq(_beats_of(outcome, n[2]), [1], "the hostile lands")
	assert_true(_beats_of(outcome, n[3]).is_empty(), "the friendly never does")


func test_no_node_lands_in_two_waves() -> void:
	var pos := {}
	var edges: Array = []
	for i in range(1, 30):
		@warning_ignore("integer_division")  # intended truncation: index/count/offset
		pos[i] = Vector2((i % 6) * APART, (i / 6) * APART)
		if i > 1:
			edges.append([i - 1, i])
		if i > 6:
			edges.append([i - 6, i])
	var b := _board(pos, edges)
	var outcome := _resolve(b, 1)
	for node in b.n:
		assert_lte(_beats_of(outcome, node).size(), 1, "%s lands at most once" % node.name)


func test_the_cast_stops_at_max_hops() -> void:
	var hops := int(FIRECRACKER.propagation.max_hops)
	var pos := {}
	var edges: Array = []
	for i in range(1, hops + 4):
		pos[i] = Vector2((i - 1) * APART, 0)
		if i > 1:
			edges.append([i - 1, i])
	var b := _board(pos, edges)
	var outcome := _resolve(b, 1)
	var beats: Array = _landings(outcome).map(func(ev): return ev.beat)
	assert_eq(beats.max(), hops, "the cast stops at max_hops")


# 2 ---------------------------------------------------------------------------

func test_the_row_names_fire_and_its_landing_plants_heat_at_the_innate() -> void:
	var row := Infusion.intake_of(FIRECRACKER, &"fire")
	assert_not_null(row, "the row names Fire")
	var riders := Infusion.innate(FIRECRACKER).riders(FIRECRACKER)
	assert_eq(riders.size(), 1, "one rider")
	assert_eq((riders[0] as ApplyStatusEffect).def, _fire().terrain, "it plants Heat")
	assert_eq((riders[0] as ApplyStatusEffect).power, float(row.innate), "at the row's innate")


func test_a_landing_plants_heat_on_each_node_it_reaches() -> void:
	var b := _board({1: Vector2.ZERO, 2: Vector2(APART, 0)}, [[1, 2]])
	var n: Array = b.n
	var outcome := _resolve(b, 1)
	for i in [1, 2]:
		var heat := outcome.hits.filter(func(x): return x is StatusInstance and x.target == n[i] and x.def == _fire().terrain)
		assert_eq(heat.size(), 1, "node %d takes one Heat rider" % i)


# 3 ---------------------------------------------------------------------------

## A node the Heat tips into Burning goes off through Burning's disc: the cast
## itself has no blast.
func test_a_landing_that_primes_a_node_sets_off_burnings_disc() -> void:
	var disc := _fire().bands[0].go_off as DiscGoOff
	var innate := float(Infusion.intake_of(FIRECRACKER, &"fire").innate)
	assert_not_null(disc, "fixture: Burning's disc")
	var rad := 32.0
	var reach := disc.radius_a * (sqrt(innate) + disc.radius_b) * rad
	var b := _board({1: Vector2.ZERO, 2: Vector2(rad + 0.5 * reach, 0)}, [[1, 2]])
	var n: Array = b.n
	var seed_node: SkillNode = n[1]
	assert_almost_eq(seed_node.radius, rad, 0.01, "fixture: geometry assumes this node radius")
	var combat := seed_node.get_combat()
	combat.add_terrain(_fire(), combat.terrain_threshold() - combat.terrain_t())
	(b.graph as Graph).navigator.reconcile()
	var outcome := _resolve(b, 1)
	await OutcomeApplier.drain(HitQueue.over(outcome.hits), CombatWorld.live(), BeatClock.instant_clock())
	var marks := outcome.hits.filter(func(x: HitInstance) -> bool:
			return x.blast_mark != null and x.blast_mark.centre == seed_node)
	assert_false(marks.is_empty(), "the primed seed set Burning's disc off")

extends GutTest

## #1812: a spell cast's Fire or Lightning shape at its seed's gather head
## (`docs/design/elements/casting.md` § Shape and ride; ADR 0084 §1-§6, ADR
## 0086 §1-§5). A shape reshapes the seed's reach and plants nothing: on a node
## primed in its element it adds into that band's go-off (one channel, the
## node's solo cost); anywhere else (a Frozen node's muted bands included) it
## runs alone as a list, no channel: no spend, no centre copy.
##
## The carrier is the head's [member HitInstance.cast_shape] /
## [member HitInstance.cast_shape_points], stamped by [SpellResolver] on each
## wave-0 seed head (8b goes through the resolver); the rest hand-stamp it.
## Knobs (share, A, B, the per-point power, the floor, the break threshold)
## are read off their owners, never as literals. Every hit is Blue's TRUE
## damage [constant _D] with a Poison rider of [constant _POISON].

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _D := 1.0
const _POISON := 3.0
const _FAR := 20000.0

var _w: TestWorld
var _red: Entity
var _blue: Entity
var _fire: Element
var _ice: Element
var _light: Element
var _fa: FrozenAdmits
var _disc: DiscGoOff
var _edge: EdgeGoOff
var _was_tunables: HitGatherTunables
var _was_disc: Array = []


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_red = _w.add_entity("Red")
	_blue = _w.add_entity("Blue")
	await get_tree().process_frame
	_fire = ElementRoster.shared().by_id(&"fire")
	_ice = ElementRoster.shared().by_id(&"ice")
	_light = ElementRoster.shared().by_id(&"lightning")
	_fa = _ice.bands[0].admits as FrozenAdmits
	_disc = _fire.bands[0].go_off as DiscGoOff
	_edge = _light.bands[0].go_off as EdgeGoOff
	_was_disc = [_disc.damage_per_power, _disc.solo_cost_floor, _disc.radius_a, _disc.radius_b]
	_disc.damage_per_power = 0.0
	_was_tunables = HitGather.tunables
	_dedupe(false)


func after_each() -> void:
	_disc.damage_per_power = _was_disc[0]
	_disc.solo_cost_floor = _was_disc[1]
	_disc.radius_a = _was_disc[2]
	_disc.radius_b = _was_disc[3]
	HitGather.tunables = _was_tunables
	CombatWorld.reset_live()


func _dedupe(on: bool) -> void:
	var tun := HitGatherTunables.new()
	tun.dedupe_dual_reach = on
	HitGather.tunables = tun


# --- fixture -----------------------------------------------------------------

## A node at [param pos] linked to one far anchor of its own (its T reads a
## degree without another node in reach).
func _at(id: String, pos: Vector2) -> SkillNode:
	var n := _w.add_node(StringName(id), pos)
	_w.link(n, _w.add_node(StringName(id + "_anchor"), pos + Vector2(0.0, _FAR)))
	return n


## A hub X with [param k] neighbours on a ring 3000 px out (beyond any disc
## here), each with one far anchor: `[X, n1, ..., nk]`.
func _star(prefix: String, k: int) -> Array[SkillNode]:
	var x := _w.add_node(StringName(prefix + "X"), Vector2.ZERO)
	var out: Array[SkillNode] = [x]
	for i in k:
		var n := _at("%sN%d" % [prefix, i], Vector2.from_angle(TAU * i / k) * 3000.0)
		_w.link(x, n)
		out.append(n)
	return out


func _own(nodes: Array) -> void:
	_w.allocate(_red, nodes)
	await get_tree().process_frame


func _c(n: SkillNode) -> NodeCombat:
	return CombatWorld.live().combat_for(n) as NodeCombat


func _t(n: SkillNode) -> int:
	return _c(n).terrain_threshold()


func _heat(n: SkillNode) -> int:
	return _c(n).terrain_t()


func _cold(n: SkillNode) -> int:
	return _c(n).terrain_count(_ice)


func _charge(n: SkillNode) -> int:
	return _c(n).charge()


func _set_charge(n: SkillNode, to: int) -> void:
	_c(n).add_terrain(_light, to - _charge(n))


func _set_t(n: SkillNode, to: int) -> void:
	_c(n).add_terrain(_fire, to - _heat(n))


func _freeze(n: SkillNode) -> void:
	_set_t(n, -(_t(n) + 1))


func _tau(n: SkillNode) -> float:
	return _fa.break_fraction_max_hp * _c(n).owner().get_max_hp()


## Nodes within [param hops] of [param x] on the graph's mirror, x excluded.
func _ball(x: SkillNode, hops: int) -> Array:
	var mirror: GraphMirror = x.get_graph().navigator
	return mirror.nodes_within(x, hops).keys().filter(func(n: SkillNode) -> bool: return n != x)


## Fire's shape disc radius at [param x] for [param points] over an excess.
func _shape_r(points: int, excess: float, x: SkillNode) -> float:
	return _disc.shape_disc_radius(_fire.shape_power(points), excess, x.radius)


## A direct hit on [param at], shaped [param shape] × [param points], with one
## raw rider per `[param riders]` entry (StatusDef → stacks).
func _hit(at: SkillNode, shape: Element, points: int, riders := {}) -> Array[HitInstance]:
	var d := DamageInstance.new()
	d.amount = _D
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	d.cast_shape = shape
	d.cast_shape_points = points
	var span: Array[HitInstance] = [d]
	var p := StatusInstance.new()
	p.def = preload("res://effects/status/poison.tres")
	p.power = _POISON
	p.raw = true
	span.append(p)
	for def: StatusDef in riders:
		var s := StatusInstance.new()
		s.def = def
		s.power = float(riders[def])
		s.raw = true
		span.append(s)
	for h in span:
		h.target = at
		h.attacker = _blue
		h.schedule_index = 0
		h.structural_key = 0.0
	return span


func _land(span: Array[HitInstance]) -> Array[HitInstance]:
	var all: Array[HitInstance] = span.duplicate()
	HitGather.stage_one(span.duplicate(), CombatWorld.live(), HitQueue.over(all))
	return all


func _on(all: Array, n: SkillNode) -> Array:
	return all.filter(func(h: HitInstance) -> bool: return h.target == n)


func _dmg(all: Array, n: SkillNode) -> Array:
	return _on(all, n).filter(func(h: HitInstance) -> bool:
		return h is DamageInstance and not HitGather.is_burst(h))


func _takes(all: Array, n: SkillNode) -> int:
	return _dmg(all, n).size()


func _poison(all: Array, n: SkillNode) -> Array:
	return _on(all, n).filter(func(h: HitInstance) -> bool:
		return h is StatusInstance and h.def.id == &"poison")


## The nodes every damage entry carrying [param mark] lands on, the centre's apart.
func _copies_of(all: Array, mark: BlastMark) -> Array:
	var out: Array = []
	for h: HitInstance in all:
		if h is DamageInstance and h.blast_mark == mark and h.target != mark.centre and not out.has(h.target):
			out.append(h.target)
	return out


## The distinct marks the damage entries in [param all] carry.
func _marks(all: Array) -> Array:
	var out: Array = []
	for h: HitInstance in all:
		if h is DamageInstance and h.blast_mark != null and not out.has(h.blast_mark):
			out.append(h.blast_mark)
	return out


func _same_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for x in a:
		if not b.has(x):
			return false
	return true


func _s_edge() -> float:
	return _edge.share


func _s_disc() -> float:
	return _disc.share


# 1 ─────────────────────────────────────────────────────────────────────────────
func test_level_for_points_is_the_triangular_rule() -> void:
	var got: Array = []
	for p in [0, 1, 2, 3, 5, 6, 10]:
		got.append(EdgeGoOff.level_for_points(p))
	assert_eq(got, [0, 1, 1, 2, 2, 3, 4])


# 2 ─────────────────────────────────────────────────────────────────────────────
func test_a_lightning_shape_alone_lands_once_on_the_seed_and_copies_every_node_within_its_level() -> void:
	var g := _star("", 3)
	await _own(g.slice(0, 2))  # allocated or not: two neighbours stay unowned
	var x := g[0]
	assert_eq(EdgeGoOff.level_for_points(3), 2, "fixture: 3 points buy level 2")
	var ball := _ball(x, 2)
	assert_eq(ball.size(), 6, "fixture: 3 neighbours and their 3 anchors")
	_set_charge(x, _t(x))
	assert_eq(_edge.level_of(TerrainRead.of(_c(x), x)), 0, "fixture: X holds Charge T, not Shocked")
	var all := _land(_hit(x, _light, 3))
	assert_eq(_takes(all, x), 1, "the seed lands once: the shape is no channel")
	assert_eq(_charge(x), _t(x), "no Charge spent, none planted")
	for n: SkillNode in ball:
		var d := _dmg(all, n)
		assert_eq(d.size(), 1, "%s takes one shape copy" % n.name)
		if d.size() == 1:
			assert_almost_eq((d[0] as HitInstance).amount, _D * _s_edge(), 0.0001, "at the arc's share")
			assert_eq((d[0] as HitInstance).paired, all[0], "paired to the seed: it carries its crit")
		var p := _poison(all, n)
		assert_eq(p.size(), 1, "%s takes one Poison" % n.name)
		if p.size() == 1:
			assert_eq((p[0] as StatusInstance).power, ceilf(_POISON * _s_edge()), "ceil(p × share)")
	var marks := _marks(all)
	assert_eq(marks.size(), 1, "one shape mark")
	if marks.size() == 1:
		assert_true(_same_set(_copies_of(all, marks[0]), ball), "its copies are the 2-hop ball")


# 3 ─────────────────────────────────────────────────────────────────────────────
func test_a_lightning_shape_on_a_shocked_node_adds_up_into_one_arc_at_its_solo_cost() -> void:
	var g := _star("", 3)
	await _own(g)
	var x := g[0]
	_set_charge(x, _t(x) + 1)
	assert_eq(_edge.level_of(TerrainRead.of(_c(x), x)), 1, "fixture: X is Shocked, level 1")
	var before := _charge(x)
	var all := _land(_hit(x, _light, 1))
	assert_eq(before - _charge(x), _ball(x, 1).size(), "X pays its solo cost: its 1-hop count")
	for n: SkillNode in _ball(x, 2):
		assert_eq(_takes(all, n), 1, "%s: one entry, not two" % n.name)
	assert_eq(_marks(all).size(), 1, "one go-off")
	assert_eq(_takes(all, x), 2, "the seed and the combined go-off's one centre copy")


# 4 ─────────────────────────────────────────────────────────────────────────────
func test_a_fire_shape_alone_reaches_by_the_seeds_own_radius() -> void:
	var x := _at("X", Vector2.ZERO)
	x.base_radius *= 2.0  # unlike every other node's: reading another fails
	var r1 := _shape_r(1, 0.0, x)
	var r3 := _shape_r(3, 0.0, x)
	assert_almost_eq(r1, _disc.radius_a * (sqrt(_fire.shape_power_per_point) + _disc.radius_b) * x.radius, 0.001)
	assert_almost_eq(r3, _disc.radius_a * (sqrt(3.0 * _fire.shape_power_per_point) + _disc.radius_b) * x.radius, 0.001)
	var probe := _at("P", Vector2(10000.0, 0.0))
	var inside := _at("In", Vector2(r3 + probe.radius - 2.0, 0.0))
	var outside := _at("Out", Vector2(-(r3 + probe.radius + 2.0), 0.0))
	await _own([x, inside, outside])
	assert_ne(x.radius, probe.radius, "fixture: the seed's radius is its own")
	_set_t(x, _t(x) - 1)
	var all := _land(_hit(x, _fire, 3))
	assert_eq(_takes(all, x), 1, "the seed lands once")
	assert_eq(_takes(all, inside), 1, "just inside the shaped disc: a copy")
	assert_eq(_takes(all, outside), 0, "just outside: none")
	assert_eq(_heat(x), _t(x) - 1, "its Heat is unchanged")
	assert_null(_c(x).terrain_band(_fire), "no status planted")


# 5 ─────────────────────────────────────────────────────────────────────────────
func test_a_fire_shape_on_a_burning_node_adds_the_roots_into_one_disc() -> void:
	assert_almost_eq(_disc.shape_disc_radius(0.0, 4.0, 30.0), _disc.disc_radius(4.0, 30.0), 0.0001)
	_disc.radius_a = 3.0
	_disc.radius_b = 2.0
	assert_almost_eq(_disc.shape_disc_radius(0.0, 4.0, 30.0), _disc.disc_radius(4.0, 30.0), 0.0001,
			"A and B move both")
	_disc.radius_a = _was_disc[2]
	_disc.radius_b = _was_disc[3]
	var x := _at("X", Vector2.ZERO)
	var solo := _disc.radius_at(x, 4)
	var both := _shape_r(3, 4.0, x)
	var a := _at("A", Vector2(solo * 0.5, 0.0))
	var b := _at("B", Vector2(-solo * 0.5, 0.0))
	var far := _at("F", Vector2(0.0, (solo + both) * 0.5 + x.radius))
	await _own([x, a, b, far])
	_set_t(x, _t(x) + 4)
	var all := _land(_hit(x, _fire, 3))
	assert_eq(_takes(all, far), 1, "beyond the solo disc, inside the combined one")
	assert_eq(_marks(all).size(), 1, "one go-off")
	if _marks(all).size() == 1:
		assert_almost_eq((_marks(all)[0] as BlastMark).reach, both, 0.001, "reach = shape_disc_radius(3, 4, R)")
	assert_eq(_heat(x), _t(x) + 4 - 2, "X loses its solo disc's spend (A and B), never the shape's")
	assert_eq(_takes(all, x), 2, "the seed and the one centre copy")


# 6 ─────────────────────────────────────────────────────────────────────────────
func _floor_case(floor: int) -> Array:
	_disc.solo_cost_floor = floor
	var x := _at("X", Vector2.ZERO)
	var far := _at("F", Vector2(_shape_r(3, 1.0, x) - x.radius, 0.0))
	await _own([x, far])
	_set_t(x, _t(x) + 1)
	assert_gt(far.global_position.x - far.radius, _disc.radius_at(x, 1), "fixture: the solo disc reaches nobody")
	var all := _land(_hit(x, _fire, 3))
	return [x, far, all]


func test_floor_one_costs_a_burning_node_one_stack() -> void:
	var got: Array = await _floor_case(1)
	var x: SkillNode = got[0]
	assert_eq(_takes(got[2], got[1]), 1, "the combined disc reaches F")
	assert_eq(_heat(x), _t(x), "X pays the floor: 1")
	assert_eq(_takes(got[2], x), 2, "it goes off: the seed takes 2")


func test_floor_zero_costs_nothing() -> void:
	var got: Array = await _floor_case(0)
	var x: SkillNode = got[0]
	assert_eq(_heat(x), _t(x) + 1, "floor 0: X pays nothing")
	assert_eq(_takes(got[2], x), 2, "it still goes off: the seed takes 2")


# 7 / 7a / 9 ───────────────────────────────────────────────────────────────────
func test_a_fire_shape_on_an_unprimed_seed_is_one_landing_and_one_copy_per_disc_node() -> void:
	var x := _at("X", Vector2.ZERO)
	var r := _shape_r(3, 0.0, x)
	var a := _at("A", Vector2(r * 0.5, 0.0))
	var b := _at("B", Vector2(-r * 0.5, 0.0))
	await _own([x, a, b])
	var all := _land(_hit(x, _fire, 3, {_fire.terrain: 1}))
	assert_eq(_takes(all, x), 1, "the seed: one landing")
	assert_eq(_heat(x), 1, "its Heat + 1")
	for n: SkillNode in [a, b]:
		assert_eq(_takes(all, n), 1, "%s: one copy" % n.name)
		assert_almost_eq((_dmg(all, n)[0] as HitInstance).amount, _D * _s_disc(), 0.0001)
		assert_eq((_poison(all, n)[0] as StatusInstance).power, ceilf(_POISON * _s_disc()))
		assert_eq(_heat(n), ceili(1 * _s_disc()), "Heat ceil(1 × s)")


## X at origin (Shocked level 1: Charge T + 1), B linked and inside the disc (both
## reaches), D unlinked inside the disc (disc only), X's anchor (arc only).
## `[X, B, D, anchor, all]` after a Fire [param points] shape with
## [param riders].
func _two_reaches(points: int, riders: Dictionary) -> Array:
	var x := _at("X", Vector2.ZERO)
	var r := _shape_r(points, 0.0, x)
	var b := _at("B", Vector2(r * 0.5, 0.0))
	var d := _at("D", Vector2(-r * 0.5, 0.0))
	_w.link(x, b)
	var anchor: SkillNode = _ball(x, 1).filter(func(n: SkillNode) -> bool: return n != b)[0]
	await _own([x, b, d, anchor])
	_set_charge(x, _t(x) + 1)
	var all := _land(_hit(x, _fire, points, riders))
	return [x, b, d, anchor, all]


func test_a_fire_shape_on_a_shocked_node_is_two_reaches_concatenated() -> void:
	var got: Array = await _two_reaches(3, {_fire.terrain: 1})
	var x: SkillNode = got[0]
	var all: Array = got[4]
	assert_eq(_charge(x), _t(x) + 1 - _ball(x, 1).size(), "the arc spends as without the shape")
	assert_eq(_takes(all, x), 2, "the seed and the arc's centre copy; the disc adds none")
	var on_x := _dmg(all, x).map(func(h: HitInstance) -> float: return h.amount)
	on_x.sort()
	assert_almost_eq(on_x[0] + on_x[1], _D + _D * _s_edge(), 0.0001, "D + D × s")
	assert_eq(_poison(all, x).size(), 2, "p and ceil(p × s)")
	assert_eq(_heat(x), 1, "Heat + 1, once")
	assert_eq(_takes(all, got[1]), 2, "B in both reaches takes 2")
	assert_eq(_heat(got[1]), ceili(1 * _s_disc()), "B's Heat once")
	assert_eq(_takes(all, got[2]), 1, "D in the disc only: 1")
	assert_eq(_takes(all, got[3]), 1, "the anchor in the arc only: 1")


func test_7a_two_marks_at_the_seed_told_apart_by_their_copy_sets() -> void:
	var got: Array = await _two_reaches(3, {})
	var x: SkillNode = got[0]
	var marks := _marks(got[4])
	assert_eq(marks.size(), 2, "two marks: the shape's disc and the node's arc")
	var sets := marks.map(func(m: BlastMark) -> Array: return _copies_of(got[4], m))
	var disc := [got[1], got[2]]
	var arc := _ball(x, 1)
	assert_true((_same_set(sets[0], disc) and _same_set(sets[1], arc))
			or (_same_set(sets[1], disc) and _same_set(sets[0], arc)), "one the disc's reach, one the arc's")
	for m: BlastMark in marks:
		assert_eq(m.centre, x, "both at the seed")
	var on_b := _dmg(got[4], got[1]).map(func(h: HitInstance) -> BlastMark: return h.blast_mark)
	assert_ne(on_b[0], on_b[1], "B's two entries are two rows")


func test_dedupe_on_folds_the_both_reach_node_and_never_the_seed() -> void:
	_dedupe(true)
	var got: Array = await _two_reaches(3, {_fire.terrain: 1})
	var all: Array = got[4]
	assert_eq(_takes(all, got[1]), 1, "B: one landing")
	assert_almost_eq((_dmg(all, got[1])[0] as HitInstance).amount, _D * (_s_disc() + _s_edge()), 0.0001,
			"at the summed share")
	assert_eq((_poison(all, got[1])[0] as StatusInstance).power, ceilf(_POISON * (_s_disc() + _s_edge())))
	assert_eq(_takes(all, got[0]), 2, "the seed still takes 2")
	assert_eq(_takes(all, got[2]), 1, "one-reach nodes unchanged")
	assert_eq(_heat(got[1]), ceili(1 * _s_disc()), "Heat once")


func test_9_riders_first_a_charge_rider_tips_the_seed_and_both_reaches_go() -> void:
	var x := _at("X", Vector2.ZERO)
	var r := _shape_r(2, 0.0, x)
	var b := _at("B", Vector2(r * 0.5, 0.0))
	var d := _at("D", Vector2(-r * 0.5, 0.0))
	_w.link(x, b)
	await _own([x, b, d])
	_set_charge(x, _t(x))
	assert_eq(_edge.level_of(TerrainRead.of(_c(x), x)), 0, "fixture: one short of Shocked")
	var all := _land(_hit(x, _fire, 2, {_light.terrain: 1}))
	assert_eq(_takes(all, x), 2, "the seed and the arc's centre copy")
	assert_eq(_takes(all, b), 2, "B in both: 2")
	assert_eq(_takes(all, d), 1, "D in the disc only: 1")
	assert_eq(_charge(d), ceili(1 * _s_disc()), "the Charge rider lands once on D")


# 8 ─────────────────────────────────────────────────────────────────────────────
func test_a_shape_copy_onto_a_frozen_node_under_the_threshold_is_absorbed_its_cold_lands() -> void:
	var g := _star("", 2)
	await _own(g)
	var x := g[0]
	var f := g[1]
	_freeze(f)
	assert_lt(_D * _s_edge(), _tau(f), "fixture: the copy is under F's break threshold")
	var cold := _cold(f)
	var all := _land(_hit(x, _light, 1, {_ice.terrain: 1}))
	assert_eq(_takes(all, f), 0, "absorbed: no damage")
	assert_eq(_poison(all, f).size(), 0, "and no Poison")
	assert_eq(_cold(f), cold + ceili(1 * _s_edge()), "its Cold still lands, once")
	assert_eq(_takes(all, g[2]), 1, "the unfrozen neighbour takes its copy")


func test_a_shape_copy_sets_off_a_burning_neighbour() -> void:
	var g := _star("", 2)
	await _own(g)
	var x := g[0]
	var n := g[1]
	var near := _at("Near", n.global_position + Vector2(n.radius * 3.0, 0.0))
	await _own([near])
	_set_t(n, _t(n) + 1)
	var all := _land(_hit(x, _light, 1))
	assert_eq(_takes(all, n), 2, "the shape's copy and its own disc's centre copy")
	assert_eq(_takes(all, near), 1, "its disc reaches on")


# 8a ────────────────────────────────────────────────────────────────────────────
func test_8a_a_lightning_shape_on_a_frozen_shocked_seed_runs_alone() -> void:
	var g := _star("", 3)
	await _own(g)
	var x := g[0]
	_freeze(x)
	_set_charge(x, _t(x) + 1)
	_freeze(g[1])
	assert_eq(_edge.level_of(TerrainRead.of(_c(x), x)), 1, "fixture: X Shocked")
	assert_not_null(_c(x).terrain_band(_ice), "fixture: X Frozen")
	assert_lt(_D, _tau(x), "fixture: the seed does not break the ice")
	var charge := _charge(x)
	var all := _land(_hit(x, _light, 1))
	assert_eq(_charge(x), charge, "the arc is muted: Charge unchanged")
	assert_eq(_takes(all, x), 1, "the seed takes 1")
	assert_eq(_takes(all, g[1]), 0, "the Frozen neighbour absorbs its copy")
	assert_eq(_poison(all, g[1]).size(), 0, "and its Poison")
	for n in [g[2], g[3]]:
		assert_eq(_takes(all, n), 1, "%s: one shape copy" % n.name)


# 8b ────────────────────────────────────────────────────────────────────────────
func test_8b_every_seed_of_a_multi_seed_cast_is_shaped() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, atk, [3])
	helper.assign_owner(graph, def, [0, 1, 2, 4, 5, 6])
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.sum_reducer(),
			{max_hops = 0})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n: Array[SkillNode] = []
	n.assign(graph.get_skill_nodes())
	var infusion := Infusion.new()
	infusion.set_shape(&"lightning", 1)
	var seeds: Array[SkillNode] = [n[1], n[5]]
	var world := CombatWorld.shadow()
	var out := SpellResolver.resolve_seeds(spell, seeds, n[3], atk, graph, world, null, infusion)
	world.free_shadow()
	var hits: Array = out.hits
	assert_eq(_takes(hits, n[1]), 1, "A: one landing, no centre copy")
	assert_eq(_takes(hits, n[5]), 1, "B: one landing, no centre copy")
	var marks := _marks(hits)
	assert_eq(marks.size(), 2, "one shape mark per seed")
	for m: BlastMark in marks:
		var want := [n[0], n[2]] if m.centre == n[1] else [n[4], n[6]]
		assert_true(_same_set(_copies_of(hits, m), want), "one copy on each 1-hop node of %s" % m.centre.name)


# 2 (the walk) ─────────────────────────────────────────────────────────────────
## A shape touches the cast's seed, never its walk: a 2-hop walk lands on the
## same nodes in the same beats shaped or not, and only wave 0 carries it.
func test_a_shaped_cast_walks_exactly_as_the_unshaped_one() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 3], [3, 4]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, atk, [0])
	helper.assign_owner(graph, def, [1, 2, 3, 4])
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.sum_reducer(),
			{max_hops = 2})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n: Array[SkillNode] = []
	n.assign(graph.get_skill_nodes())
	var shaped := Infusion.new()
	shaped.set_shape(&"lightning", 1)
	var walks: Array = []
	var outs: Array = []
	for inf: Infusion in [Infusion.new(), shaped]:
		var out := SpellResolver.resolve(spell, n[1], n[0], atk, graph, null, inf)
		outs.append(out)
		walks.append(out.timeline.map(func(ev: PropagationEvent) -> Array: return [ev.beat, ev.target]))
	assert_eq(walks[0].size(), 3, "fixture: the walk lands three waves")
	assert_eq(walks[1], walks[0], "same landings, same beats")
	var shaped_out: AttackOutcome = outs[1]
	assert_eq(_marks(shaped_out.hits).size(), 1, "one shape mark, at the seed")
	for ev: PropagationEvent in shaped_out.timeline:
		for h: HitInstance in ev.hits:
			if ev.beat > 0:
				assert_null(h.cast_shape, "no later wave's landing carries a shape")

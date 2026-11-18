extends GutTest

## The pair rules (`docs/design/elements/frozen.md` § Pair rules): what needs two
## elements at once. Frozen mutes a node's own go-offs and the break releases
## them, once per breaking hit; Frozen ends an arc or a disc's copy; dual reach
## concatenates; Catalyst under a Frozen node; a Cold rider on Shocked and
## Burning nodes. Stage one only ([method HitGather.stage_one] over a
## [HitQueue]): a node "takes n" when n damage entries reach it, the shatter's
## burst counted apart ([method HitGather.is_burst]).
##
## The roster's real bands throughout; the threshold, the break's channel count
## and the shatter knobs are read from Ice's [FrozenAdmits], never a literal.
## Every counted node is Red's (the holder whose max HP sizes the threshold);
## every hit is Blue's TRUE damage with a Poison rider of [constant _POISON].

const _POISON := 3.0
const _FAR := 20000.0
const _CATALYST := preload("res://effects/status/catalyst.tres")

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
var _was_dpp := 0.0


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
	_was_dpp = _disc.damage_per_power
	_disc.damage_per_power = 0.0
	_was_tunables = HitGather.tunables
	_dedupe(false)


func after_each() -> void:
	_disc.damage_per_power = _was_dpp
	HitGather.tunables = _was_tunables
	CombatWorld.reset_live()


func _dedupe(on: bool) -> void:
	var tun := HitGatherTunables.new()
	tun.dedupe_dual_reach = on
	HitGather.tunables = tun


# --- fixture -----------------------------------------------------------------

## A node at [param pos] linked to [param anchors] far anchors of its own, so
## its T reads a degree without another node in reach.
func _at(id: String, pos: Vector2, anchors := 1) -> SkillNode:
	var n := _w.add_node(StringName(id), pos)
	for i in anchors:
		var a := _w.add_node(StringName("%s_anchor%d" % [id, i]), pos + Vector2(3000.0 * i, _FAR))
		_w.link(n, a)
	return n


## A hub X with [param k] neighbours on a ring 3000 px out, each with one far
## anchor: `[X, n1, ..., nk]`.
func _star(prefix: String, k: int, origin := Vector2.ZERO) -> Array[SkillNode]:
	var x := _w.add_node(StringName(prefix + "X"), origin)
	var out: Array[SkillNode] = [x]
	for i in k:
		var n := _at("%sN%d" % [prefix, i], origin + Vector2.from_angle(TAU * i / k) * 3000.0)
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


func _tt(n: SkillNode) -> int:
	return _c(n).terrain_t()


func _cold(n: SkillNode) -> int:
	return _c(n).terrain_count(_ice)


func _charge(n: SkillNode) -> int:
	return _c(n).charge()


func _set_charge(n: SkillNode, to: int) -> void:
	_c(n).add_terrain(_light, to - _charge(n))


func _set_t(n: SkillNode, to: int) -> void:
	_c(n).add_terrain(_fire, to - _tt(n))


## Cold T + [param e]: Frozen.
func _freeze(n: SkillNode, e := 1) -> void:
	_set_t(n, -(_t(n) + e))


func _frozen(n: SkillNode) -> bool:
	return _c(n).terrain_band(_ice) != null


## The flat break threshold on [param n]: the knob × its holder's max HP.
func _tau(n: SkillNode) -> float:
	return _fa.break_fraction_max_hp * _c(n).owner().get_max_hp()


## The break's channel count b.
func _b() -> int:
	return _fa.break_channels


## The Cold a shatter leaves of [param cold] on [param n].
func _after_shatter(n: SkillNode, cold: int) -> int:
	return cold - roundi((cold - _t(n)) * _fa.shatter_spend_fraction)


## The disc's radius at [param n] for a Heat excess of [param excess].
func _r(n: SkillNode, excess: int) -> float:
	return _disc.radius_at(n, excess)


## A direct hit on [param at]: damage [param dmg], Poison, and one raw rider per
## `[param riders]` entry (StatusDef → stacks).
func _hit(at: SkillNode, dmg: float, riders := {}) -> Array[HitInstance]:
	var d := DamageInstance.new()
	d.amount = dmg
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
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


func _crit(span: Array[HitInstance]) -> Array[HitInstance]:
	span[0].is_crit = true
	span[0].crit_tier = 1
	span[0].crit_multiplier = 1.5
	span[0].crit_decided = true
	return span


## One beat over [param spans]: everything stage one pushes, the spans first.
func _land(spans: Array) -> Array[HitInstance]:
	var all: Array[HitInstance] = []
	for s: Array in spans:
		all.append_array(s)
	HitGather.stage_one(all.duplicate(), CombatWorld.live(), HitQueue.over(all))
	return all


func _on(all: Array, n: SkillNode) -> Array:
	return all.filter(func(h: HitInstance) -> bool: return h.target == n)


## The landings on [param n]: damage entries, the burst apart.
func _takes(all: Array, n: SkillNode) -> int:
	return _on(all, n).filter(func(h: HitInstance) -> bool:
		return h is DamageInstance and not HitGather.is_burst(h)).size()


func _poisons(all: Array, n: SkillNode) -> int:
	return _on(all, n).filter(func(h: HitInstance) -> bool:
		return h is StatusInstance and h.def.id == &"poison").size()


func _bursts(all: Array, n: SkillNode) -> int:
	return _on(all, n).filter(func(h: HitInstance) -> bool: return HitGather.is_burst(h)).size()


## The fixture of 1 and 2: X Frozen (Cold T + 1) and Shocked (Charge T + 1,
## level 1) with [param k] unfrozen neighbours, all Red's. `[X, n...]`.
func _frozen_shocked(k: int, prefix := "") -> Array[SkillNode]:
	var g := _star(prefix, k)
	await _own(g)
	var x := g[0]
	_freeze(x)
	_set_charge(x, _t(x) + 1)
	assert_true(_frozen(x), "fixture: X is Frozen")
	assert_eq(_edge.level_of(TerrainRead.of(_c(x), x)), 1, "fixture: X is Shocked, level 1")
	assert_gt(_tau(x), 0.0, "fixture: X's holder sizes a threshold")
	return g


# 1 ─────────────────────────────────────────────────────────────────────────────
func test_frozen_mutes_shocked_and_an_arrivals_charge_joins_the_trapped_store() -> void:
	var g: Array[SkillNode] = await _frozen_shocked(2)
	var x := g[0]
	var charge := _charge(x)
	var cold := _cold(x)
	var all := _land([_hit(x, _tau(x) * 0.5, {_light.terrain: 1})])
	assert_eq(_takes(all, x), 1, "X takes 1: the muted arc lands no centre payload")
	assert_eq(_poisons(all, x), 1, "one Poison")
	assert_eq(_charge(x), charge + 1, "no Charge spent; the rider joins the trapped store")
	assert_eq(_cold(x), cold, "its Cold unchanged")
	assert_eq(_bursts(all, x), 0, "nothing shatters")
	for n in g.slice(1):
		assert_eq(_takes(all, n), 0, "%s untouched" % n.name)
		assert_eq(_charge(n), 0, "%s gains no Charge" % n.name)


# 2 ─────────────────────────────────────────────────────────────────────────────
func _assert_released(crit: bool) -> void:
	var g: Array[SkillNode] = await _frozen_shocked(3)
	var x := g[0]
	var cold := _cold(x)
	var charge := _charge(x)
	var span := _hit(x, _tau(x) * (0.5 if crit else 2.0))
	if crit:
		_crit(span)
	var all := _land([span])
	var tag := "crit" if crit else "D ≥ τ"
	assert_eq(_takes(all, x), 2 + _b(), "%s: X takes its own, the break's b and the arc's centre" % tag)
	assert_eq(_poisons(all, x), 2 + _b(), "%s: Poison on each of X's landings" % tag)
	assert_eq(_bursts(all, x), 1, "%s: one burst" % tag)
	assert_eq(_cold(x), _after_shatter(x, cold), "%s: one shatter spend" % tag)
	assert_eq(_charge(x), charge - 3, "%s: the released arc spends 1 per neighbour" % tag)
	for n in g.slice(1):
		assert_eq(_takes(all, n), 1, "%s: %s takes the arc's copy" % [tag, n.name])
		assert_eq(_charge(n), 1, "%s: %s takes the transferred stack" % [tag, n.name])


func test_a_breaking_hit_releases_the_trapped_arc() -> void:
	await _assert_released(false)


func test_a_breaking_crit_under_the_threshold_releases_the_trapped_arc() -> void:
	await _assert_released(true)


## X at 4T Charge (level 1, one short of level 2), W two hops out behind its
## first neighbour; [param rider] Charge on the breaker. W's landings.
func _two_hop(rider: int) -> int:
	var g := _star("", 3)
	var w := _at("W", g[1].global_position + Vector2(3000.0, 0.0))
	_w.link(g[1], w)
	await _own(g + [w])
	var x := g[0]
	_freeze(x)
	var t := _t(x)
	var four_t := int(pow(2, _edge.ladder_exponent)) * t
	_set_charge(x, four_t)
	assert_eq(_charge(x), four_t, "fixture: X holds 4T")
	assert_eq(_edge.level_of(TerrainRead.of(_c(x), x)), 1, "fixture: 4T is level 1")
	var riders := {_light.terrain: rider} if rider > 0 else {}
	var all := _land([_hit(x, _tau(x) * 2.0, riders)])
	assert_eq(_bursts(all, x), 1, "the ice shatters")
	return _takes(all, w)


func test_a_breaker_without_charge_releases_the_arc_as_it_sat() -> void:
	assert_eq(await _two_hop(0), 0, "a level-1 arc: the two-hop node takes 0")


func test_a_breakers_charge_feeds_the_arc_it_releases() -> void:
	assert_eq(await _two_hop(1), 1, "power read post-land: level 2, the two-hop node takes 1")


# 2b ────────────────────────────────────────────────────────────────────────────
func test_a_heat_rider_that_thaws_lifts_the_mute_with_no_shatter() -> void:
	var g := _star("", 2)
	await _own(g)
	var x := g[0]
	var e := 2
	_freeze(x, e)
	_set_charge(x, _t(x) + 1)
	var t0 := _tt(x)
	var all := _land([_hit(x, _tau(x) * 0.5, {_fire.terrain: e})])
	assert_false(_frozen(x), "the rider thawed X")
	assert_eq(_tt(x), t0 + e, "t rises by exactly the rider, once")
	assert_eq(_bursts(all, x), 0, "a thaw is no breaker: no burst")
	assert_eq(_takes(all, x), 2, "X arcs: its own landing and the centre")
	for n in g.slice(1):
		assert_eq(_takes(all, n), 1, "%s takes the arc's copy" % n.name)


# 2c ────────────────────────────────────────────────────────────────────────────
## Two identical breakers in one beat on the fixture of 2, [param swap]ped or not.
func _two_breakers(prefix: String, swap: bool) -> Array:
	var g: Array[SkillNode] = await _frozen_shocked(3, prefix)
	var x := g[0]
	var cold := _cold(x)
	var charge := _charge(x)
	var a := _hit(x, _tau(x) * 2.0)
	var b := _hit(x, _tau(x) * 2.0)
	var all := _land([b, a] if swap else [a, b])
	var out := [_takes(all, x), _bursts(all, x), _cold(x), _charge(x)]
	assert_eq(_cold(x), _after_shatter(x, cold), "one shatter spend")
	assert_eq(_charge(x), maxi(charge - 6, 0), "two releases' spends sum and clamp at 0")
	for n in g.slice(1):
		assert_eq(_takes(all, n), 2, "%s takes one copy per release" % n.name)
		out.append(_takes(all, n))
	return out


func test_two_breakers_shatter_once_and_release_once_each() -> void:
	var got: Array = await _two_breakers("a", false)
	assert_eq(got[0], 4 + 2 * _b(), "X: each breaker 1 + b, plus one centre per release")
	assert_eq(got[1], 1, "one burst")
	var swapped: Array = await _two_breakers("b", true)
	assert_eq(swapped, got, "swapping the two hits changes nothing")


# 3 ─────────────────────────────────────────────────────────────────────────────
## B Burning (Heat T + 1, excess 1) at the origin; F Frozen + Shocked inside B's
## disc, unlinked to it, with two neighbours far outside. The hit on B carries
## Charge 1. `[B, F, G1, G2, all]`.
func _disc_onto_frozen_shocked(dmg_of_tau: float, crit: bool) -> Array:
	var b := _at("B", Vector2.ZERO)
	var r := _r(b, 1)
	var f := _w.add_node(&"F", Vector2(r * 0.5, 0.0))
	f.global_position = Vector2(r * 0.5 + f.radius, 0.0)
	var g1 := _at("G1", Vector2(r * 4.0 + 6000.0, 0.0))
	var g2 := _at("G2", Vector2(r * 4.0 + 9000.0, 0.0))
	_w.link(f, g1)
	_w.link(f, g2)
	await _own([b, f, g1, g2])
	_set_t(b, _t(b) + 1)
	_freeze(f)
	_set_charge(f, _t(f) + 1)
	assert_true(_frozen(f), "fixture: F Frozen")
	var span := _hit(b, _tau(f) * dmg_of_tau, {_light.terrain: 1})
	if crit:
		_crit(span)
	return [b, f, g1, g2, _land([span])]


func test_an_under_threshold_disc_copy_is_absorbed_and_its_charge_joins_the_trap() -> void:
	var got: Array = await _disc_onto_frozen_shocked(0.5, false)
	var f: SkillNode = got[1]
	var all: Array = got[4]
	assert_eq(_takes(all, got[0]), 2, "fixture: B's disc went off")
	assert_eq(_takes(all, f), 0, "F absorbs the copy")
	assert_eq(_poisons(all, f), 0, "no Poison")
	assert_eq(_charge(f), _t(f) + 1 + 1, "the copy's Charge lands and joins the trapped store")
	assert_eq(_cold(f), _t(f) + 1, "its Cold unchanged")
	assert_eq(_bursts(all, f), 0, "no shatter")
	assert_eq(_takes(all, got[2]) + _takes(all, got[3]), 0, "no arc")


func _assert_copy_breaks(crit: bool) -> void:
	var got: Array = await _disc_onto_frozen_shocked(0.5 if crit else 2.0, crit)
	var f: SkillNode = got[1]
	var all: Array = got[4]
	var tag := "crit" if crit else "D ≥ τ"
	assert_eq(_takes(all, f), 2 + _b(), "%s: F takes the copy, the break's b and the arc's centre" % tag)
	assert_eq(_bursts(all, f), 1, "%s: one burst" % tag)
	assert_eq(_charge(f), _t(f) + 1 + 1 - 2, "%s: the copy's Charge lands once, then the arc spends 2" % tag)
	assert_eq(_takes(all, got[2]), 1, "%s: G1 takes the released arc's copy" % tag)
	assert_eq(_takes(all, got[3]), 1, "%s: G2 takes the released arc's copy" % tag)


func test_a_breaking_disc_copy_releases_the_arc() -> void:
	await _assert_copy_breaks(false)


func test_a_crit_disc_copy_under_the_threshold_releases_the_arc() -> void:
	await _assert_copy_breaks(true)


# 4 ─────────────────────────────────────────────────────────────────────────────
func test_an_arc_copy_onto_a_frozen_neighbour_is_absorbed_and_still_paid_for() -> void:
	var g := _star("", 3)
	await _own(g)
	var s := g[0]
	var z := g[1]
	_freeze(z)
	_set_charge(s, _t(s) + 1)
	var charge := _charge(s)
	var all := _land([_hit(s, _tau(z) * 0.5)])
	assert_eq(_takes(all, z), 0, "Z absorbs the copy")
	assert_eq(_poisons(all, z), 0, "no Poison on Z")
	assert_eq(_charge(z), 1, "the transferred stack lands on Z anyway")
	assert_eq(_takes(all, s), 2, "S: its own and the centre")
	for n in g.slice(2):
		assert_eq(_takes(all, n), 1, "%s takes the arc's copy" % n.name)
	assert_eq(_charge(s), charge - 3, "the arc pays 1 for Z too")


func test_a_disc_copy_onto_a_frozen_node_is_absorbed_and_still_paid_for() -> void:
	var b := _at("B", Vector2.ZERO)
	var r := _r(b, 1)
	var z := _at("Z", Vector2.ZERO)
	z.global_position = Vector2(r * 0.5 + z.radius, 0.0)
	await _own([b, z])
	_set_t(b, _t(b) + 1)
	_freeze(z)
	var heat := _tt(b)
	var all := _land([_hit(b, _tau(z) * 0.5)])
	assert_eq(_takes(all, z), 0, "Z absorbs the copy")
	assert_eq(_poisons(all, z), 0, "no Poison on Z")
	assert_eq(_tt(b), heat - 1, "the disc still spends 1 Heat for Z")


## X Burning and Shocked, Z its neighbour inside the disc and Frozen.
func _both_onto_frozen(dmg_of_tau: float) -> Array:
	var x := _at("X", Vector2.ZERO)
	var r := _r(x, 1)
	var z := _at("Z", Vector2.ZERO)
	z.global_position = Vector2(-(r * 0.5 + z.radius), 0.0)
	_w.link(x, z)
	await _own([x, z])
	_set_t(x, _t(x) + 1)
	_set_charge(x, _t(x) + 1)
	_freeze(z)
	var cold := _cold(z)
	var all := _land([_hit(x, _tau(z) * dmg_of_tau)])
	return [z, cold, all]


func test_a_frozen_node_in_both_reaches_absorbs_both_copies_under_the_threshold() -> void:
	var got: Array = await _both_onto_frozen(0.5)
	assert_eq(_takes(got[2], got[0]), 0, "both copies absorbed")
	assert_eq(_bursts(got[2], got[0]), 0, "no shatter")


func test_a_frozen_node_in_both_reaches_broken_by_both_copies_shatters_once() -> void:
	var got: Array = await _both_onto_frozen(2.0)
	var z: SkillNode = got[0]
	assert_eq(_takes(got[2], z), 2 + 2 * _b(), "each copy lands and takes the break's b")
	assert_eq(_bursts(got[2], z), 1, "one burst")
	assert_eq(_cold(z), _after_shatter(z, int(got[1])), "one shatter spend")


# 4b ────────────────────────────────────────────────────────────────────────────
func test_an_absorbed_disc_copys_heat_thaws_with_no_shatter() -> void:
	var b := _at("B", Vector2.ZERO)
	var e := 2
	var h := e + 1
	var r := _r(b, 1)
	var z := _at("Z", Vector2.ZERO)
	z.global_position = Vector2(r * 0.5 + z.radius, 0.0)
	await _own([b, z])
	_set_t(b, _t(b) + 1)
	_freeze(z, e)
	var cold := _cold(z)
	var t0 := _tt(z)
	var all := _land([_hit(b, _tau(z) * 0.5, {_fire.terrain: h})])
	assert_eq(_takes(all, z), 0, "Z absorbs the copy")
	assert_eq(_poisons(all, z), 0, "no Poison")
	assert_eq(_tt(z), t0 + h, "its Heat lands once")
	assert_false(_frozen(z), "Z thawed")
	assert_eq(_bursts(all, z), 0, "a thaw is no breaker: no burst")
	assert_eq(cold - h, _cold(z), "no shatter spend")


# 5 ─────────────────────────────────────────────────────────────────────────────
func test_a_cold_rider_on_a_shocked_node_lays_cold_on_every_arc_target_once() -> void:
	var g := _star("", 2)
	await _own(g)
	var s := g[0]
	_set_charge(s, _t(s) + 1)
	var c := 1
	_land([_hit(s, 1.0, {_ice.terrain: c})])
	assert_eq(_tt(s), -c, "S: c once, not once per landing")
	for n in g.slice(1):
		assert_eq(_tt(n), -int(ceil(c * _edge.share)), "%s: ceil(c × share)" % n.name)


func test_a_cold_rider_on_a_burning_node_that_stays_burning_lays_cold_over_the_disc() -> void:
	var b := _at("B", Vector2.ZERO)
	var c := 1
	var r := _r(b, 1)
	var p := _at("P", Vector2.ZERO)
	p.global_position = Vector2(r * 0.5 + p.radius, 0.0)
	await _own([b, p])
	_set_t(b, _t(b) + 1 + c)
	var heat := _tt(b)
	var all := _land([_hit(b, 1.0, {_ice.terrain: c})])
	assert_eq(_takes(all, p), 1, "the disc reaches P")
	assert_eq(_tt(p), -c, "P: c Cold")
	assert_eq(_tt(b), heat - c - 1, "B: c once, then the disc's spend")


func test_a_cold_rider_that_nets_burning_to_t_puts_it_out() -> void:
	var b := _at("B", Vector2.ZERO)
	var r := _r(b, 1)
	var p := _at("P", Vector2.ZERO)
	p.global_position = Vector2(r * 0.5 + p.radius, 0.0)
	await _own([b, p])
	_set_t(b, _t(b) + 1)
	var all := _land([_hit(b, 1.0, {_ice.terrain: 1})])
	assert_eq(_takes(all, b), 1, "no disc: B takes 1")
	assert_eq(_takes(all, p), 0, "no disc: P untouched")
	assert_eq(_tt(b), _t(b), "no spend")


func test_a_cold_rider_that_freezes_a_shocked_node_mutes_it() -> void:
	var g := _star("", 2)
	await _own(g)
	var s := g[0]
	_set_t(s, -_t(s))
	_set_charge(s, _t(s) + 1)
	var charge := _charge(s)
	var all := _land([_hit(s, _tau(s) * 0.5, {_ice.terrain: 1})])
	assert_true(_frozen(s), "the rider froze S")
	assert_eq(_takes(all, s), 1, "muted: S takes 1")
	assert_eq(_charge(s), charge, "no Charge spent")
	for n in g.slice(1):
		assert_eq(_takes(all, n), 0, "%s untouched" % n.name)


# 6 ─────────────────────────────────────────────────────────────────────────────
## X Burning (Heat T, +1 from the hit: excess 1) and Shocked (level 1); N a
## neighbour inside the disc, O a neighbour far outside it, P a non-neighbour
## inside it. `[X, N, O, P, all]`.
func _whole_hit(dmg: float) -> Array:
	var x := _w.add_node(&"X", Vector2.ZERO)
	var r := _r(x, 1)
	var n := _at("N", Vector2.ZERO)
	n.global_position = Vector2(-(r * 0.5 + n.radius), 0.0)
	var o := _at("O", Vector2(r * 4.0 + 6000.0, 0.0))
	var p := _at("P", Vector2.ZERO)
	p.global_position = Vector2(0.0, r * 0.5 + p.radius)
	_w.link(x, n)
	_w.link(x, o)
	await _own([x, n, o, p])
	_set_t(x, _t(x))
	_set_charge(x, _t(x) + 1)
	return [x, n, o, p, _land([_hit(x, dmg, {_fire.terrain: 1})])]


func test_burning_and_shocked_concatenated_the_whole_hit_counts() -> void:
	_dedupe(false)
	var got: Array = await _whole_hit(1.0)
	var x: SkillNode = got[0]
	var all: Array = got[4]
	assert_eq(_takes(all, x), 3, "X: 1 + 1 per channel")
	assert_eq(_takes(all, got[1]), 2, "N, both reach: 2")
	var marks := {}
	for h: HitInstance in _on(all, got[1]):
		if h is DamageInstance and h.blast_mark != null:
			marks[h.blast_mark] = true
	assert_eq(marks.size(), 2, "N: one mark per go-off (a blast row each)")
	assert_eq(_takes(all, got[2]), 1, "O, arc only: 1")
	assert_eq(_takes(all, got[3]), 1, "P, disc only: 1")
	assert_eq(_tt(x), _t(x) + 1 - 2, "X: the Heat rider once, then the disc's spend for N and P")
	for b: SkillNode in [got[1], got[2], got[3]]:
		assert_eq(_tt(b), 1, "%s: Heat rises by exactly 1" % b.name)


func test_burning_and_shocked_deduped_merges_the_both_reach_neighbour_only() -> void:
	_dedupe(true)
	var d := 2.0
	var got: Array = await _whole_hit(d)
	var all: Array = got[4]
	assert_eq(_takes(all, got[0]), 3, "X still takes 3: the hit node is never merged")
	var on_n := _on(all, got[1]).filter(func(h: HitInstance) -> bool: return h is DamageInstance)
	assert_eq(on_n.size(), 1, "N: one landing")
	if on_n.size() == 1:
		assert_eq(on_n[0].amount, 2.0 * d, "at share × 2: 2D")
	var poison := _on(all, got[1]).filter(func(h: HitInstance) -> bool:
		return h is StatusInstance and h.def.id == &"poison")
	assert_eq(poison.size(), 1, "one Poison row")
	if poison.size() == 1:
		assert_eq(poison[0].power, 2.0 * _POISON, "2p")
	assert_eq(_tt(got[1]), 1, "N's Heat still rises by 1")
	assert_eq(_takes(all, got[2]), 1, "O unchanged")
	assert_eq(_takes(all, got[3]), 1, "P unchanged")


# 7 ─────────────────────────────────────────────────────────────────────────────
## N Frozen at Cold T + e holding 3 Catalyst, alone (its anchors far out).
func _catalysed(pos := Vector2.ZERO) -> SkillNode:
	var n := _at("N", pos, 3)
	await _own([n])
	_freeze(n, 2)
	_c(n).apply_status(_CATALYST, 3.0)
	assert_eq(int(_c(n).get_status_power(&"catalyst")), 3, "fixture: N holds 3 Catalyst")
	assert_eq(_CATALYST.ratio_in, _CATALYST.ratio_out, "fixture: Catalyst trades 1 : 1")
	return n


func test_catalyst_under_frozen_makes_a_heat_hit_thaw_harder() -> void:
	var n: SkillNode = await _catalysed()
	var t0 := _tt(n)
	_land([_hit(n, _tau(n) * 0.5, {_fire.terrain: 1})])
	assert_eq(_tt(n), t0 + 4, "Heat 1 plus the 3 converted")


func test_catalyst_under_frozen_makes_a_cold_hit_deepen() -> void:
	var n: SkillNode = await _catalysed()
	var cold := _cold(n)
	var c := 1
	_land([_hit(n, _tau(n) * 0.5, {_ice.terrain: c})])
	assert_eq(_cold(n), cold + c + 3, "Cold c plus the 3 converted")


func test_catalyst_under_frozen_converts_with_an_absorbed_copys_cold() -> void:
	var b := _at("B", Vector2.ZERO)
	var c := 1
	var r := _r(b, 1)
	var n: SkillNode = await _catalysed(Vector2.ZERO)
	n.global_position = Vector2(r * 0.5 + n.radius, 0.0)
	await _own([b])
	_set_t(b, _t(b) + 1 + c)
	var cold := _cold(n)
	var all := _land([_hit(b, _tau(n) * 0.5, {_ice.terrain: c})])
	assert_eq(_takes(all, n), 0, "N absorbs the copy")
	assert_eq(_poisons(all, n), 0, "no Poison")
	assert_eq(_cold(n), cold + c + 3, "the copy's Cold lands and converts the store")
	assert_eq(int(_c(n).get_status_power(&"catalyst")), 0, "Catalyst 0")

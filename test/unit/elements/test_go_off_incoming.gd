extends GutTest

## The incoming party (ADR 0098): a head's [GoOffSource] — a blade vertex's
## copy or a cast's shape — goes off at the hit node with the node's own band
## as ONE go-off per element. Every primed party pays its own solo cost (the
## floor plus 1 per node inside its own reach, measured from the hit node; a
## shape pays nothing), and the go-off lands one effect on every node it
## reaches (+1 of the element's terrain, combined reach included) whenever a
## party is primed. The cost never funds the effect.
##
## Copies are filled from a primed source node as a swing fills
## ([BladeVertexFill]); counts are relative to T, never literals.

const _FAR := 20000.0

## A contact whose second store is a real blade copy, handed as
## [BladeDamageInstance] hands its own.
class _Contact:
	extends DamageInstance
	var blade: BladeState = null

	func go_off_source() -> GoOffSource:
		if blade == null:
			return null
		var s := blade
		return GoOffSource.new(s, 1, s.copy_read(1),
				func(e: Element, n: int) -> void: s.spend_copy(1, e, n))


var _w: TestWorld
var _red: Entity
var _blue: Entity
var _fire: Element
var _light: Element
var _disc: DiscGoOff
var _edge: EdgeGoOff
var _was: Array = []
var _sources := 0


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_red = _w.add_entity("Red")
	_blue = _w.add_entity("Blue")
	await get_tree().process_frame
	_fire = ElementRoster.shared().by_id(&"fire")
	_light = ElementRoster.shared().by_id(&"lightning")
	_disc = _fire.bands[0].go_off as DiscGoOff
	_edge = _light.bands[0].go_off as EdgeGoOff
	_was = [_disc.damage_per_power, _disc.floor_when_unreached, _edge.floor_when_unreached]
	_disc.damage_per_power = 0.0
	_sources = 0


func after_each() -> void:
	_disc.damage_per_power = _was[0]
	_disc.floor_when_unreached = _was[1]
	_edge.floor_when_unreached = _was[2]
	CombatWorld.reset_live()


# --- fixture -----------------------------------------------------------------

## A node at [param pos] with one far anchor of its own (a T without company).
func _at(id: String, pos: Vector2) -> SkillNode:
	var n := _w.add_node(StringName(id), pos)
	_w.link(n, _w.add_node(StringName(id + "_anchor"), pos + Vector2(0.0, _FAR)))
	return n


## A hub X at [param origin] with [param inner] neighbours 3000 px out, each
## with [param outer] children of its own 6000 px out: `[X, inner..., outer...]`.
func _tree(prefix: String, origin: Vector2, inner: int, outer: int) -> Array[SkillNode]:
	var x := _w.add_node(StringName(prefix + "X"), origin)
	var ins: Array[SkillNode] = []
	var outs: Array[SkillNode] = []
	for i in inner:
		var a := TAU * i / inner
		var n := _w.add_node(StringName("%sI%d" % [prefix, i]), origin + Vector2.from_angle(a) * 3000.0)
		_w.link(x, n)
		ins.append(n)
		for j in outer:
			var o := _w.add_node(StringName("%sO%d_%d" % [prefix, i, j]),
					origin + Vector2.from_angle(a + 0.2 * j) * 6000.0)
			_w.link(n, o)
			outs.append(o)
	var out: Array[SkillNode] = [x]
	out.append_array(ins)
	out.append_array(outs)
	await _own(out)
	return out


## A hub X with [param k] linked neighbours fanned at 60 px steps out from it
## (the disc's reach splits them by distance), each with a far anchor.
func _fan(prefix: String, origin: Vector2, k: int) -> Array[SkillNode]:
	var x := _w.add_node(StringName(prefix + "X"), origin)
	var out: Array[SkillNode] = [x]
	for i in k:
		var n := _at("%sF%d" % [prefix, i], origin + Vector2.from_angle(TAU * i / k) * (60.0 * (i + 1)))
		_w.link(x, n)
		out.append(n)
	await _own(out)
	return out


func _own(nodes: Array) -> void:
	_w.allocate(_red, nodes)
	await get_tree().process_frame


func _c(n: SkillNode) -> NodeCombat:
	return CombatWorld.live().combat_for(n) as NodeCombat


func _read(n: SkillNode) -> TerrainRead:
	return TerrainRead.of(_c(n), n)


func _t(n: SkillNode) -> int:
	return _c(n).terrain_threshold()


func _heat(n: SkillNode) -> int:
	return _c(n).terrain_t()


func _charge(n: SkillNode) -> int:
	return _c(n).charge()


func _set_charge(n: SkillNode, to: int) -> void:
	_c(n).add_terrain(_light, to - _charge(n))


func _set_t(n: SkillNode, to: int) -> void:
	_c(n).add_terrain(_fire, to - _heat(n))


## A Charge count on [param n]'s T at arc level 1, at least [param least].
func _l1(n: SkillNode, least := 4) -> int:
	return clampi(maxi(_t(n) + 1, least), _t(n) + 1, 4 * _t(n))


## A blade whose vertex 1 copies a fresh source node primed by [param prime]
## (`(SkillNode) -> void`), filled as a swing fills.
func _blade(prime: Callable) -> BladeState:
	_sources += 1
	var pivot := _at("pivot%d" % _sources, Vector2(-90000.0, 9000.0 * _sources))
	var src := _at("src%d" % _sources, Vector2(-60000.0, 9000.0 * _sources))
	_w.allocate(_blue, [pivot, src])
	await get_tree().process_frame
	prime.call(src)
	var positions: Array[Vector2] = [Vector2(-400, 0), Vector2(430, 0)]
	var radii: Array[float] = [16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1)]
	var s := BladeState.build(positions, 0, edges, radii)
	var nodes: Array[SkillNode] = [pivot, src]
	BladeVertexFill.new().fill(s, nodes)
	return s


## A Lightning copy at [param count] Charge (count chosen off the source's T by
## [param of_t]: `(t: int) -> int`).
func _charged(of_t: Callable) -> BladeState:
	return await _blade(func(src: SkillNode) -> void: _set_charge(src, int(of_t.call(_t(src)))))


func _burning(of_t: Callable) -> BladeState:
	return await _blade(func(src: SkillNode) -> void: _set_t(src, int(of_t.call(_t(src)))))


func _head(d: DamageInstance, at: SkillNode) -> Array[HitInstance]:
	d.amount = 1.0
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	d.target = at
	d.attacker = _blue
	d.schedule_index = 0
	d.structural_key = 0.0
	var span: Array[HitInstance] = [d]
	return span


func _contact(s: BladeState, at: SkillNode) -> Array[HitInstance]:
	var d := _Contact.new()
	d.blade = s
	return _head(d, at)


func _cast(at: SkillNode, e: Element, points: int) -> Array[HitInstance]:
	var d := DamageInstance.new()
	d.cast_shape = e
	d.cast_shape_points = points
	return _head(d, at)


func _land(span: Array[HitInstance]) -> Array[HitInstance]:
	var all: Array[HitInstance] = span.duplicate()
	HitGather.stage_one(span.duplicate(), CombatWorld.live(), HitQueue.over(all))
	return all


func _marks(all: Array, centre: SkillNode) -> Array:
	var out: Array = []
	for h: HitInstance in all:
		if h is DamageInstance and h.blast_mark != null and h.blast_mark.centre == centre \
				and not out.has(h.blast_mark):
			out.append(h.blast_mark)
	return out


func _copies_of(all: Array, mark: BlastMark) -> Array:
	var out: Array = []
	for h: HitInstance in all:
		if h is DamageInstance and h.blast_mark == mark and h.target != mark.centre and not out.has(h.target):
			out.append(h.target)
	return out


func _ball(x: SkillNode, hops: int) -> Array:
	var mirror: GraphMirror = x.get_graph().navigator
	return mirror.nodes_within(x, hops).keys().filter(func(n: SkillNode) -> bool: return n != x)


func _snap(nodes: Array, of: Callable) -> Dictionary:
	var out := {}
	for n: SkillNode in nodes:
		out[n] = int(of.call(n))
	return out


func _solo_disc(x: SkillNode, read: TerrainRead) -> Array:
	var out: Array = []
	for r in _disc.fire_in(null, x, read).reached:
		out.append(r.node)
	return out


# 1 ─────────────────────────────────────────────────────────────────────────────
func test_1_a_shocked_copy_alone_pays_its_floor_and_ring_and_charges_the_ring() -> void:
	var g := await _tree("a", Vector2.ZERO, 3, 0)
	var x := g[0]
	var s := await _charged(func(t: int) -> int: return clampi(t + 4, t + 1, 4 * t))
	var c0 := s.vertex_charge[1]
	assert_eq(_edge.level_of(s.copy_read(1)), 1, "fixture: the copy arcs at L1")
	var ring := _ball(x, 1)
	assert_eq(ring.size(), 3, "fixture: 3 neighbours")
	var before := _snap(ring, _charge)
	var hub := _charge(x)
	_land(_contact(s, x))
	assert_eq(s.vertex_charge[1], maxi(0, c0 - _edge.void_floor - 3), "the copy pays its floor and its ring")
	for n: SkillNode in ring:
		assert_eq(_charge(n), before[n] + 1, "%s: +1 Charge" % n.name)
	assert_eq(_charge(x), hub, "the unprimed hit node pays nothing")


# 2 ─────────────────────────────────────────────────────────────────────────────
func test_2_a_copy_and_a_shocked_node_each_pay_solo_and_all_nine_take_one() -> void:
	var g := await _tree("b", Vector2.ZERO, 3, 2)
	var x := g[0]
	_set_charge(x, _l1(x))
	var h0 := _charge(x)
	assert_eq(_edge.level_of(_read(x)), 1, "fixture: H at L1")
	var s := await _charged(func(t: int) -> int: return clampi(t + 4, t + 1, 4 * t))
	var c0 := s.vertex_charge[1]
	assert_eq(_edge.level_of(s.copy_read(1)), 1, "fixture: the copy at L1")
	var reach := _ball(x, 2)
	assert_eq(reach.size(), 9, "fixture: 3 inner, 6 outer")
	var before := _snap(reach, _charge)
	var all := _land(_contact(s, x))
	var marks := _marks(all, x)
	assert_eq(marks.size(), 1, "one go-off")
	if not marks.is_empty():
		assert_eq((marks[0] as BlastMark).power, 2, "the combined reach is L2")
	assert_eq(s.vertex_charge[1], maxi(0, c0 - _edge.void_floor - 3), "the blade pays 1 + its own ring")
	assert_eq(_charge(x), maxi(0, h0 - _edge.void_floor - 3), "H pays 1 + its own ring")
	for n: SkillNode in reach:
		assert_eq(_charge(n), before[n] + 1, "%s: exactly +1 Charge" % n.name)


# 3 ─────────────────────────────────────────────────────────────────────────────
func test_3_a_short_payer_clamps_at_zero_and_the_effect_lands_whole() -> void:
	var g := await _tree("c", Vector2.ZERO, 8, 0)
	var x := g[0]
	var s := await _charged(func(t: int) -> int: return t + 1)
	assert_eq(_edge.level_of(s.copy_read(1)), 1, "fixture: L1")
	assert_lt(s.vertex_charge[1], _edge.void_floor + 8, "fixture: the bill exceeds the copy")
	var ring := _ball(x, 1)
	var before := _snap(ring, _charge)
	_land(_contact(s, x))
	assert_eq(s.vertex_charge[1], 0, "the copy pays what it has")
	for n: SkillNode in ring:
		assert_eq(_charge(n), before[n] + 1, "%s: +1 Charge all the same" % n.name)


# 4 ─────────────────────────────────────────────────────────────────────────────
func test_4_each_contact_reads_the_copys_level_from_its_current_count() -> void:
	var g := await _tree("d", Vector2.ZERO, 3, 1)
	var x := g[0]
	var s := await _charged(func(t: int) -> int: return 9 * t)
	assert_eq(_edge.level_of(s.copy_read(1)), 2, "fixture: the copy starts at L2")
	var levels: Array[int] = []
	for i in 8:
		var level := _edge.level_of(s.copy_read(1))
		var c0 := s.vertex_charge[1]
		var marks := _marks(_land(_contact(s, x)), x)
		if level == 0:
			assert_true(marks.is_empty(), "a copy at or under T goes off no more")
			assert_eq(s.vertex_charge[1], c0, "and pays nothing")
			break
		levels.append(level)
		assert_eq(marks.size(), 1, "contact %d goes off" % i)
		if not marks.is_empty():
			assert_eq((marks[0] as BlastMark).power, level, "contact %d at the copy's current level" % i)
		assert_eq(s.vertex_charge[1], maxi(0, c0 - _edge.void_floor - _ball(x, level).size()),
				"contact %d pays its floor and its own level's reach" % i)
	assert_true(levels.has(2) and levels.has(1), "the level dropped across the swing: %s" % [levels])


# 5 ─────────────────────────────────────────────────────────────────────────────
func test_5_a_burning_copy_on_a_burning_node_is_one_disc_each_party_pays_solo() -> void:
	var g := await _fan("e", Vector2.ZERO, 24)
	var x := g[0]
	_set_t(x, _t(x) + 4)
	var s := await _burning(func(t: int) -> int: return t + 9)
	var excess := _disc.power_at(x, _read(x))
	var copy_power := _disc.power_at(null, s.copy_read(1))
	assert_gt(excess, 0, "fixture: X Burning")
	assert_gt(copy_power, 0, "fixture: the copy Burning")
	var node_solo := _solo_disc(x, _read(x))
	var copy_solo := _solo_disc(x, s.copy_read(1))
	var t0 := _heat(x)
	var c0 := s.vertex_t[1]
	var everyone := g.slice(1)
	var before := _snap(everyone, _heat)
	var all := _land(_contact(s, x))
	var marks := _marks(all, x)
	assert_eq(marks.size(), 1, "one disc")
	if marks.is_empty():
		return
	var mark: BlastMark = marks[0]
	assert_almost_eq(mark.reach, _disc.shape_disc_radius(float(copy_power), float(excess), x.radius), 0.001,
			"the combined radius")
	var reached := _copies_of(all, mark)
	assert_gt(reached.size(), maxi(node_solo.size(), copy_solo.size()), "fixture: the combined disc reaches further")
	assert_eq(_heat(x), maxi(0, t0 - _disc.void_floor - node_solo.size()), "X pays 1 + its own disc")
	assert_eq(s.vertex_t[1], maxi(0, c0 - _disc.void_floor - copy_solo.size()), "the copy pays 1 + its own disc")
	for n: SkillNode in reached:
		assert_eq(_heat(n), before[n] + 1, "%s: +1 Heat" % n.name)


# 6 ─────────────────────────────────────────────────────────────────────────────
func test_6_a_shape_alone_reaches_and_changes_no_terrain() -> void:
	var g := await _tree("f", Vector2.ZERO, 3, 1)
	var x := g[0]
	var charge := _snap(g, _charge)
	var heat := _snap(g, _heat)
	var all := _land(_cast(x, _light, 1))
	var marks := _marks(all, x)
	assert_eq(marks.size(), 1, "the shape reaches")
	if not marks.is_empty():
		assert_eq(_copies_of(all, marks[0]).size(), 3, "its L1 ring takes payload copies")
	for n: SkillNode in g:
		assert_eq(_charge(n), charge[n], "%s: no Charge moves" % n.name)
		assert_eq(_heat(n), heat[n], "%s: no Heat moves" % n.name)


# 7 ─────────────────────────────────────────────────────────────────────────────
func test_7_a_shape_on_a_shocked_node_charges_the_whole_combined_reach() -> void:
	var g := await _tree("g", Vector2.ZERO, 3, 1)
	var x := g[0]
	_set_charge(x, _l1(x))
	var h0 := _charge(x)
	var reach := _ball(x, 2)
	var before := _snap(reach, _charge)
	_land(_cast(x, _light, 1))
	assert_eq(_charge(x), maxi(0, h0 - _edge.void_floor - 3), "the node pays 1 + its own L1 ring")
	for n: SkillNode in reach:
		assert_eq(_charge(n), before[n] + 1, "%s: +1 Charge, the outer ring included" % n.name)


# 8 ─────────────────────────────────────────────────────────────────────────────
func test_8_a_copy_and_a_shape_at_equal_levels_differ_only_in_the_incoming_cost() -> void:
	var p := await _tree("p", Vector2.ZERO, 3, 1)
	var q := await _tree("q", Vector2(0.0, 40000.0), 3, 1)
	_set_charge(p[0], _l1(p[0]))
	_set_charge(q[0], _l1(q[0]))
	var s := await _charged(func(t: int) -> int: return clampi(t + 4, t + 1, 4 * t))
	var c0 := s.vertex_charge[1]
	assert_eq(_edge.level_of(s.copy_read(1)), EdgeGoOff.level_for_points(1), "fixture: equal levels")
	var bp := _snap(p, _charge)
	var bq := _snap(q, _charge)
	var ap := _land(_contact(s, p[0]))
	var aq := _land(_cast(q[0], _light, 1))
	var mp := _marks(ap, p[0])
	var mq := _marks(aq, q[0])
	assert_eq([mp.size(), mq.size()], [1, 1], "one go-off each")
	if mp.size() == 1 and mq.size() == 1:
		assert_eq(_copies_of(ap, mp[0]).size(), _copies_of(aq, mq[0]).size(), "the same reach")
	for i in p.size():
		assert_eq(_charge(p[i]) - bp[p[i]], _charge(q[i]) - bq[q[i]], "%s / %s: the same change" % [p[i].name, q[i].name])
	assert_eq(s.vertex_charge[1], maxi(0, c0 - _edge.void_floor - 3), "the copy pays; the shape paid nothing")


# 9 ─────────────────────────────────────────────────────────────────────────────
func test_9_a_burning_copy_on_a_shocked_node_is_two_go_offs_each_its_own_bill() -> void:
	var g := await _fan("h", Vector2.ZERO, 24)
	var x := g[0]
	_set_charge(x, _l1(x))
	var h0 := _charge(x)
	var s := await _burning(func(t: int) -> int: return t + 9)
	var copy_solo := _solo_disc(x, s.copy_read(1))
	assert_gt(copy_solo.size(), 0, "fixture: the copy's disc reaches")
	var ring := _ball(x, 1)
	var c0 := s.vertex_t[1]
	var charge := _snap(g.slice(1), _charge)
	var heat := _snap(g.slice(1), _heat)
	var all := _land(_contact(s, x))
	assert_eq(_marks(all, x).size(), 2, "two go-offs: the node's arc and the copy's disc")
	assert_eq(_charge(x), maxi(0, h0 - _edge.void_floor - ring.size()), "the node pays its arc's bill")
	assert_eq(s.vertex_t[1], maxi(0, c0 - _disc.void_floor - copy_solo.size()), "the copy pays its disc's bill")
	for n: SkillNode in ring:
		assert_eq(_charge(n), charge[n] + 1, "%s: the arc's +1 Charge" % n.name)
	for n: SkillNode in copy_solo:
		assert_eq(_heat(n), heat[n] + 1, "%s: the disc's +1 Heat" % n.name)


# 10 ────────────────────────────────────────────────────────────────────────────
func test_10_a_copy_reaching_nobody_pays_its_floor_while_the_knob_is_on() -> void:
	var lone := _at("lone", Vector2.ZERO)
	await _own([lone])
	var s := await _burning(func(t: int) -> int: return t + 2)
	assert_true(_solo_disc(lone, s.copy_read(1)).is_empty(), "fixture: the copy's disc reaches nobody")
	var c0 := s.vertex_t[1]
	_land(_contact(s, lone))
	assert_eq(s.vertex_t[1], maxi(0, c0 - _disc.void_floor), "on: the floor")
	_disc.floor_when_unreached = false
	var c1 := s.vertex_t[1]
	assert_gt(_disc.power_at(null, s.copy_read(1)), 0, "fixture: the copy is still Burning")
	_land(_contact(s, lone))
	assert_eq(s.vertex_t[1], c1, "off: nothing")


func test_10b_a_burning_node_and_copy_reaching_nobody_each_void_their_floor() -> void:
	var lone := _at("lone", Vector2.ZERO)
	await _own([lone])
	_set_t(lone, _t(lone) + 1)
	var s := await _burning(func(t: int) -> int: return t + 1)
	assert_true(_solo_disc(lone, s.copy_read(1)).is_empty(), "fixture: the copy's disc reaches nobody")
	var t0 := _heat(lone)
	var c0 := s.vertex_t[1]
	_land(_contact(s, lone))
	assert_eq(_heat(lone), maxi(0, t0 - _disc.void_floor), "the node voids its floor")
	assert_eq(s.vertex_t[1], maxi(0, c0 - _disc.void_floor), "the copy voids its own")

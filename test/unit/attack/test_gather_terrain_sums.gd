extends GutTest

## Stage one's per-beat terrain sums ([member HitInstance.terrain_sums],
## [CombatWorld.TerrainBook] layout): per element the applied amounts produced,
## effect, voided (node-paid), voided incoming (copy-paid, off the graph) and
## onto the opposite side. Every case also reconciles them with the netted
## per-node deltas ([member HitInstance.terrain_ops]): per element,
## Δtotal = produced + effect − voided − onto_opposite − from_opposite.
## Fixture shared with test_go_off_incoming.gd; counts are relative to T.

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



const _B := CombatWorld.TerrainBook
const _F := CombatWorld.TerrainBook.Field


func _all_nodes() -> Array:
	return _w.graph.get_skill_nodes()


func _pre() -> Dictionary:
	var out := {}
	for n: SkillNode in _all_nodes():
		out[n] = [_heat(n), _charge(n)]
	return out


## The beat's sums (its first head's).
func _sums(all: Array) -> PackedInt32Array:
	for h: HitInstance in all:
		if not h.terrain_sums.is_empty():
			return h.terrain_sums
	return PackedInt32Array()


func _v(sums: PackedInt32Array, row: int, field: int) -> int:
	return _B.read_of(sums, row, field)


## Δtotal per element from the recorded ops and from the live board both, each
## against the sums.
func _reconcile(all: Array, pre: Dictionary) -> void:
	var sums := _sums(all)
	var d_ops := [0, 0, 0]
	for h: HitInstance in all:
		for op: Array in h.terrain_ops:
			var was: Array = pre.get(op[0], [0, 0])
			var t0 := int(was[0])
			var t1 := t0 + int(op[1])
			d_ops[0] += maxi(t1, 0) - maxi(t0, 0)
			d_ops[1] += maxi(-t1, 0) - maxi(-t0, 0)
			d_ops[2] += int(op[2])
	var d_board := [0, 0, 0]
	for n: SkillNode in pre:
		var was: Array = pre[n]
		d_board[0] += maxi(_heat(n), 0) - maxi(int(was[0]), 0)
		d_board[1] += maxi(-_heat(n), 0) - maxi(-int(was[0]), 0)
		d_board[2] += _charge(n) - int(was[1])
	for row in 3:
		var other := 1 - row if row < 2 else -1
		var expect := _v(sums, row, _F.PRODUCED) + _v(sums, row, _F.EFFECT) \
				- _v(sums, row, _F.VOIDED) - _v(sums, row, _F.ONTO_OPPOSITE) \
				- (_v(sums, other, _F.ONTO_OPPOSITE) if other >= 0 else 0)
		assert_eq(d_ops[row], expect, "row %d: the sums reconcile with the netted ops" % row)
		assert_eq(d_board[row], expect, "row %d: the sums reconcile with the board" % row)


# ─────────────────────────────────────────────────────────────────────────────
func test_a_solo_lightning_go_off_on_a_degree_3_node_voids_1_plus_3_and_lands_3() -> void:
	var g := await _tree("a", Vector2.ZERO, 3, 0)
	var x := g[0]
	_set_charge(x, _l1(x, 4))
	assert_eq(_edge.level_of(_read(x)), 1, "fixture: L1")
	var pre := _pre()
	var all := _land(_head(DamageInstance.new(), x))
	var sums := _sums(all)
	assert_eq(_v(sums, _B.CHARGE, _F.VOIDED), _edge.void_floor + 3, "cost: floor + 3")
	assert_eq(_v(sums, _B.CHARGE, _F.EFFECT), 3, "effect: 3")
	assert_eq(_v(sums, _B.CHARGE, _F.PRODUCED), 0, "no rider")
	_reconcile(all, pre)


func test_the_combined_example_voids_8_and_lands_9() -> void:
	var g := await _tree("b", Vector2.ZERO, 3, 2)
	var x := g[0]
	_set_charge(x, _l1(x))
	var s := await _charged(func(t: int) -> int: return clampi(t + 4, t + 1, 4 * t))
	assert_eq(_edge.level_of(s.copy_read(1)), 1, "fixture: the copy at L1")
	assert_gte(_charge(x), _edge.void_floor + 3, "fixture: the node covers its bill")
	assert_gte(s.vertex_charge[1], _edge.void_floor + 3, "fixture: the copy covers its bill")
	var pre := _pre()
	var all := _land(_contact(s, x))
	var sums := _sums(all)
	assert_eq(_v(sums, _B.CHARGE, _F.VOIDED) + _v(sums, _B.CHARGE, _F.VOIDED_INCOMING), 8, "8 voided")
	assert_eq(_v(sums, _B.CHARGE, _F.VOIDED_INCOMING), _edge.void_floor + 3, "the copy's part is off the graph")
	assert_eq(_v(sums, _B.CHARGE, _F.EFFECT), 9, "9 landed")
	_reconcile(all, pre)


func test_a_short_payer_copy_voids_what_it_has_and_lands_8() -> void:
	var g := await _tree("c", Vector2.ZERO, 8, 0)
	var x := g[0]
	var s := await _charged(func(t: int) -> int: return t + 1)
	var c0 := s.vertex_charge[1]
	assert_lt(c0, _edge.void_floor + 8, "fixture: the bill exceeds the copy")
	var pre := _pre()
	var all := _land(_contact(s, x))
	var sums := _sums(all)
	assert_eq(_v(sums, _B.CHARGE, _F.VOIDED_INCOMING), c0, "voids what it has")
	assert_eq(_v(sums, _B.CHARGE, _F.VOIDED), 0, "the unprimed hub pays nothing")
	assert_eq(_v(sums, _B.CHARGE, _F.EFFECT), 8, "lands 8")
	_reconcile(all, pre)


func test_a_heat_rider_on_cold_is_produced_and_applied_onto_cold() -> void:
	var x := _at("cold", Vector2.ZERO)
	await _own([x])
	_set_t(x, -3)
	var span := _head(DamageInstance.new(), x)
	var r := StatusInstance.new()
	r.def = _fire.terrain
	r.power = 1.0
	r.raw = true
	r.target = x
	r.attacker = _blue
	r.schedule_index = 0
	r.structural_key = 0.0
	span.append(r)
	var pre := _pre()
	var all := _land(span)
	var sums := _sums(all)
	assert_eq(_v(sums, _B.HEAT, _F.PRODUCED), 1, "produced 1 Heat")
	assert_eq(_v(sums, _B.HEAT, _F.ONTO_OPPOSITE), 1, "applied onto Cold 1")
	assert_eq(_heat(x), -2, "the node's Cold reads 2")
	_reconcile(all, pre)


func test_a_charge_spend_counts_the_applied_amount_not_the_request() -> void:
	# A degree-1 hub (low T) whose one neighbour fans out to 8: an L2 bill of
	# floor + 9 outruns the store that primes it to L2.
	var g := await _tree("e", Vector2.ZERO, 1, 8)
	var x := g[0]
	var c := _t(x) + 1
	_set_charge(x, c)
	while _edge.level_of(_read(x)) < 2 and c < 400:
		c += 1
		_set_charge(x, c)
	assert_eq(_edge.level_of(_read(x)), 2, "fixture: L2")
	var have := _charge(x)
	assert_lt(have, _edge.void_floor + 9, "fixture: the bill exceeds the store")
	var pre := _pre()
	var all := _land(_head(DamageInstance.new(), x))
	var sums := _sums(all)
	assert_eq(_v(sums, _B.CHARGE, _F.VOIDED), have, "the clamp at 0: what was there")
	_reconcile(all, pre)

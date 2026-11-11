extends GutTest

## #1798 (Unit A): the two-stage hit resolver's gather core, [HitGather]. Stage
## one runs per beat, generation by generation, admit / land / read at each
## node; stage two lands each gathered entry as a copy of the whole hit.
## Acceptance 1, 2, 2b, 3, 4, 6, 7 and 10 of the issue.
##
## Terrain is keyed by an element's axis, so the test bands sit on the roster's
## own Fire (a band whose test [GoOff] logs what it is handed) and Lightning (a
## band holding the test [Admits]). They are swapped in before each test and
## restored after.

const _POISON := preload("res://effects/status/poison.tres")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _D := 2.0


## A test go-off: reaches what [member reach_of] names for the node it fires
## on, through the base law unless told otherwise, and logs what it is handed.
class _TestGoOff extends GoOff:
	var reach_of: Dictionary = {}
	var nodeless_of: Dictionary = {}
	var transfer_of: Dictionary = {}
	var own_damage := 0.0
	var element: Element = null
	var log: Array = []
	var hp: Callable = Callable()

	func fire(node: SkillNode, read: TerrainRead, hit_load: int) -> GoOffResult:
		log.append({node = node, count = read.count(element), hit_load = hit_load,
				hp = hp.call() if hp.is_valid() else 0.0})
		var r := super(node, read, hit_load)
		if nodeless_of.has(node):
			r.cost = {}
			r.nodeless_cost = int(nodeless_of[node])
		if transfer_of.has(node):
			for reach in r.reached:
				r.transfer[reach.node] = int(transfer_of[node])
		r.own_damage = own_damage
		return r

	func _reach(node: SkillNode, _read: TerrainRead, _hit_load: int) -> Array[GoOffResult.Reach]:
		var out: Array[GoOffResult.Reach] = []
		for n: SkillNode in reach_of.get(node, []):
			out.append(GoOffResult.Reach.new(n))
		return out


## A go-off with a shape and nothing else: the base law on the base itself.
class _ShapeOnly extends GoOff:
	var nodes: Array[SkillNode] = []

	func _reach(_node: SkillNode, _read: TerrainRead, _hit_load: int) -> Array[GoOffResult.Reach]:
		var out: Array[GoOffResult.Reach] = []
		for n in nodes:
			out.append(GoOffResult.Reach.new(n))
		return out


## A test admit: absorbs a copy at a node in [member refuse], logs every call.
class _TestAdmits extends Admits:
	var refuse: Dictionary = {}
	var element: Element = null
	var calls: Array = []

	func admit(node: SkillNode, before: TerrainRead, arrival: Arrival) -> bool:
		calls.append({node = node, count = before.count(element), centre = arrival.centre})
		return not refuse.has(node)


class _LogDamage extends DamageInstance:
	var log: Array = []

	func land_on(node: NodeCombat, world: CombatWorld) -> void:
		log.append("dmg:%s" % target.name)
		super(node, world)


class _LogStatus extends StatusInstance:
	var log: Array = []
	var tag := ""

	func land_on(node: NodeCombat, world: CombatWorld) -> void:
		log.append("%s:%s" % [tag, target.name])
		super(node, world)


var _w: TestWorld
var _owner: Entity
var _attacker: Entity
var _h: SkillNode
var _n1: SkillNode
var _n2: SkillNode
var _n3: SkillNode
var _fire: Element
var _light: Element
var _fire_bands: Array[ElementBand] = []
var _light_bands: Array[ElementBand] = []
var _goff: _TestGoOff
var _admits: _TestAdmits
var _orig := 0


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_owner = _entity()
	_attacker = _entity()
	await get_tree().process_frame
	_h = _w.add_node(&"H")
	_n1 = _w.add_node(&"N1")
	_n2 = _w.add_node(&"N2")
	_n3 = _w.add_node(&"N3")
	for n: SkillNode in [_n1, _n2, _n3]:
		_w.link(_h, n)
	_w.link(_n1, _n2)
	for n: SkillNode in [_h, _n1, _n2, _n3]:
		n.owned_by = _owner
	await get_tree().process_frame
	_fire = ElementRoster.shared().by_id(&"fire")
	_light = ElementRoster.shared().by_id(&"lightning")
	_fire_bands = _fire.bands.duplicate()
	_light_bands = _light.bands.duplicate()
	_goff = _TestGoOff.new()
	_goff.element = _fire
	_goff.hp = _hp_all
	var band := ElementBand.new()
	band.go_off = _goff
	var fb: Array[ElementBand] = [band]
	_fire.bands = fb
	_admits = _TestAdmits.new()
	_admits.element = _fire
	var lband := ElementBand.new()
	lband.admits = _admits
	var lb: Array[ElementBand] = [lband]
	_light.bands = lb


func after_each() -> void:
	_fire.bands = _fire_bands
	_light.bands = _light_bands
	CombatWorld.reset_live()


func _entity() -> Entity:
	var e := Entity.new()
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_w.graph.add_child(e)
	return e


func _c(n: SkillNode) -> NodeCombat:
	return CombatWorld.live().combat_for(n)


func _t(n: SkillNode) -> int:
	return _c(n).terrain_threshold()


func _fire_of(n: SkillNode) -> int:
	return _c(n).terrain_count(_fire)


func _set_fire(n: SkillNode, k: int) -> void:
	_c(n).add_terrain(_fire, k - _c(n).terrain_t())


func _hp_all() -> float:
	var sum := 0.0
	for n: SkillNode in [_h, _n1, _n2, _n3]:
		sum += _c(n).get_current_hp()
	return sum


## One hit on [param at], beat [param si]: a TRUE damage head of [param dmg],
## then [param heat] stacks of Fire's terrain and [param poison] of Poison.
func _span(at: SkillNode, heat := 0, poison := 0, dmg := _D, si := 0) -> Array[HitInstance]:
	var d := DamageInstance.new()
	_stamp(d, at, si)
	d.amount = dmg
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	var span: Array[HitInstance] = [d]
	if heat > 0:
		span.append(_status(_fire.terrain, heat, at, si))
	if poison > 0:
		span.append(_status(_POISON, poison, at, si))
	return span


func _status(def: StatusDef, power: float, at: SkillNode, si: int) -> StatusInstance:
	var s := StatusInstance.new()
	_stamp(s, at, si)
	s.def = def
	s.power = power
	s.raw = true
	return s


func _stamp(h: HitInstance, at: SkillNode, si: int) -> void:
	h.target = at
	h.attacker = _attacker
	h.schedule_index = si
	h.structural_key = float(si)


func _outcome(spans: Array) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	for span: Array in spans:
		for h: HitInstance in span:
			outcome.hits.append(h)
	_orig = outcome.hits.size()
	return outcome


## Stage one alone, on the live world: nothing lands but the element riders.
func _gather(spans: Array) -> AttackOutcome:
	var outcome := _outcome(spans)
	HitGather.stage_one(outcome.hits.duplicate(), CombatWorld.live(), HitQueue.over(outcome.hits))
	return outcome


## The whole drain: stage one per beat, then every hit and copy lands.
func _run(spans: Array) -> AttackOutcome:
	var outcome := _outcome(spans)
	await OutcomeApplier.drain(HitQueue.over(outcome.hits), CombatWorld.live(),
			BeatClock.instant_clock())
	return outcome


## The copies stage one made on [param at]: the hits past the authored ones.
func _copies(outcome: AttackOutcome, at: SkillNode) -> Array:
	return outcome.hits.slice(_orig).filter(func(h: HitInstance) -> bool: return h.target == at)


func _damage(hits: Array) -> Array:
	return hits.filter(func(h: HitInstance) -> bool: return h is DamageInstance) \
			.map(func(h: HitInstance) -> float: return h.amount)


func _poison(hits: Array) -> Array:
	return hits.filter(func(h: HitInstance) -> bool: return h is StatusInstance and h.def == _POISON) \
			.map(func(h: HitInstance) -> float: return h.power)


func _fired_at(at: SkillNode, key: String) -> Array:
	return _goff.log.filter(func(e: Dictionary) -> bool: return e.node == at) \
			.map(func(e: Dictionary) -> Variant: return e[key])


func _sorted(a: Array) -> Array:
	var b := a.duplicate()
	b.sort()
	return b


# 1 ─────────────────────────────────────────────────────────────────────────────
func test_stage_one_gathers_every_reached_node_before_any_payload_lands() -> void:
	_goff.share = 0.5
	_goff.lands_on_own_node = false
	_goff.reach_of = {_h: [_n1], _n1: [_n2]}
	_goff.nodeless_of = {_n1: 0}
	_set_fire(_h, _t(_h) + 1)
	_set_fire(_n1, _t(_n1) + 1)
	var hp := _hp_all()
	var outcome := _gather([_span(_h, 4, 3)])
	assert_eq(_hp_all(), hp, "no HP moved when stage one ends")
	assert_eq(_fired_at(_n1, "hp"), [hp], "N1's go-off read before any payload landed")
	assert_eq(_damage(_copies(outcome, _n1)), [_D * 0.5], "N1's entry lands damage × s")
	assert_eq(_poison(_copies(outcome, _n1)), [2.0], "and its aspect rider ceil(3 × 0.5)")
	assert_eq(_damage(_copies(outcome, _n2)), [_D * 0.5], "the second generation is flat, never s²")
	assert_eq(_poison(_copies(outcome, _n2)), [2.0], "its rider too: ceil(3 × 0.5), never ceil(3 × 0.25)")
	assert_eq(_fire_of(_n1), _t(_n1) + 1 + 2, "N1's store moves by ceil(4 × 0.5), once, in stage one")
	assert_eq(_fire_of(_n2), 2, "N2's by ceil(4 × 0.5), flat")


# 2 ─────────────────────────────────────────────────────────────────────────────
func test_the_base_go_off_spends_one_per_other_node_reached() -> void:
	var read := TerrainRead.of(_c(_h), _h)
	assert_eq(GoOff.new().fire(_h, read, 0).spend(), 0, "the bare base reaches nothing, spends nothing")
	var shape := _ShapeOnly.new()
	var three: Array[SkillNode] = [_n1, _n2, _n3]
	shape.nodes = three
	var r := shape.fire(_h, read, 0)
	assert_eq(r.spend(), 3, "spend = the other nodes reached")
	assert_eq(r.reached.size(), 3, "every node of the shape reached")
	assert_eq(r.share, shape.share, "share = its exported share")
	assert_eq(r.own_damage, 0.0, "own damage 0")
	var own: Array[SkillNode] = [_h]
	shape.nodes = own
	assert_eq(shape.fire(_h, read, 0).spend(), 0, "its own node is no node reached")

	_fire.bands[0].go_off = shape
	var none: Array[SkillNode] = []
	shape.nodes = none
	_set_fire(_h, _t(_h) + 1)
	var lone := _gather([_span(_h)])
	assert_eq(_fire_of(_h), _t(_h) + 1, "reaching no other node: the store does not move")
	assert_eq(lone.hits.size(), _orig, "no entry, no centre copy")
	shape.nodes = three
	_set_fire(_h, _t(_h) + 1)
	var wide := _gather([_span(_h)])
	assert_eq(_fire_of(_h), maxi(_t(_h) + 1 - 3, 0), "spend 3 commits; the centre copy is not counted")
	assert_lt(_fire_of(_h), _t(_h), "a spend digs under T")
	assert_eq(_damage(wide.hits.slice(_orig)).size(), 4, "3 reached plus the centre copy")


# 2b ────────────────────────────────────────────────────────────────────────────
func test_the_gather_commits_the_returned_spend_and_judges_no_reach() -> void:
	_goff.reach_of = {_h: [_n1, _n2, _n3]}
	_goff.nodeless_of = {_h: 1}
	_set_fire(_h, _t(_h) + 1)
	var four := _gather([_span(_h)])
	assert_eq(_fire_of(_h), _t(_h), "spend 1 while reaching 3: the store drops by exactly 1")
	assert_eq(_damage(four.hits.slice(_orig)).size(), 4, "3 reached plus the centre copy")
	assert_eq(_damage(_copies(four, _h)).size(), 1, "the centre copy is on H")

	_goff.reach_of = {}
	_set_fire(_h, _t(_h) + 1)
	var lone := _gather([_span(_h)])
	assert_eq(_fire_of(_h), _t(_h), "spend 1 reaching no node still commits")
	assert_eq(lone.hits.size(), _orig, "and makes no entry and no centre copy")

	_goff.nodeless_of = {}
	_goff.reach_of = {_h: [_n1]}
	_goff.share = 0.5
	_goff.own_damage = 3.0
	_set_fire(_h, _t(_h) + 1)
	var own := _gather([_span(_h)])
	assert_eq(_damage(_copies(own, _n1)), [_D * 0.5 + 3.0], "each entry: damage × s + d")
	assert_eq(_damage(_copies(own, _h)), [_D * 0.5 + 3.0], "the centre copy too")

	_goff.share = 1.0
	_goff.own_damage = 0.0
	for lands: bool in [true, false]:
		_goff.lands_on_own_node = lands
		_set_fire(_h, _t(_h) + 1)
		var h_hp := _c(_h).get_current_hp()
		var n1_hp := _c(_n1).get_current_hp()
		await _run([_span(_h)])
		assert_almost_eq(h_hp - _c(_h).get_current_hp(), _D * (2.0 if lands else 1.0), 1e-6,
				"H takes 2 landings with the centre copy, 1 without (lands_on_own_node %s)" % lands)
		assert_almost_eq(n1_hp - _c(_n1).get_current_hp(), _D, 1e-6, "the reached entry is unchanged")
		assert_eq(_fire_of(_h), _t(_h), "and so is the spend")


# 3 ─────────────────────────────────────────────────────────────────────────────
func test_the_hit_that_tips_a_node_over_T_sets_it_off_itself() -> void:
	_goff.lands_on_own_node = false
	_goff.reach_of = {_h: [_n1]}
	_set_fire(_h, _t(_h))
	_gather([_span(_h, 1)])
	assert_eq(_fired_at(_h, "count"), [_t(_h) + 1], "handed the post-land store, pre-hit + 1")

	_goff.log.clear()
	_set_fire(_h, _t(_h))
	var bare := _gather([_span(_h)])
	assert_eq(_goff.log.size(), 0, "no element rider: the node is not primed, no go-off")
	assert_eq(bare.hits.size(), _orig, "it gathers only the head")

	_goff.log.clear()
	_set_fire(_h, _t(_h) + 1)
	_gather([_span(_h, 2)])
	assert_eq(_fired_at(_h, "count"), [_t(_h) + 3], "an already primed node: pre-hit + 2")

	_goff.log.clear()
	_goff.reach_of = {_h: [_n1], _n1: [_n2]}
	_set_fire(_h, _t(_h) + 1)
	_set_fire(_n1, _t(_n1) + 1)
	var span := _span(_h)
	span[0].hit_load = 5
	_gather([span])
	assert_eq(_fired_at(_h, "hit_load"), [5], "the GoOff is handed the head's load")
	assert_eq(_fired_at(_n1, "hit_load"), [0], "a reached primed node's GoOff is handed 0")


# 4 ─────────────────────────────────────────────────────────────────────────────
func test_an_absorbed_copy_makes_no_entry_but_lands_its_terrain() -> void:
	_goff.share = 0.5
	_goff.reach_of = {_h: [_n1], _n1: [_n2]}
	_admits.refuse = {_n1: true}
	_c(_n1).add_terrain(_light, _t(_n1) + 1)
	_set_fire(_h, _t(_h) + 1)
	_set_fire(_n1, _t(_n1))
	var outcome := _gather([_span(_h, 2, 3)])
	assert_eq(_admits.calls.map(func(c: Dictionary) -> SkillNode: return c.node), [_n1],
			"asked once, about H's copy on N1; never about N1's centre copy")
	assert_eq(_admits.calls.map(func(c: Dictionary) -> int: return c.count), [_t(_n1)],
			"handed N1's store before the generation's riders")
	assert_eq(_fired_at(_n1, "count"), [_t(_n1) + 1],
			"the absorbed copy's rider ceil(2 × 0.5) primes N1, read after it landed")
	assert_eq(_damage(_copies(outcome, _n1)), [_D * 0.5],
			"N1 takes its own centre copy only: the absorbed copy made no entry")
	assert_eq(_poison(_copies(outcome, _n1)), [2.0], "no aspect rider from the absorbed copy either")
	assert_eq(_damage(_copies(outcome, _n2)), [_D * 0.5], "N1's go-off fired from the read")


# 6 ─────────────────────────────────────────────────────────────────────────────
func test_one_beat_lands_its_riders_as_sums_and_reads_each_go_off_from_them() -> void:
	_goff.lands_on_own_node = false
	_goff.reach_of = {_h: [_n1]}
	var runs: Array = []
	for swap: bool in [false, true]:
		_goff.log.clear()
		_set_fire(_h, _t(_h))
		_set_fire(_n1, 0)
		var x := _span(_h, 1, 0, _D)
		var y := _span(_h, 1, 0, _D * 2.0)
		var outcome := _gather([y, x] if swap else [x, y])
		assert_eq(_fired_at(_h, "count"), [_t(_h) + 2, _t(_h) + 2], "both go-offs are handed S + 2")
		runs.append([_sorted(_damage(_copies(outcome, _n1))), _fire_of(_h), _fire_of(_n1)])
	assert_eq(runs[0], runs[1], "swapping the arrivals changes nothing")
	assert_eq(runs[0][1], _t(_h) + 2 - 2, "the two spends sum")

	_goff.nodeless_of = {_h: _t(_h) + 5}
	_set_fire(_h, _t(_h))
	_gather([_span(_h, 1), _span(_h, 1)])
	assert_eq(_c(_h).terrain_t(), 0, "summed spends clamp at 0, never dig into the other sign")


# 7 ─────────────────────────────────────────────────────────────────────────────
func test_a_node_lands_and_goes_off_once_per_hit() -> void:
	_goff.lands_on_own_node = false
	_goff.reach_of = {_h: [_n1], _n1: [_h]}
	_set_fire(_h, _t(_h) + 1)
	_set_fire(_n1, _t(_n1) + 1)
	var outcome := _gather([_span(_h, 1, 2)])
	assert_eq(_fired_at(_h, "count").size(), 1, "H goes off once in the hit")
	assert_eq(_fired_at(_n1, "count").size(), 1, "N1 goes off once")
	assert_eq(_damage(_copies(outcome, _h)), [_D], "the returning copy is one more entry on H")
	assert_eq(_poison(_copies(outcome, _h)), [2.0], "carrying its aspect rider")
	assert_eq(_fire_of(_h), _t(_h) + 1 + 1 - 1,
			"H's rider lands once (the returning copy's does not); H pays 1 for N1")
	assert_eq(_fire_of(_n1), _t(_n1) + 1 + 1 - 1, "N1's default spend counts H, already visited")

	_goff.transfer_of = {_n1: 1}
	_set_fire(_h, _t(_h) + 1)
	_set_fire(_n1, _t(_n1) + 1)
	_gather([_span(_h, 1, 2)])
	assert_eq(_fire_of(_h), _t(_h) + 1 + 1, "N1's transfer raises H by 1 beyond its own rider: uncapped")

	_goff.transfer_of = {}
	_goff.log.clear()
	_set_fire(_h, _t(_h) + 1)
	_set_fire(_n1, _t(_n1) + 1)
	_gather([_span(_h, 1), _span(_h, 1)])
	assert_eq(_fired_at(_h, "count").size(), 2, "two hits each go off at H")
	assert_eq(_fired_at(_n1, "count").size(), 2, "and each at N1")


func test_a_transfer_commits_with_the_spend_before_the_next_admit() -> void:
	_goff.lands_on_own_node = false
	_goff.reach_of = {_h: [_n2]}
	_goff.transfer_of = {_h: 1}
	_admits.refuse = {_n2: true}
	_c(_n2).add_terrain(_light, _t(_n2) + 1)
	_set_fire(_h, _t(_h) + 1)
	var outcome := _gather([_span(_h, 1)])
	assert_eq(_admits.calls.map(func(c: Dictionary) -> int: return c.count), [1],
			"N2's admit is handed its store with the transfer already in")
	assert_eq(_fire_of(_n2), 2, "the transfer and the absorbed copy's rider both land")
	assert_eq(_copies(outcome, _n2).size(), 0, "the absorbed copy makes no entry")


# 10 ────────────────────────────────────────────────────────────────────────────
func test_a_beat_lands_terrain_then_damage_then_aspect_riders() -> void:
	_goff.lands_on_own_node = false
	_goff.reach_of = {_h: [_n1]}
	_set_fire(_h, _t(_h) + 1)
	var log: Array = []
	var d := _LogDamage.new()
	_stamp(d, _h, 0)
	d.amount = _D
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	d.log = log
	var span: Array[HitInstance] = [d]
	for row: Array in [["heat", _fire.terrain, 1.0], ["poison", _POISON, 1.0], ["poison", _POISON, 2.0]]:
		var s := _LogStatus.new()
		_stamp(s, _h, 0)
		s.def = row[1]
		s.power = row[2]
		s.raw = true
		s.tag = row[0]
		s.log = log
		span.append(s)
	var outcome: AttackOutcome = await _run([span])
	assert_eq(log, ["heat:H", "dmg:H", "dmg:N1", "poison:H", "poison:H", "poison:N1"],
			"terrain riders, then every damage of the beat, then every aspect rider")
	var riders := _copies(outcome, _n1).filter(func(h: HitInstance) -> bool: return h is StatusInstance)
	assert_eq(_poison(riders), [3.0], "one summed entry per status id per entry")
	assert_false(span.has(riders[0] if not riders.is_empty() else null) and not riders.is_empty(),
			"a copy's rider is its own, never merged with the hit's")


# The record: a replay feeds the gather's terrain and skips its staged riders.
func test_a_record_carries_the_stage_one_terrain_and_the_staged_riders() -> void:
	_goff.reach_of = {}
	_set_fire(_h, 0)
	var outcome: AttackOutcome = await _run([_span(_h, 3)])
	assert_eq(outcome.hits[0].terrain_ops, [[_h, 3, 0]], "the beat's net terrain rides its first head")
	assert_true(outcome.hits[1].staged, "the Heat rider landed in stage one")
	assert_eq(_fire_of(_h), 3, "and landed once")
	var rebuilt := AttackRecord.rebuild(AttackRecord.capture(outcome, _w.graph), _w.graph)
	assert_eq(rebuilt.hits[0].terrain_ops, [[_h, 3, 0]], "the record carries the terrain ops")
	assert_true(rebuilt.hits[1].staged, "and the staged flag")
	assert_false(rebuilt.hits[0].is_head, "a rebuilt hit is no head")
	_set_fire(_h, 0)
	await OutcomeApplier.drain(HitQueue.over(rebuilt.hits), CombatWorld.live(), BeatClock.instant_clock())
	assert_eq(_fire_of(_h), 3, "the replay lands the recorded terrain once, never gathering again")

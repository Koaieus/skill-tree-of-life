extends GutTest

## #1798 (Unit A): the two-stage hit resolver's gather core, [HitGather]. Stage
## one runs per beat, generation by generation, admit / land / read at each
## node; stage two lands each gathered entry as a copy of the whole hit.
## Acceptance 1, 2, 2b, 3, 4, 6, 7 and 10 of the issue; Unit B1 adds the
## second [Admits] read, the shatter and the walk end: 5, 5b and 6b; Unit B2
## the hop seat, the go-off's mark and the burst's replay: 6c and 11.
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
	## `SkillNode -> [[node, depth, ring], ...]`: reaches past depth 1 (B2).
	var deep_of: Dictionary = {}
	var nodeless_of: Dictionary = {}
	var transfer_of: Dictionary = {}
	var own_damage := 0.0
	var element: Element = null
	var log: Array = []
	var seq: Array = []
	var hp: Callable = Callable()

	func fire(node: SkillNode, read: TerrainRead, hit_load: int) -> GoOffResult:
		seq.append("fire:%s" % node.name)
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
		for d: Array in deep_of.get(node, []):
			var r := GoOffResult.Reach.new(d[0], d[1])
			r.ring.assign(d[2])
			out.append(r)
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


## A test second read (B1): logs every admit and read into the shared
## sequence, admits every copy, and answers from what the test sets: a breaker
## per arrival (by its head, or all), "paths end", a spend, a burst, a count.
class _ReadAdmits extends Admits:
	var element: Element = null
	var seq: Array = []
	var admits: Array = []
	var reads: Array = []
	var breaks: Dictionary = {}
	var break_all := false
	var ends := false
	## `SkillNode -> true`: the nodes whose read alone says "paths end" (B2).
	var ends_at: Dictionary = {}
	var spend := 0
	var burst := 0.0
	var extra := 2

	func admit(node: SkillNode, before: TerrainRead, arrival: Arrival) -> bool:
		seq.append("admit:%s:%d" % [node.name, arrival.generation])
		admits.append({node = node, count = before.count(element)})
		return true

	func read(node: SkillNode, after: TerrainRead, arrivals: Array[Arrival]) -> AdmitsAnswer:
		seq.append("read:%s:%d" % [node.name, arrivals[0].generation if not arrivals.is_empty() else -1])
		reads.append({node = node, count = after.count(element), n = arrivals.size(),
				amounts = arrivals.map(func(a: Arrival) -> float: return a.amount)})
		var answer := AdmitsAnswer.new()
		for i in arrivals.size():
			if break_all or breaks.has(arrivals[i].head):
				answer.breakers.append(i)
		answer.paths_end = ends or ends_at.has(node)
		answer.spend = spend
		answer.burst = burst
		answer.extra_landings = extra
		return answer


## A crit condition (#1798 item 9): logs its landing node's Fire store when
## evaluated, and passes.
class _StoreCondition extends LandingCondition:
	var element: Element = null
	var seen: Array = []

	func evaluate(lctx: LandingContext) -> bool:
		seen.append(CombatWorld.live().combat_for(lctx.node).terrain_count(element))
		return true


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
var _seq: Array = []
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
	_seq = []
	_goff.seq = _seq
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
	HitGather.tunables = HitGather.DEFAULT_TUNABLES
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
func _run(spans: Array, rng: RandomNumberGenerator = null) -> AttackOutcome:
	var outcome := _outcome(spans)
	await OutcomeApplier.drain(HitQueue.over(outcome.hits), CombatWorld.live(),
			BeatClock.instant_clock(), null, rng)
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


# 8 ─────────────────────────────────────────────────────────────────────────────
## Item 8's fixture: Fire's band (A, reaching N1 and N2) and Lightning's (B,
## reaching N2 and N3) on H, shares 1; one hit on H of damage D, Poison r and
## one Fire terrain stack, with the switch at [param dedupe] and B primed or
## not. H sits one Fire stack short of primed (at T), so the hit's own rider primes A.
func _dual(dedupe: bool, b_primed: bool, a_reach: Array = [_n1, _n2]) -> AttackOutcome:
	var tun := HitGatherTunables.new()
	tun.dedupe_dual_reach = dedupe
	HitGather.tunables = tun
	_goff.log.clear()
	_goff.reach_of = {_h: a_reach}
	var b := _TestGoOff.new()
	b.element = _light
	b.reach_of = {_h: [_n2, _n3]}
	_light.bands[0].admits = null
	_light.bands[0].go_off = b
	for n: SkillNode in [_n1, _n2, _n3]:
		_set_fire(n, 0)
		_set_light(n, 0)
	_set_fire(_h, _t(_h))
	_set_light(_h, _t(_h) + 1 if b_primed else 0)
	var outcome := _gather([_span(_h, 1, 3)])
	assert_eq(_fired_at(_h, "count").size(), 1, "A is read once at H")
	assert_eq(b.log.filter(func(e: Dictionary) -> bool: return e.node == _h).size(), 1 if b_primed else 0,
			"B fires once at H when primed")
	return outcome


func _landed(outcome: AttackOutcome, at: SkillNode) -> Array:
	return [_damage(_copies(outcome, at)), _poison(_copies(outcome, at))]


func test_the_whole_hit_takes_one_landing_per_channel_at_both_dedupe_settings() -> void:
	for dedupe: bool in [false, true]:
		var why := " (dedupe %s)" % dedupe
		var only_a := _dual(dedupe, false)
		assert_eq(_landed(only_a, _h), [[_D], [3.0]], "only A: H takes the head + one centre copy" + why)
		assert_eq(_landed(only_a, _n1), [[_D], [3.0]], "only A: N1 takes 1" + why)
		assert_eq(_landed(only_a, _n2), [[_D], [3.0]], "only A: N2 takes 1" + why)
		assert_eq(_landed(only_a, _n3), [[], []], "only A: N3 takes none" + why)
		assert_eq(_fire_of(_h), _t(_h) + 1 - 2, "H: its own rider once, then A's spend of 2" + why)
		for n: SkillNode in [_n1, _n2]:
			assert_eq(_fire_of(n), 1, "%s takes the terrain rider once%s" % [n.name, why])

		var both := _dual(dedupe, true)
		assert_eq(_landed(both, _h), [[_D, _D], [3.0, 3.0]],
				"both: H takes the head + one centre copy per channel, never merged" + why)
		assert_eq(_landed(both, _n1), [[_D], [3.0]], "both: N1 takes 1" + why)
		assert_eq(_landed(both, _n3), [[_D], [3.0]], "both: N3 takes 1" + why)
		if dedupe:
			assert_eq(_landed(both, _n2), [[2.0 * _D], [6.0]],
					"both, dedupe on: N2 takes one landing at share × channels" + why)
		else:
			assert_eq(_landed(both, _n2), [[_D, _D], [3.0, 3.0]], "both, concatenate: N2 takes 2" + why)
		assert_eq(_fire_of(_h), _t(_h) + 1 - 2, "H: its own rider once, then A's spend" + why)
		for n: SkillNode in [_n1, _n2, _n3]:
			assert_eq(_fire_of(n), 1, "%s takes the terrain rider once, N2 t not 2t%s" % [n.name, why])

		var none := _dual(dedupe, false, [])
		assert_eq(_landed(none, _h), [[], []], "A reaching no other node: no centre copy" + why)


# 9 ─────────────────────────────────────────────────────────────────────────────
func test_a_spell_arrival_draws_one_crit_decided_at_its_head_pre_hit() -> void:
	_goff.reach_of = {_h: [_n1]}
	_set_fire(_h, _t(_h))
	var cond := _StoreCondition.new()
	cond.element = _fire
	var spell := SpellDef.new()
	spell.crit_conditions.append(cond)
	var lctx := LandingContext.new()
	lctx.node = _h
	# D, then +1 Fire and Poison 2: two unpaired siblings that each drew before.
	var span := _span(_h, 1, 2)
	assert_gt(CritRoll.chance_for(span[0], CombatWorld.live()), 0.0, "the attacker's crit chance draws")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1798
	for hit: HitInstance in span:
		SpellResolver._crit_at_head(spell, lctx, hit, rng, CombatWorld.live())
	var outcome: AttackOutcome = await _run([span], rng)
	var once := RandomNumberGenerator.new()
	once.seed = 1798
	once.randf()
	assert_eq(rng.state, once.state, "the whole arrival draws once: no sibling or copy draws")
	assert_eq(cond.seen, [_t(_h)], "the condition is evaluated once, at the head, on the pre-hit store")
	assert_eq(_fired_at(_h, "count"), [_t(_h) + 1], "while the same hit's GoOff is handed pre-hit + 1")
	assert_gt(span[0].crit_tier, 0, "the passing condition crits the head")
	assert_eq(_entries(outcome, _h).size(), 2, "the centre copy: its damage and its Poison")
	assert_eq(_entries(outcome, _n1).size(), 2, "N1's copy: its damage and its Poison")
	for hit: HitInstance in outcome.hits:
		assert_eq([hit.crit_tier, hit.crit_multiplier], [span[0].crit_tier, span[0].crit_multiplier],
				"every sibling and copy, centre copy included, carries the head's crit")


func test_a_cast_evaluates_its_crit_conditions_once_per_landing() -> void:
	var cond := _StoreCondition.new()
	cond.element = _fire
	var poison := ApplyStatusEffect.new()
	poison.def = _POISON
	poison.power = 2.0
	var helper := SpellTestHelper.new()
	var spell := helper.make_spell(helper.make_config(helper.fan_all(), null, null, {max_hops = 1}),
			[DamageEffect.new(), poison] as Array[OnHitEffect], 1.0)
	spell.crit_conditions.append(cond)
	var out := SpellResolver.resolve_against(spell, _n3, null, _attacker, _w.graph, CombatWorld.live())
	assert_gt(out.timeline.size(), 1, "the cast lands on more than one node")
	assert_eq(cond.seen.size(), out.timeline.size(), "one condition read per landing, at its head")
	for ev: PropagationEvent in out.timeline:
		var head: HitInstance = ev.hits[0]
		assert_true(head.is_head, "the landing's first hit is its head")
		assert_eq(ev.hits.map(func(h: HitInstance) -> int: return h.crit_tier),
				ev.hits.map(func(_h: HitInstance) -> int: return head.crit_tier),
				"every hit of the landing carries its head's crit tier")


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


# ── Unit B1: the second read, the shatter, the walk end ─────────────────────────

## A [_ReadAdmits] on [param band], counting Fire (the hits' element).
func _read_admits(band: ElementBand) -> _ReadAdmits:
	var a := _ReadAdmits.new()
	a.element = _fire
	a.seq = _seq
	band.admits = a
	return a


## [param n]'s Lightning store set to [param k]: the band carrying the test read.
func _set_light(n: SkillNode, k: int) -> void:
	_c(n).add_terrain(_light, k - _c(n).charge())


## A crit already decided on [param h] (the head), at multiplier [param m].
func _crit(h: HitInstance, m: float) -> void:
	h.is_crit = true
	h.crit_tier = 1
	h.crit_multiplier = m
	h.crit_decided = true


## The node's holder's pool HP.
func _pool(n: SkillNode) -> float:
	return (_c(n).owner().board().get_stat(&"health") as PoolStat).current


## Stage two's entries on [param at]: the pushed copies, each paired to its head.
func _entries(outcome: AttackOutcome, at: SkillNode) -> Array:
	return _copies(outcome, at).filter(func(h: HitInstance) -> bool: return h.paired != null)


## The bursts stage one pushed: unpaired damage past the authored hits.
func _bursts(outcome: AttackOutcome) -> Array:
	return outcome.hits.slice(_orig).filter(func(h: HitInstance) -> bool: return h.paired == null) \
			.map(func(h: HitInstance) -> float: return h.amount)


# 5 ─────────────────────────────────────────────────────────────────────────────
func test_the_second_read_is_handed_the_post_rider_store_before_the_go_off() -> void:
	var adm := _read_admits(_fire.bands[0])
	adm.break_all = true
	adm.spend = 2
	adm.extra = 0
	_goff.lands_on_own_node = false
	_goff.reach_of = {_h: [_n1]}
	_set_fire(_h, _t(_h))
	_gather([_span(_h, 1)])
	assert_eq(adm.reads.map(func(r: Dictionary) -> int: return r.count), [_t(_h) + 1],
			"the second read is handed S + 1, after the rider landed")
	assert_eq(_seq, ["read:H:0", "fire:H"], "asked before the node's GoOff")
	assert_eq(_fired_at(_h, "count"), [_t(_h) + 1], "nothing commits between the read and the go-off")
	assert_eq(_fire_of(_h), _t(_h) + 1 - 2 - 1, "the break spend k and the go-off spend g commit together")


## The walk (N3 → H → N1, N2) on the live world: each wave's drain gathers its
## heads before step 4 reads them, so every case here, the null-Admits one
## included, runs the gather in the walk.
func test_a_walk_ends_where_the_middle_node_says_paths_end() -> void:
	var adm := _read_admits(_light.bands[0])
	_set_light(_h, _t(_h) + 1)
	var helper := SpellTestHelper.new()
	var spell := helper.make_spell(helper.make_config(helper.fan_all(), null, null, {max_hops = 2}),
			[DamageEffect.new()] as Array[OnHitEffect], 1.0)
	var walk := func(ends: bool, breaks: bool) -> Dictionary:
		adm.ends = ends
		adm.break_all = breaks
		adm.spend = 0
		adm.burst = 0.0
		adm.extra = 0
		var out := SpellResolver.resolve_against(spell, _n3, null, _attacker, _w.graph, CombatWorld.live())
		var by := {}
		for ev: PropagationEvent in out.timeline:
			by[ev.target] = ev
		return by
	var ended: Dictionary = walk.call(true, false)
	assert_true(ended.has(_h) and ended[_h].is_terminal, "the middle landing's event is terminal")
	assert_false(ended.has(_n1) or ended.has(_n2), "no wave is minted past the middle node")
	var on: Dictionary = walk.call(false, false)
	assert_true(on.has(_n1) and on.has(_n2), "path continues: the walk goes on")
	assert_false(on[_h].is_terminal, "and the middle landing is not terminal")
	var broke: Dictionary = walk.call(true, true)
	assert_true(broke.has(_n1) and broke.has(_n2), "an arrival that breaks the node walks on")
	_light.bands[0].admits = null
	var today: Dictionary = walk.call(true, false)
	assert_true(today.has(_n1) and today.has(_n2), "a null Admits runs the walk as today")


# 5b ────────────────────────────────────────────────────────────────────────────
func test_a_shatter_lands_the_breaker_three_times_spends_once_and_bursts_once() -> void:
	var adm := _read_admits(_light.bands[0])
	adm.break_all = true
	adm.spend = 2
	adm.burst = 3.0
	_goff.reach_of = {}
	var f := _n1
	var light := _t(f) + 4
	_set_light(f, light)
	_set_fire(f, 0)
	var pool := _pool(f)
	var hp := _c(f).get_current_hp()
	var outcome := _gather([_span(f, 1, 2)])
	assert_eq(_damage(_entries(outcome, f)), [_D, _D], "two extra landings: 3D with the hit's own")
	assert_eq(_poison(_entries(outcome, f)), [2.0, 2.0], "3r, one summed row on each")
	assert_eq(_bursts(outcome), [3.0], "one burst, pushed for stage two")
	assert_eq(_fire_of(f), 1, "the terrain rider moves the store once; the extras move none")
	assert_eq(_c(f).charge(), light - 2, "the break spends k once")
	assert_eq([_pool(f), _c(f).get_current_hp()], [pool, hp], "no HP has moved when stage one ends")

	_set_light(f, light)
	_set_fire(f, 0)
	var span := _span(f, 1, 2)
	_crit(span[0], 1.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	outcome = await _run([span], rng)
	assert_eq(_entries(outcome, f).map(func(h: HitInstance) -> int: return h.crit_tier), [1, 1, 1, 1],
			"every extra landing carries the head's crit tier")
	assert_eq(_pool(f), pool - 3.0, "the holder takes one TRUE burst of b through DotTick.mint")

	adm.extra = 0
	_set_light(f, light)
	outcome = _gather([_span(f, 1, 2)])
	assert_eq(_entries(outcome, f).size(), 0, "extra landings 0: the hit lands once")
	assert_eq(_bursts(outcome), [3.0], "and the burst still lands")

	f.owned_by = null
	_set_light(f, light)
	outcome = _gather([_span(f, 1, 2)])
	assert_eq(_c(f).charge(), light - 2, "an unallocated node takes the spend")
	assert_eq(_bursts(outcome), [], "and no burst")

	f.owned_by = _owner
	_light.bands[0].admits = null
	_set_light(f, light)
	outcome = _gather([_span(f, 1, 2)])
	assert_eq([_copies(outcome, f).size(), _c(f).charge()], [0, light],
			"a null Admits breaks nothing: one landing, no spend, no burst")


# 6b ────────────────────────────────────────────────────────────────────────────
func test_a_generation_reads_every_node_before_the_next_admits() -> void:
	var adm := _read_admits(_light.bands[0])
	_goff.lands_on_own_node = false
	_goff.reach_of = {_h: [_n1]}
	assert_gt(_t(_n1), 2, "F never primes at 2 stacks")
	_set_light(_n1, _t(_n1) + 1)
	_set_fire(_n1, 0)
	_set_fire(_h, _t(_h))
	_gather([_span(_h, 1, 2), _span(_n1, 1, 2)])
	assert_eq(_seq, ["fire:H", "read:N1:0", "admit:N1:1", "read:N1:1"],
			"every generation-0 read before any generation-1 admit; each admit before its node's read")
	assert_eq(adm.reads.map(func(r: Dictionary) -> int: return r.count), [1, 2],
			"F is read at 1 over Y alone, then at 2 over X's copy")
	assert_eq(adm.admits.map(func(r: Dictionary) -> int: return r.count), [1],
			"X's copy is admitted against the store generation 0 left")


func test_one_read_over_every_arrival_breaks_once() -> void:
	var adm := _read_admits(_light.bands[0])
	adm.spend = 2
	adm.burst = 3.0
	_goff.reach_of = {}
	var f := _n1
	var light := _t(f) + 4
	var run := func(flag_x: bool, flag_y: bool, ends: bool, swap: bool) -> Array:
		_set_light(f, light)
		_set_fire(f, 0)
		adm.reads.clear()
		adm.ends = ends
		var x := _span(f, 1, 2, _D)
		var y := _span(f, 1, 2, _D * 3.0)
		adm.breaks = {}
		if flag_x:
			adm.breaks[x[0]] = true
		if flag_y:
			adm.breaks[y[0]] = true
		var out := _gather([y, x] if swap else [x, y])
		return [adm.reads.size(), adm.reads[0].n, adm.reads[0].count, _sorted(adm.reads[0].amounts),
				_sorted(_damage(_entries(out, f))), _sorted(_poison(_entries(out, f))),
				_fire_of(f), _c(f).charge(), _bursts(out), x[0].path_ends, y[0].path_ends]
	var one: Array = run.call(true, false, false, false)
	assert_eq(one.slice(0, 4), [1, 2, 2, [_D, _D * 3.0]],
			"one read over both arrivals at store 2, each handed its own amount, never a sum")
	assert_eq(one.slice(4, 6), [[_D, _D], [2.0, 2.0]], "X lands 3 times, Y once")
	assert_eq(one.slice(6), [2, light - 2, [3.0], false, false],
			"the extras move no terrain; one spend, one burst; both heads walk on")
	assert_eq(run.call(true, false, false, true), one, "swapping X and Y changes nothing")
	var both: Array = run.call(true, true, false, false)
	assert_eq(both.slice(4), [[_D, _D, _D * 3.0, _D * 3.0], [2.0, 2.0, 2.0, 2.0], 2, light - 2, [3.0], false, false],
			"both breaking: each lands 3 times, still one spend and one burst")
	var held: Array = run.call(false, false, true, false)
	assert_eq(held.slice(4), [[], [], 2, light, [], true, true],
			"neither breaking and paths end: both heads end, no spend, no burst")


func test_the_second_read_is_handed_each_arrivals_own_amount() -> void:
	var adm := _read_admits(_light.bands[0])
	_goff.lands_on_own_node = false
	_goff.reach_of = {_h: [_n1]}
	_goff.share = 0.5
	_goff.own_damage = 1.0
	_set_light(_n1, _t(_n1) + 1)
	_set_fire(_h, _t(_h))
	var x := _span(_h, 1, 2, _D)
	_crit(x[0], 1.5)
	_gather([x, _span(_n1, 1, 2, _D * 3.0)])
	assert_eq(adm.reads.map(func(r: Dictionary) -> Array: return r.amounts),
			[[_D * 3.0], [(_D * 0.5 + 1.0) * 1.5]],
			"a head at its stamped damage; a copy at (D × s + d) × m, its own landing's number")


# ── Unit B2: the hop seat, the go-off's mark, the burst's replay ────────────────

# 6c ────────────────────────────────────────────────────────────────────────────
## P (H) primed in Fire at S = T; its go-off (spend 1 per node, share 1,
## transferring 1 to each) reaches each of [param ys] at depth 1 and Z (N2) at
## depth 2 behind them all. Y and Z sit in Lightning's band, under the test
## read, and hold no Fire, so neither primes. One hit X on P: D, poison 2, +1.
func _hop(adm: _ReadAdmits, ys: Array, ends: Array) -> AttackOutcome:
	_seq.clear()
	adm.admits.clear()
	adm.reads.clear()
	adm.ends_at = {}
	for y: SkillNode in ends:
		adm.ends_at[y] = true
	var deep: Array = []
	for y: SkillNode in ys:
		deep.append([y, 1, []])
	deep.append([_n2, 2, ys])
	_goff.deep_of = {_h: deep}
	for n: SkillNode in ys + [_n2]:
		_set_light(n, _t(n) + 1)
		_set_fire(n, 0)
	_set_fire(_h, _t(_h))
	return _gather([_span(_h, 1, 2)])


func test_a_deep_reach_lands_a_generation_later_and_drops_behind_an_ended_ring() -> void:
	var adm := _read_admits(_light.bands[0])
	adm.extra = 0
	_goff.lands_on_own_node = false
	_goff.transfer_of = {_h: 1}
	var s := _t(_h)
	var z := _n2
	assert_gt(_t(z), 2, "fixture: T ≥ 3, so Y and Z never prime at 2")
	var out := _hop(adm, [_n1], [])
	assert_eq(_seq, ["fire:H", "admit:N1:1", "read:N1:1", "admit:N2:2", "read:N2:2"],
			"Y arrives in generation 1, Z in 2, Z's admit after Y's second read")
	assert_eq(adm.admits.map(func(r: Dictionary) -> int: return r.count), [1, 1],
			"Z's admit is handed its store with the transfer already in")
	assert_eq([_damage(_entries(out, z)), _poison(_entries(out, z))], [[_D], [2.0]], "Z takes one landing")
	assert_eq([_fire_of(z), _fire_of(_h)], [2, s + 1 - 2], "Z: transfer + rider; P spends both nodes")

	_light.bands[0].admits = null
	out = _hop(adm, [_n1], [])
	assert_eq([_damage(_entries(out, z)), _poison(_entries(out, z)), _fire_of(z), _fire_of(_h)],
			[[_D], [2.0], 2, s + 1 - 2], "a null Admits on Y runs the same")
	_light.bands[0].admits = adm

	out = _hop(adm, [_n1], [_n1])
	assert_eq(_seq, ["fire:H", "admit:N1:1", "read:N1:1"], "Y ends the paths: Z is never asked")
	assert_eq(_entries(out, z).size(), 0, "Z takes no entry")
	assert_eq([_fire_of(z), _fire_of(_h), _fire_of(_n1)], [0, s + 1 - 1, 2],
			"no rider and no transfer reach Z, and only Y's cost commits")

	out = _hop(adm, [_n1, _n3], [_n1])
	assert_eq(_damage(_entries(out, z)), [_D], "one ring node of two ends: Z still takes its entry")
	out = _hop(adm, [_n1, _n3], [_n1, _n3])
	assert_eq([_entries(out, z).size(), _fire_of(z)], [0, 0], "both ring nodes end: Z takes none")


# 11 ────────────────────────────────────────────────────────────────────────────
## Fire's own first band's [Identity] (Burning), one the roster holds.
func _burning() -> Identity:
	var id: Identity = _fire_bands[0].identity
	assert_not_null(IdentityRoster.shared().by_id(id.id), "fixture: the roster holds Fire's band identity")
	return id


func _marks(hits: Array) -> Array:
	var out: Array = []
	for h: HitInstance in hits:
		if not out.any(func(m: BlastMark) -> bool: return is_same(m, h.blast_mark)):
			out.append(h.blast_mark)
	return out


func test_each_go_off_mints_one_mark_stamped_on_its_entries() -> void:
	var burning := _burning()
	_fire.bands[0].identity = burning
	_goff.reach_of = {_h: [_n1], _n3: [_n2]}
	_set_fire(_h, _t(_h))
	_set_fire(_n3, _t(_n3))
	var x := _span(_h, 1, 2)
	var y := _span(_n3, 1, 2)
	var outcome := _gather([x, y])
	var from_h := _entries(outcome, _n1) + _entries(outcome, _h)
	var marks := _marks(from_h)
	assert_eq(from_h.size(), 4, "fixture: N1 and the centre copy on H, damage and poison each")
	assert_eq(marks.size(), 1, "one mark on every entry of H's go-off, the centre copy's included")
	var mark: BlastMark = marks[0]
	assert_not_null(mark, "the go-off stamps its entries")
	if mark != null:
		assert_eq([mark.go_off.id if mark.go_off != null else &"", mark.centre, mark.attacker],
				[burning.id, _h, _attacker], "naming the band's Identity, centred on H, the attacker's")
	var from_n3 := _marks(_entries(outcome, _n2) + _entries(outcome, _n3))
	assert_eq(from_n3.size(), 1, "N3's go-off marks its own entries")
	assert_false(is_same(from_n3[0], mark), "a second go-off mints a second mark")
	assert_eq(_marks(x + y), [null], "the heads' own hits carry no mark")


func test_a_record_carries_the_go_off_mark_and_writes_no_key_unnamed() -> void:
	var burning := _burning()
	_fire.bands[0].identity = burning
	_goff.reach_of = {_h: [_n1]}
	_set_fire(_h, _t(_h))
	var outcome: AttackOutcome = await _run([_span(_h, 1, 2)])
	var d := AttackRecord.capture(outcome, _w.graph)
	assert_true(d.has(AttackRecord.KEY_BLAST_GO_OFF), "a named go-off writes the column")
	var rebuilt := AttackRecord.rebuild(d, _w.graph)
	var marks := _marks(rebuilt.hits.slice(_orig))
	assert_eq(marks.map(func(m: BlastMark) -> StringName:
			return m.go_off.id if m != null and m.go_off != null else &""), [burning.id],
			"the rebuilt entries share one mark naming the same Identity")

	_fire.bands[0].identity = null
	_set_fire(_h, _t(_h))
	outcome = await _run([_span(_h, 1, 2)])
	d = AttackRecord.capture(outcome, _w.graph)
	assert_eq([d.has(AttackRecord.KEY_BLAST_CENTRE), d.has(AttackRecord.KEY_BLAST_GO_OFF)], [true, false],
			"an unnamed go-off's mark rides the blast table and writes no new key")


func test_a_go_off_on_a_band_with_no_identity_names_the_band_below() -> void:
	var lower := ElementBand.new()
	lower.identity = _burning()
	var upper := ElementBand.new()
	upper.go_off = _goff
	var fb: Array[ElementBand] = [lower, upper]
	_fire.bands = fb
	_goff.reach_of = {_h: [_n1]}
	_set_fire(_h, _t(_h))
	var outcome := _gather([_span(_h, 1)])
	var marks := _marks(_entries(outcome, _n1))
	assert_eq(marks.map(func(m: BlastMark) -> StringName:
			return m.go_off.id if m != null and m.go_off != null else &""), [lower.identity.id],
			"the identity-less band's go-off names the band below")


# The burst's replay (B1's gap) ─────────────────────────────────────────────────
func test_a_rebuilt_burst_lands_on_the_holders_pool() -> void:
	var adm := _read_admits(_light.bands[0])
	adm.break_all = true
	adm.burst = 3.0
	adm.extra = 0
	_goff.reach_of = {}
	var f := _n1
	_set_light(f, _t(f) + 4)
	_set_fire(f, 0)
	var outcome: AttackOutcome = await _run([_span(f, 1, 2)])
	var rebuilt := AttackRecord.rebuild(AttackRecord.capture(outcome, _w.graph), _w.graph)
	var pool := _pool(f)
	var hp := _c(f).get_current_hp()
	await OutcomeApplier.drain(HitQueue.over(rebuilt.hits), CombatWorld.live(), BeatClock.instant_clock())
	assert_eq(_pool(f), pool - 3.0, "the replay lands the burst on the holder's pool, through DotTick.mint")
	assert_eq(_c(f).get_current_hp(), hp - _D, "and only the hit's own damage on the node")

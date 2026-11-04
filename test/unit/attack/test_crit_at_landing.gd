extends GutTest

## Crit rolls at LANDING: a HIT crits once, as its own fact, before any of its
## payload lands — the lead draws from the outcome's crit stream the moment
## its first rider lands (or it lands itself, bare), reading the landing world,
## and every rider copies that crit (× `crit_multiplier`, abs'd, on a status).
## So a mark landed earlier in the attack reaches the hits behind it, never
## the one that carried it. A rebuilt record carries no stream and lands its
## recorded crits without drawing.

const _MARKED := preload("res://effects/status/marked.tres")
const _POISON := preload("res://effects/status/poison.tres")
const _CURSE := preload("res://effects/status/curse.tres")
const _SEED := 0x1473

var _attacker: Entity
var _defender: Entity
var _graph: Graph
var _n: Dictionary = {}


func before_each() -> void:
	var f := await VolleyBoardFixture.build(self)
	_graph = f.graph
	_attacker = f.attacker
	_defender = f.hostile
	_n = {"a0": f.hub, "a1": f.leaves[0], "t": f.target, "u": f.cluster[0]}
	_attacker.stat_board.get_stat(&"crit_chance").base_value = 0.0


func _arrow(key: float) -> DamageInstance:
	var hit := DamageInstance.new()
	hit.attacker = _attacker
	hit.read_node = _n.a1
	hit.origin = _n.a1
	hit.target = _n.t
	hit.amount = 1.0
	hit.structural_key = key
	return hit


## A status hit on the target: a rider of [param lead] when given (lands
## BEFORE it, ADR 0067), else a bare status-only lead at [param key].
func _status(def: StatusDef, power: float, lead: HitInstance = null,
		key: float = 0.0) -> StatusInstance:
	var hit := StatusInstance.new()
	hit.def = def
	hit.attacker = _attacker
	hit.read_node = _n.a1
	hit.origin = _n.a1
	hit.target = _n.t
	hit.power = power
	hit.structural_key = lead.structural_key if lead != null else key
	hit.paired = lead
	return hit


func _mark_rider(lead: HitInstance) -> StatusInstance:
	# Deep enough that the marked chance clears 1.0 for a zero-crit attacker.
	return _status(_MARKED, ceilf(1.5 / _MARKED.incoming_modifiers[0].value), lead)


func _outcome(hits: Array) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	for hit in hits:
		outcome.hits.append(hit)
	outcome.resolve_seed = _SEED
	outcome.crit_stream = CritRoll.stream_for(_SEED)
	return outcome


## mark rider riding arrow 0 (lands ahead of it, key 0) → arrow 0 → arrow (key 1).
func _volley() -> AttackOutcome:
	var first := _arrow(0.0)
	return _outcome([_mark_rider(first), first, _arrow(1.0)])


func _stat(id: StringName, value: float) -> void:
	_attacker.stat_board.get_stat(id).base_value = value


func _land(outcome: AttackOutcome) -> void:
	var world := CombatWorld.shadow()
	OutcomeApplier.apply(outcome, world)
	world.free_shadow()


func _crits(outcome: AttackOutcome) -> Array:
	var out: Array = []
	for hit in outcome.hits:
		out.append([hit.is_crit, hit.crit_tier, hit.crit_multiplier])
	return out


# ── 1. A mark landed earlier in the attack reaches the hits behind it ───────

func test_an_arrow_behind_the_mark_rider_crits_and_the_one_carrying_it_does_not() -> void:
	var world := CombatWorld.shadow()
	var outcome := _volley()
	OutcomeApplier.apply(outcome, world)
	assert_almost_eq(CritRoll.chance_for(_arrow(1.0)), 0.0, 0.0001,
		"fixture: no crit without the mark")
	assert_false(outcome.hits[1].is_crit,
		"the arrow carrying the mark drew before its rider landed, so it never saw it")
	assert_false(outcome.hits[0].is_crit, "and its rider copies that non-crit")
	assert_true(outcome.hits[2].is_crit, "the next arrow reads the mark overlay")
	assert_eq(outcome.hits[2].crit_tier, 1, "one draw, stat path only")
	world.free_shadow()


# ── 1b. A hit crits first; its riders copy it ───────────────────────────────

func test_a_crit_arrows_poison_rider_lands_crit_multiplier_times_its_stacks() -> void:
	_stat(&"crit_chance", 0.0)
	var plain := _arrow(0.0)
	var plain_rider := _status(_POISON, 1.0, plain)
	_land(_outcome([plain_rider, plain]))
	assert_almost_eq(plain_rider.power, 1.0, 0.0001, "fixture: a non-crit arrow lands 1 stack")
	assert_false(plain_rider.is_crit)
	_stat(&"crit_chance", 1.0)
	_stat(&"crit_multiplier", 2.0)
	var arrow := _arrow(0.0)
	var rider := _status(_POISON, 1.0, arrow)
	_land(_outcome([rider, arrow]))
	assert_true(arrow.is_crit, "fixture: the arrow crit")
	assert_almost_eq(arrow.amount, 2.0, 0.0001, "the arrow's damage doubles")
	assert_true(rider.is_crit, "the rider copies the arrow's crit")
	assert_eq(rider.crit_tier, arrow.crit_tier)
	assert_almost_eq(rider.power, 2.0, 0.0001, "1 stack × crit_multiplier")
	assert_almost_eq(rider.effective_amount, 2.0, 0.0001)


func test_two_riders_on_one_hit_each_copy_its_crit_and_scale_their_own_count() -> void:
	for spec in [[0.0, 2.0, 1.0], [1.0, 2.0, 2.0], [1.0, 3.0, 3.0], [1.0, -2.0, 2.0]]:
		_stat(&"crit_chance", spec[0])
		_stat(&"crit_multiplier", spec[1])
		var arrow := _arrow(0.0)
		var poison := _status(_POISON, 1.0, arrow)
		var curse := _status(_CURSE, 1.0, arrow)
		_land(_outcome([poison, curse, arrow]))
		var at := "chance %s × %s: " % [spec[0], spec[1]]
		assert_almost_eq(poison.power, spec[2], 0.0001, at + "poison stacks")
		assert_almost_eq(curse.power, spec[2], 0.0001, at + "curse stacks")
		assert_eq(poison.is_crit, arrow.is_crit, at + "poison copies the crit")
		assert_eq(curse.is_crit, arrow.is_crit, at + "curse copies the crit")


func test_the_stream_advances_once_per_lead_whatever_it_carries() -> void:
	_stat(&"crit_chance", 0.5)
	var bare := _outcome([_arrow(0.0), _arrow(1.0)])
	_land(bare)
	var first := _arrow(0.0)
	var second := _arrow(1.0)
	var laden := _outcome([_status(_POISON, 1.0, first), _status(_CURSE, 1.0, first), first,
			_status(_POISON, 1.0, second), second])
	_land(laden)
	assert_ne(bare.crit_stream.state, CritRoll.stream_for(_SEED).state, "fixture: the leads drew")
	assert_eq(laden.crit_stream.state, bare.crit_stream.state,
		"two leads, two draws — a rider never draws")
	assert_eq(laden.hits[2].is_crit, bare.hits[0].is_crit, "same stream, same crits")
	assert_eq(laden.hits[4].is_crit, bare.hits[1].is_crit)


func test_a_status_only_lead_rolls_crit_chance_like_any_hit() -> void:
	_stat(&"crit_chance", 1.0)
	_stat(&"crit_multiplier", 2.0)
	var lead := _status(_POISON, 3.0)
	_land(_outcome([lead]))
	assert_true(lead.is_crit, "a bare status hit is a Hit and rolls crit_chance")
	assert_almost_eq(lead.power, 6.0, 0.0001, "2 × N")
	_stat(&"crit_chance", 0.0)
	var conditioned := _status(_POISON, 3.0)
	conditioned.crit_tier = 1
	_land(_outcome([conditioned]))
	assert_true(conditioned.is_crit, "a stamped condition tier still crits at chance 0")
	assert_almost_eq(conditioned.power, 6.0, 0.0001)
	var plain := _status(_POISON, 3.0)
	_land(_outcome([plain]))
	assert_false(plain.is_crit)
	assert_almost_eq(plain.power, 3.0, 0.0001)


func test_a_rebuilt_record_lands_a_riders_crit_and_power_as_the_authority_did() -> void:
	_stat(&"crit_chance", 1.0)
	var arrow := _arrow(0.0)
	var rider := _status(_POISON, 1.0, arrow)
	var resolved := _outcome([rider, arrow])
	_land(resolved)
	assert_almost_eq(rider.power, 2.0, 0.0001, "fixture: the authority's rider crit")
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(resolved, _graph)))
	var rebuilt := AttackRecord.rebuild(wired, _graph)
	OutcomeApplier.apply(rebuilt, CombatWorld.live())
	var peer := rebuilt.hits[0] as StatusInstance
	assert_not_null(peer, "the rider rebuilds as a StatusInstance")
	assert_true(peer.is_crit, "the recorded crit lands on the rider")
	assert_eq(peer.crit_tier, rider.crit_tier)
	assert_almost_eq(peer.power, 2.0, 0.0001, "the recorded power lands, never multiplied twice")
	assert_almost_eq(_n.t.get_combat().get_status_power(&"poison"), 2.0, 0.0001)


# ── 2. Determinism ──────────────────────────────────────────────────────────

func test_the_same_seed_lands_the_same_crits() -> void:
	var worlds := [CombatWorld.shadow(), CombatWorld.shadow()]
	var a := _volley()
	OutcomeApplier.apply(a, worlds[0])
	var b := _volley()
	OutcomeApplier.apply(b, worlds[1])
	assert_eq(_crits(a), _crits(b))
	for w in worlds:
		w.free_shadow()


func test_a_rebuilt_record_lands_its_recorded_crits_without_drawing() -> void:
	var resolved := _volley()
	var shadow := CombatWorld.shadow()
	OutcomeApplier.apply(resolved, shadow)
	shadow.free_shadow()
	assert_true(resolved.hits[2].is_crit, "fixture: the resolve crit the trailing arrow")
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(resolved, _graph)))
	var rebuilt := AttackRecord.rebuild(wired, _graph)
	assert_null(rebuilt.crit_stream, "a record carries no crit stream")
	var sentinel_state: int = resolved.crit_stream.state
	# The live replay lands the recorded mark before the trailing arrow, so a
	# replay that drew would stack a second tier on top of the recorded one.
	OutcomeApplier.apply(rebuilt, CombatWorld.live())
	assert_eq(resolved.crit_stream.state, sentinel_state, "the replay never touches the stream")
	assert_false(rebuilt.hits[1].is_crit)
	assert_true(rebuilt.hits[2].is_crit, "the recorded crit lands")
	assert_eq(rebuilt.hits[2].crit_tier, 1, "recorded tier, never re-drawn")

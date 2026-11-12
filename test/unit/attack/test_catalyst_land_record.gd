extends GutTest

## #1801 (Unit H): the Catalyst the gather's land step converts replays. The
## land step converts a node's Catalyst row over what lands there through
## [method CatalystStatus.convert] and takes the spend through the gather's row
## seat ([method HitGather._row_change], [method HitGather._commit_rows]), so
## the take rides the beat's first head ([member HitInstance.row_ops]) beside
## the converted terrain ([member HitInstance.terrain_ops]); the settle seat's
## take inside the gather's commit rides it too. A rebuilt record and a
## re-drained head feed both, never convert again. The def is built here and
## given a path ([method Resource.take_over_path]) so the record can name it:
## `catalyst.tres` is the retag unit's. Each test gathers on a shadow first (the
## authority's resolve), then replays on the untouched live world.

const _PATH := "res://test/_tmp/catalyst_land_probe.tres"
const _RAW := 4.0

var _w: TestWorld
var _red: Entity
var _blue: Entity
var _def: CatalystStatus
var _fire: Element
var _lightning: Element
var _shadow: CombatWorld


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_red = _w.add_entity("Red")
	_blue = _w.add_entity("Blue")
	await get_tree().process_frame
	_fire = ElementRoster.shared().by_id(&"fire")
	_lightning = ElementRoster.shared().by_id(&"lightning")
	_def = CatalystStatus.new()
	_def.id = &"catalyst_land_probe"
	_def.reapply = StatusDef.Reapply.ACCUMULATE
	_def.power_max = 0.0
	_def.decay = FlatDecay.new()
	_def.take_over_path(_PATH)
	_shadow = CombatWorld.shadow()


func after_each() -> void:
	StatusRoster.shared().statuses.erase(_def)
	if _shadow != null:
		_shadow.free_shadow()
		_shadow = null
	CombatWorld.reset_live()


## N, Red's, alone: its three anchors (the first Red's core) sit far outside
## any disc, so its degree is 3 (T leaves room for the numbers) and nothing it
## primes reaches another node.
func _alone() -> SkillNode:
	var n := _w.add_node(&"N", Vector2.ZERO)
	var anchors: Array[SkillNode] = []
	for i in 3:
		anchors.append(_w.add_node(StringName("N_anchor%d" % i), Vector2(5000.0 * i, 20000.0)))
		_w.link(n, anchors[i])
	_w.allocate(_red, [anchors[0], n])
	await get_tree().process_frame
	return n


func _slice(n: SkillNode, world: CombatWorld) -> NodeCombat:
	return world.combat_for(n) as NodeCombat


func _held(n: SkillNode, world: CombatWorld) -> int:
	return int(_slice(n, world).get_status_power(_def.id))


## One beat: a TRUE damage head from Blue on [param at] and one raw terrain
## rider per [param riders] entry (Element → stacks).
func _beat(at: SkillNode, riders: Dictionary) -> AttackOutcome:
	var d := DamageInstance.new()
	d.amount = _RAW
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	var outcome := AttackOutcome.new()
	outcome.hits.append(d)
	for e: Element in riders:
		var s := StatusInstance.new()
		s.def = e.terrain
		s.power = float(riders[e])
		s.raw = true
		outcome.hits.append(s)
	for hit in outcome.hits:
		hit.target = at
		hit.attacker = _blue
		hit.schedule_index = 0
		hit.structural_key = 0.0
	return outcome


func _drain(outcome: AttackOutcome, world: CombatWorld) -> void:
	await OutcomeApplier.drain(HitQueue.over(outcome.hits), world, BeatClock.instant_clock(), null,
			RandomNumberGenerator.new())


func _rebuilt(outcome: AttackOutcome) -> AttackOutcome:
	return AttackRecord.rebuild(AttackRecord.capture(outcome, _w.graph), _w.graph)


## The recorded row changes on [param outcome]'s first head for the test's def.
func _takes(outcome: AttackOutcome) -> Array:
	return outcome.hits[0].row_ops.filter(func(op: Array) -> bool: return op[2] == _def)


func _taken(outcome: AttackOutcome) -> float:
	var total := 0.0
	for op: Array in _takes(outcome):
		total += float(op[3])
	return total


# --- the land take: recorded beside the converted terrain -------------------------

func test_the_land_take_rides_the_record_beside_the_converted_terrain() -> void:
	var n: SkillNode = await _alone()
	assert_gte(_slice(n, CombatWorld.live()).terrain_threshold(), 5, "fixture: 5 Heat stays inert")
	_slice(n, CombatWorld.live()).apply_status(_def, 3.0)
	var outcome := _beat(n, {_fire: 2})
	await _drain(outcome, _shadow)
	assert_eq(_slice(n, _shadow).terrain_t(), 5, "the land write carries the 3 converted")
	assert_eq(_held(n, _shadow), 0, "the row is taken")
	var takes := _takes(outcome)
	assert_eq(takes.size(), 1, "one take, recorded on the beat's first head")
	if takes.size() == 1:
		assert_eq(takes[0][0], n, "on N")
		assert_eq(int(takes[0][1]), StatusInstance.HostKind.NODE, "N's own row")
		assert_eq(float(takes[0][3]), -3.0, "the whole store")
	assert_eq(_held(n, CombatWorld.live()), 3, "fixture: the live store is untouched")


func test_a_rebuilt_record_lands_the_same_terrain_and_row() -> void:
	var n: SkillNode = await _alone()
	_slice(n, CombatWorld.live()).apply_status(_def, 3.0)
	var outcome := _beat(n, {_fire: 2})
	await _drain(outcome, _shadow)
	var t := _slice(n, _shadow).terrain_t()
	var held := _held(n, _shadow)
	assert_eq(held, 0, "fixture: the gather took the row")
	await _drain(_rebuilt(outcome), CombatWorld.live())
	assert_eq(_slice(n, CombatWorld.live()).terrain_t(), t, "the rebuilt beat lands the converted Heat")
	assert_eq(_held(n, CombatWorld.live()), held, "and takes the row as the gather did")


func test_a_re_drained_head_converts_once() -> void:
	var n: SkillNode = await _alone()
	_slice(n, CombatWorld.live()).apply_status(_def, 3.0)
	var outcome := _beat(n, {_fire: 2})
	await _drain(outcome, _shadow)
	assert_true(outcome.hits[0].gathered, "fixture: the head was gathered on the shadow")
	await _drain(outcome, CombatWorld.live())
	assert_eq(_slice(n, CombatWorld.live()).terrain_t(), 5, "the live apply lands the conversion once")
	assert_eq(_held(n, CombatWorld.live()), 0, "and takes the row once")


# --- the settle seat's take inside the gather: recorded too ------------------------

func test_a_land_that_splits_and_primes_records_both_takes() -> void:
	var n: SkillNode = await _alone()
	StatusRoster.shared().statuses.append(_def)
	var live := _slice(n, CombatWorld.live())
	var t := live.terrain_threshold()
	assert_gte(t, 3, "fixture: 2 Charge stays inert")
	live.add_terrain(_fire, t - 1)
	live.apply_status(_def, 3.0)
	var outcome := _beat(n, {_fire: 1, _lightning: 1})
	await _drain(outcome, _shadow)
	assert_eq(_slice(n, _shadow).terrain_t(), t + 2,
			"1 Heat landed, 1 converted at land, the leftover 1 converted at settle")
	assert_eq(_slice(n, _shadow).charge(), 2, "1 Charge landed and 1 converted")
	assert_eq(_held(n, _shadow), 0, "the row ends at 0")
	assert_eq(_taken(outcome), -3.0, "the land take and the settle take are both recorded")
	await _drain(_rebuilt(outcome), CombatWorld.live())
	assert_eq(live.terrain_t(), t + 2, "the rebuilt beat lands the same Heat")
	assert_eq(live.charge(), 2, "and the same Charge")
	assert_eq(_held(n, CombatWorld.live()), 0, "and takes the row as the gather did")

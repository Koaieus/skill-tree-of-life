extends GutTest

## A status-row change the gather commits replays. The land step's Catalyst
## conversion takes off the node's row in stage one
## ([method HitGather._commit_rows]); the gather records it on the beat's first
## head beside the terrain ops, the record captures and rebuilds it, and
## [method HitGather.feed] lands it where a re-drained or rebuilt beat would
## gather (acceptance 4's invariant). Each test gathers on a shadow first (the
## authority's resolve), then replays on the untouched live world, which starts
## from the same store. The hit lands 1 Heat + 1 Charge on N's 3 Catalyst:
## the split converts 1 into each and the tied leftover stays, and N stays
## under T so no prime conversion takes it.

const _RAW := 4.0

var _w: TestWorld
var _red: Entity
var _blue: Entity
var _shadow: CombatWorld


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_red = _w.add_entity("Red")
	_blue = _w.add_entity("Blue")
	await get_tree().process_frame
	_shadow = CombatWorld.shadow()


func after_each() -> void:
	if _shadow != null:
		_shadow.free_shadow()
		_shadow = null
	CombatWorld.reset_live()


func _def() -> StatusDef:
	return StatusRoster.shared().by_concept(&"catalyst")


## The Catalyst charges on [param n]'s slice of [param world].
func _held(n: SkillNode, world: CombatWorld) -> int:
	return int(world.combat_for(n).get_status_power(&"catalyst"))


## One beat: a TRUE damage head of [param _RAW] from Blue on [param at], with
## a 1-stack Heat and a 1-stack Charge rider.
func _beat(at: SkillNode) -> AttackOutcome:
	var d := DamageInstance.new()
	d.target = at
	d.attacker = _blue
	d.schedule_index = 0
	d.structural_key = 0.0
	d.amount = _RAW
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	var outcome := AttackOutcome.new()
	outcome.hits.append(d)
	for id: StringName in [&"fire", &"lightning"]:
		var rider := StatusInstance.new()
		rider.target = at
		rider.attacker = _blue
		rider.schedule_index = 0
		rider.def = ElementRoster.shared().by_id(id).terrain
		rider.power = 1.0
		rider.raw = true
		outcome.hits.append(rider)
	return outcome


func _drain(outcome: AttackOutcome, world: CombatWorld) -> void:
	await OutcomeApplier.drain(HitQueue.over(outcome.hits), world, BeatClock.instant_clock(), null,
			RandomNumberGenerator.new())


func _rebuilt(outcome: AttackOutcome) -> AttackOutcome:
	return AttackRecord.rebuild(AttackRecord.capture(outcome, _w.graph), _w.graph)


## Red's N holding [param charges] Catalyst, linked to three far anchors so
## its T sits past one landing's Charge.
func _charged_node(charges: int) -> SkillNode:
	var n := _w.add_node(&"N", Vector2.ZERO)
	for i in 3:
		var a := _w.add_node(StringName("A%d" % i))
		a.global_position = Vector2(20000.0 * (i + 1), 20000.0)
		_w.link(n, a)
	_w.allocate(_red, [n])
	await get_tree().process_frame
	CombatWorld.live().combat_for(n).apply_status(_def(), float(charges))
	return n


# --- a record: captured, rebuilt, fed on a fresh world ----------------------------

func test_a_rebuilt_record_spends_a_nodes_own_row_as_the_gather_did() -> void:
	var n: SkillNode = await _charged_node(3)
	var outcome := _beat(n)
	await _drain(outcome, _shadow)
	var spent := _held(n, _shadow)
	assert_eq(spent, 1, "fixture: the land step converted 2 off N's own row, the tied 1 stays")
	assert_lte(_shadow.combat_for(n).terrain_t(), _shadow.combat_for(n).terrain_threshold(), "fixture: N stays unprimed")
	assert_eq(_held(n, CombatWorld.live()), 3, "fixture: the live store is untouched")
	await _drain(_rebuilt(outcome), CombatWorld.live())
	assert_eq(_held(n, CombatWorld.live()), spent, "the rebuilt beat feeds the recorded row spend")


# --- a re-drained head: the authority's live apply after its shadow ---------------

func test_a_re_drained_head_feeds_the_row_spend_once() -> void:
	var n: SkillNode = await _charged_node(3)
	var outcome := _beat(n)
	await _drain(outcome, _shadow)
	var spent := _held(n, _shadow)
	assert_eq(spent, 1, "fixture: the land step converted 2")
	assert_true(outcome.hits[0].gathered, "fixture: the head was gathered on the shadow")
	await _drain(outcome, CombatWorld.live())
	assert_eq(_held(n, CombatWorld.live()), spent,
			"the live apply feeds the recorded take once: never dropped, never twice")

extends GutTest

## #1799 (Unit F-r): a status-row change the gather commits replays. An
## [member Aspect.go_off]'s spend comes off its holder's row in stage one
## ([method HitGather._commit_rows], after the generation's terrain); the gather
## records it on the beat's first head beside the terrain ops, the record
## captures and rebuilds it, and [method HitGather.feed] lands it where a
## re-drained or rebuilt beat would gather (acceptance 4's invariant). The
## holder is the one the gather resolved: the node's own slice, or a bare
## core's owner. Here a [DiscGoOff] the test authors on the Explosive [Aspect],
## as `test_gather_aspect_go_off.gd` builds one; nothing on master authors one.
## Each test gathers on a shadow first (the authority's resolve), then replays
## on the untouched live world, which starts from the same store.

const _RAW := 4.0

var _w: TestWorld
var _red: Entity
var _blue: Entity
var _aspect: Aspect
var _was: GoOff
var _shadow: CombatWorld


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_red = _w.add_entity("Red")
	_blue = _w.add_entity("Blue")
	await get_tree().process_frame
	_aspect = AspectRoster.shared().by_id(&"explosive")
	_was = _aspect.go_off
	var disc := DiscGoOff.new()
	disc.lands_on_own_node = false
	_aspect.go_off = disc
	_shadow = CombatWorld.shadow()


func after_each() -> void:
	_aspect.go_off = _was
	if _shadow != null:
		_shadow.free_shadow()
		_shadow = null
	CombatWorld.reset_live()


func _def() -> StatusDef:
	return StatusRoster.shared().by_concept(&"explosive")


func _spread() -> ExplosiveSpread:
	return _def().spread as ExplosiveSpread


## The Explosive charges on [param n]'s slice of [param world].
func _held(n: SkillNode, world: CombatWorld) -> int:
	return int(world.combat_for(n).get_status_power(&"explosive"))


## The Explosive charges on Red's entity-hosted rows in [param world].
func _owners(world: CombatWorld) -> int:
	return int(world.combat_for_entity(_red).get_status_power(&"explosive"))


## A node whose hitbox sits [param edge] px from [param centre]'s centre, due east.
func _east_of(centre: SkillNode, id: StringName, edge: float) -> SkillNode:
	var n := _w.add_node(id)
	n.global_position = centre.global_position + Vector2(edge + n.radius, 0.0)
	return n


## One beat: a TRUE damage head of [param _RAW] from Blue on [param at].
func _beat(at: SkillNode, load := 0) -> AttackOutcome:
	var d := DamageInstance.new()
	d.target = at
	d.attacker = _blue
	d.schedule_index = 0
	d.structural_key = 0.0
	d.amount = _RAW
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	d.hit_load = load
	var outcome := AttackOutcome.new()
	outcome.hits.append(d)
	return outcome


func _drain(outcome: AttackOutcome, world: CombatWorld) -> void:
	await OutcomeApplier.drain(HitQueue.over(outcome.hits), world, BeatClock.instant_clock(), null,
			RandomNumberGenerator.new())


func _rebuilt(outcome: AttackOutcome) -> AttackOutcome:
	return AttackRecord.rebuild(AttackRecord.capture(outcome, _w.graph), _w.graph)


## N holding [param charges], M inside its disc; both Red's.
func _charged_node(charges: int) -> SkillNode:
	var n := _w.add_node(&"N", Vector2.ZERO)
	var m := _east_of(n, &"M", _spread().radius_for(n.radius, charges) * 0.5)
	_w.allocate(_red, [n, m])
	await get_tree().process_frame
	CombatWorld.live().combat_for(n).apply_status(_def(), float(charges))
	return n


# --- a record: captured, rebuilt, fed on a fresh world ----------------------------

func test_a_rebuilt_record_spends_a_nodes_own_row_as_the_gather_did() -> void:
	var n: SkillNode = await _charged_node(3)
	var outcome := _beat(n)
	await _drain(outcome, _shadow)
	var spent := _held(n, _shadow)
	assert_eq(spent, 3 - DiscGoOff.spend_of(0, 3), "fixture: the gather spent N's own row")
	assert_eq(_held(n, CombatWorld.live()), 3, "fixture: the live store is untouched")
	await _drain(_rebuilt(outcome), CombatWorld.live())
	assert_eq(_held(n, CombatWorld.live()), spent, "the rebuilt beat feeds the recorded row spend")


func test_a_rebuilt_record_spends_a_bare_cores_owner_row_as_the_gather_did() -> void:
	var core := _w.add_node(&"Core", Vector2.ZERO)
	var m := _east_of(core, &"M", _spread().radius_for(core.radius, 3) * 0.5)
	_w.allocate(_red, [core, m])
	await get_tree().process_frame
	assert_true(CombatWorld.live().combat_for(core).is_core(), "fixture: Core is Red's core")
	CombatWorld.live().combat_for_entity(_red).apply_status(_def(), 3.0)
	var outcome := _beat(core, 1)
	await _drain(outcome, _shadow)
	var spent := _owners(_shadow)
	assert_eq(spent, 3 - DiscGoOff.spend_of(1, 3), "fixture: the gather spent the owner's row")
	assert_eq(_owners(CombatWorld.live()), 3, "fixture: the live store is untouched")
	await _drain(_rebuilt(outcome), CombatWorld.live())
	assert_eq(_owners(CombatWorld.live()), spent, "the rebuilt beat feeds the spend on the recorded holder")


# --- a re-drained head: the authority's live apply after its shadow ---------------

func test_a_re_drained_head_feeds_the_row_spend_once() -> void:
	var n: SkillNode = await _charged_node(3)
	var outcome := _beat(n)
	await _drain(outcome, _shadow)
	var spent := _held(n, _shadow)
	assert_true(outcome.hits[0].gathered, "fixture: the head was gathered on the shadow")
	assert_gt(outcome.hits.size(), 1, "fixture: the go-off sent a copy")
	await _drain(outcome, CombatWorld.live())
	assert_eq(_held(n, CombatWorld.live()), spent,
			"the live apply feeds the recorded spend once: never dropped, never per copy")

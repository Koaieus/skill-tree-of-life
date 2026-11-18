extends GutTest

## The Catalyst conversion cue ([signal Events.catalyst_converted]): the
## authority's resolve on a shadow world has no audience, the replay of the
## rebuilt record on the live world (the authority's own and every peer's)
## announces each take of a Catalyst row once.

const _PATH := "res://test/_tmp/catalyst_cue_probe.tres"

var _w: TestWorld
var _red: Entity
var _blue: Entity
var _def: CatalystStatus
var _fire: Element
var _shadow: CombatWorld
var _roster: StatusRoster


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_red = _w.add_entity("Red")
	_blue = _w.add_entity("Blue")
	await get_tree().process_frame
	_fire = ElementRoster.shared().by_id(&"fire")
	_def = CatalystStatus.new()
	_def.id = &"catalyst_cue_probe"
	_def.reapply = StatusDef.Reapply.ACCUMULATE
	_def.power_max = 0.0
	_def.decay = FlatDecay.new()
	_def.take_over_path(_PATH)
	_shadow = CombatWorld.shadow()
	_roster = StatusRoster.shared()


func after_each() -> void:
	_roster.statuses.erase(_def)
	_roster = null
	if _shadow != null:
		_shadow.free_shadow()
		_shadow = null
	CombatWorld.reset_live()


func _alone() -> SkillNode:
	var n := _w.add_node(&"N", Vector2.ZERO)
	var anchors: Array[SkillNode] = []
	for i in 3:
		anchors.append(_w.add_node(StringName("N_anchor%d" % i), Vector2(5000.0 * i, 20000.0)))
		_w.link(n, anchors[i])
	_w.allocate(_red, [anchors[0], n])
	await get_tree().process_frame
	return n


func _beat(at: SkillNode) -> AttackOutcome:
	var d := DamageInstance.new()
	d.amount = 4.0
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	var s := StatusInstance.new()
	s.def = _fire.terrain
	s.power = 2.0
	s.raw = true
	var outcome := AttackOutcome.new()
	outcome.hits.append(d)
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


func test_resolve_is_silent_and_the_rebuilt_replay_announces_once() -> void:
	var n: SkillNode = await _alone()
	(CombatWorld.live().combat_for(n) as NodeCombat).apply_status(_def, 3.0)
	var outcome := _beat(n)
	watch_signals(Events)
	await _drain(outcome, _shadow)
	assert_signal_emit_count(Events, "catalyst_converted", 0, "a shadow world has no audience")
	var rebuilt := AttackRecord.rebuild(AttackRecord.capture(outcome, _w.graph), _w.graph)
	await _drain(rebuilt, CombatWorld.live())
	assert_signal_emit_count(Events, "catalyst_converted", 1, "the replay announces the take")
	assert_signal_emitted_with_parameters(Events, "catalyst_converted", [n, 3])

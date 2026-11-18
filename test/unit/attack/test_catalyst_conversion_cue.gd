extends GutTest

## The Catalyst conversion cue ([signal Events.catalyst_converted]): the
## authority's resolve on a shadow world has no audience, the replay of the
## rebuilt record on the live world (the authority's own and every peer's)
## announces each take of a Catalyst row once, with what it converted into;
## the world turn's terrain pass, run on every peer's live world, announces its
## own takes the same way.

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
	# The payload is the stacks made (ratio 1 : 1 here), keyed by landing element.
	assert_signal_emitted_with_parameters(Events, "catalyst_converted", [n, {_fire.id(): 3}])


## The world turn's terrain pass is no record: [EndTurnCommand] reproduces it on
## every peer's live world, so each announces its own conversion once.
func test_a_world_turn_conversion_announces_once() -> void:
	var n: SkillNode = await _alone()
	var hot := _w.add_node(&"Hot", Vector2(-5000.0, 0.0))
	_w.link(n, hot)
	await get_tree().process_frame
	_roster.statuses.append(_def)
	var live := CombatWorld.live()
	var slice := live.combat_for(n) as NodeCombat
	var t := slice.terrain_threshold()
	var deg := maxi(n.get_graph_degree(_w.graph), hot.get_graph_degree(_w.graph))
	slice.add_terrain(_fire, t - slice.terrain_t())
	(live.combat_for(hot) as NodeCombat).add_terrain(_fire, t + 4 * t * (1 + deg))
	slice.apply_status(_def, 3.0)
	watch_signals(Events)
	live.flow_temperature(1)
	assert_eq(int(slice.get_status_power(_def.id)), 0, "the flow primed N: the store converted")
	assert_gt(slice.terrain_t(), t, "N is past T")
	assert_signal_emit_count(Events, "catalyst_converted", 1, "the world turn announces its take")
	assert_signal_emitted_with_parameters(Events, "catalyst_converted", [n, {_fire.id(): 3}])

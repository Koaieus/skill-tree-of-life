extends GutTest

## A board blast stamps itself on its hits ([BlastMark]) and [OutcomeApplier]
## announces it once per live apply ([signal Events.blast_landed]) — never on
## a shadow world. Reach is the sim's own radius_for, never a literal. A mark
## the gather mints carries the generation of the read its go-off fired at,
## through the record too (#1799, ADR 0091 §1).

const _EXPLOSIVE := preload("res://effects/status/explosive.tres")
const _POISON := preload("res://effects/status/poison.tres")
const _BLIND := preload("res://effects/status/blindness.tres")
const _BOARD := preload("res://entity/default_entity_board.tres")

## A go-off that reaches what [member reach_of] names for the node it fires on,
## through the base law.
class _ChainGoOff extends GoOff:
	var reach_of: Dictionary = {}

	func _reach(node: SkillNode, _read: TerrainRead, _hit_load: int) -> Array[GoOffResult.Reach]:
		var out: Array[GoOffResult.Reach] = []
		for n: SkillNode in reach_of.get(node, []):
			out.append(GoOffResult.Reach.new(n))
		return out


var _f: VolleyBoardFixture
var _fire: Element
var _fire_bands: Array[ElementBand] = []


func before_each() -> void:
	_f = await VolleyBoardFixture.build(self, true)
	_f.target.base_radius = 40.0
	_f.target.get_combat().apply_status(_EXPLOSIVE, 2.0)
	_fire = ElementRoster.shared().by_id(&"fire")
	_fire_bands = _fire.bands.duplicate()


func after_each() -> void:
	_fire.bands = _fire_bands


func _rider(def: StatusDef) -> ApplyStatusEffect:
	var e := ApplyStatusEffect.new()
	e.def = def
	return e


## A DETONATE spell landing (load 3) on the charged target with two inners.
func _detonate() -> Array[HitInstance]:
	var cast := PropagationContext.new()
	cast.caster = _f.attacker
	cast.graph = _f.graph
	cast.world = CombatWorld.live()
	cast.outcome = AttackOutcome.new()
	cast.target_mask = SkillNode.Ownership.HOSTILE
	var payload := CastSpell.new()
	payload.current_node = _f.target
	payload.source = _f.leaves[0]
	payload.damage = 10.0
	var lctx := LandingContext.for_test(payload, _f.target, cast)
	var effects: Array[OnHitEffect] = [_rider(_POISON), _rider(_BLIND)]
	OnHitEffect.run_all(DetonateEffect.arm(effects, 3), lctx)
	return lctx.hits


## The hits the blast appended: everything off the centre.
func _inner(hits: Array[HitInstance]) -> Array[HitInstance]:
	var out: Array[HitInstance] = []
	for h in hits:
		if h.target != _f.target:
			out.append(h)
	return out


func _outcome(hits: Array[HitInstance]) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	outcome.hits = hits
	return outcome


func test_one_mark_rides_every_inner_hit_at_the_sims_reach() -> void:
	var hits := _detonate()
	var inner := _inner(hits)
	assert_gt(inner.size(), 1, "fixture: the blast lands inner hits")
	var mark: BlastMark = inner[0].blast_mark
	assert_not_null(mark, "the blast stamps its hits")
	if mark == null:
		return
	for h in inner:
		assert_true(is_same(h.blast_mark, mark), "one mark on every inner hit")
	var spread := _EXPLOSIVE.spread as ExplosiveSpread
	var power := DetonateEffect.power_of(3, 2, spread.resonance)
	assert_almost_eq(mark.reach, spread.radius_for(_f.target.radius, power), 0.001, "the sim's reach")
	assert_eq(mark.power, power, "the detonation's power reaches the mark")
	assert_true(is_same(mark.centre, _f.target), "centred on the struck node")
	assert_true(is_same(mark.attacker, _f.attacker), "the attacker's blast")
	assert_eq(mark.riders, [_POISON.identity, _BLIND.identity] as Array[Identity],
			"riders are the inners' status identities, explosive stripped")
	for h in hits:
		if h.target == _f.target:
			assert_null(h.blast_mark, "the centre's own hits carry no mark")


func test_a_live_apply_announces_the_blast_once() -> void:
	var hits := _detonate()
	watch_signals(Events)
	await OutcomeApplier.apply(_outcome(hits), CombatWorld.live())
	assert_signal_emit_count(Events, "blast_landed", 1, "once per mark")


func test_a_shadow_apply_never_announces() -> void:
	var hits := _detonate()
	watch_signals(Events)
	await OutcomeApplier.apply(_outcome(hits), CombatWorld.shadow())
	assert_signal_emit_count(Events, "blast_landed", 0, "a shadow world has no audience")


func test_a_blast_whose_hits_all_gated_never_announces() -> void:
	var hits := _detonate()
	for h in hits:
		h.gated = true
	watch_signals(Events)
	await OutcomeApplier.apply(_outcome(hits), CombatWorld.live())
	assert_signal_emit_count(Events, "blast_landed", 0, "a gated blast has no ring")


func test_a_later_ungated_hit_still_announces_a_mark_gated_hits_shared() -> void:
	var hits := _detonate()
	var inner := _inner(hits)
	inner[0].gated = true
	watch_signals(Events)
	await OutcomeApplier.apply(_outcome(hits), CombatWorld.live())
	assert_signal_emit_count(Events, "blast_landed", 1, "the gated hit does not spend the mark")


func test_two_marks_announce_twice() -> void:
	var hits := _detonate()
	var second := _detonate()
	assert_ne(_inner(second)[0].blast_mark, _inner(hits)[0].blast_mark, "fixture: two marks")
	hits.append_array(second)
	watch_signals(Events)
	await OutcomeApplier.apply(_outcome(hits), CombatWorld.live())
	assert_signal_emit_count(Events, "blast_landed", 2, "once per mark, not once per apply")



# The generation index (#1799) ─────────────────────────────────────────────────
## A two-link go-off chain on three fresh nodes of a default-board owner, all
## edge-linked to each other only so each has a threshold (read off the
## degree): a head on H, H's go-off reaching N1 and N1's reaching N2, both
## primed on Fire (whose band the test go-off holds).
## Returns `[outcome, H, N1, N2, authored hit count]`.
func _chain() -> Array:
	var holder := Entity.new()
	holder.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_f.graph.add_child(holder)
	var nodes: Array[SkillNode] = []
	for id: StringName in [&"gen_h", &"gen_n1", &"gen_n2"]:
		var n := _f.world.add_node(id, Vector2(600 + 40 * nodes.size(), 400))
		n.owned_by = holder
		nodes.append(n)
	for pair in [[0, 1], [1, 2], [0, 2]]:
		_f.world.link(nodes[pair[0]], nodes[pair[1]])
	await get_tree().process_frame
	var goff := _ChainGoOff.new()
	goff.reach_of = {nodes[0]: [nodes[1]], nodes[1]: [nodes[2]]}
	goff.lands_on_own_node = false
	var band := ElementBand.new()
	band.go_off = goff
	var fb: Array[ElementBand] = [band]
	_fire.bands = fb
	for n in nodes.slice(0, 2):
		var c := CombatWorld.live().combat_for(n)
		c.add_terrain(_fire, c.terrain_threshold() + 1 - c.terrain_t())
	var head := DamageInstance.new()
	head.target = nodes[0]
	head.attacker = _f.attacker
	head.amount = 2.0
	head.type = DamageInstance.Type.TRUE
	head.is_head = true
	var outcome := AttackOutcome.new()
	outcome.hits.append(head)
	return [outcome, nodes[0], nodes[1], nodes[2], outcome.hits.size()]


## The one mark on the entries past [param authored] that landed on [param at].
func _mark_on(hits: Array[HitInstance], authored: int, at: SkillNode) -> BlastMark:
	var marks: Array = []
	for h in hits.slice(authored):
		if h.target == at and not marks.has(h.blast_mark):
			marks.append(h.blast_mark)
	assert_eq(marks.size(), 1, "fixture: one mark on %s's entries" % at.name)
	return marks[0] if marks.size() == 1 else null


func test_the_gather_stamps_each_mark_with_the_generation_its_go_off_fired_at() -> void:
	var c: Array = await _chain()
	var outcome: AttackOutcome = c[0]
	HitGather.stage_one(outcome.hits.duplicate(), CombatWorld.live(), HitQueue.over(outcome.hits))
	var from_h := _mark_on(outcome.hits, c[4], c[2])
	var from_n1 := _mark_on(outcome.hits, c[4], c[3])
	assert_not_null(from_h, "H's go-off marks N1's entries")
	assert_not_null(from_n1, "N1's go-off marks N2's entries")
	if from_h == null or from_n1 == null:
		return
	assert_eq([from_h.centre, from_n1.centre], [c[1], c[2]], "fixture: one mark per link, at its centre")
	assert_eq([from_h.generation, from_n1.generation], [0, 1],
			"the beat's own arrival sets off generation 0; its copy, generation 1")


func test_a_record_rebuilds_each_mark_with_its_generation() -> void:
	var c: Array = await _chain()
	var outcome: AttackOutcome = c[0]
	await OutcomeApplier.drain(HitQueue.over(outcome.hits), CombatWorld.live(), BeatClock.instant_clock())
	var d := AttackRecord.capture(outcome, _f.graph)
	assert_true(d.has(AttackRecord.KEY_BLAST_GENERATION), "a generation past 0 writes the column")
	var rebuilt := AttackRecord.rebuild(d, _f.graph)
	var from_h := _mark_on(rebuilt.hits, c[4], c[2])
	var from_n1 := _mark_on(rebuilt.hits, c[4], c[3])
	if from_h == null or from_n1 == null:
		return
	assert_eq([from_h.generation, from_n1.generation], [0, 1], "the rebuilt marks keep their generations")

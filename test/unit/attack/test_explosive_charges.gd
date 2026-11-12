extends GutTest

## The explosive charge status (#1594): its def's decay, its death removal
## (every charge spent at once) and [method ExplosiveSpread.radius_for]'s
## shape. Ratios, never the authored literals — knobs move.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EXPLOSIVE_PATH := "res://effects/status/explosive.tres"

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _nodes: Array[SkillNode] = []


func before_each() -> void:
	_graph = TestWorld.create(self).graph
	_alloc = TestWorld.allocator_for(_graph)
	_entity = autofree(Entity.new())
	_entity.display_name = "Bomber"
	_entity.stat_board = TestBoards.flat_entity_board()
	_graph.add_child(_entity)
	_nodes = []
	for i in 2:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	_graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame
	_alloc.force_allocate(_entity, _nodes[0])
	_entity.core_location = _nodes[0]


func _def() -> StatusDef:
	return load(_EXPLOSIVE_PATH) as StatusDef


func _spread() -> ExplosiveSpread:
	return _def().spread as ExplosiveSpread


# --- acceptance 8: radius_for ratios ---------------------------------------

func test_radius_doubles_with_node_radius() -> void:
	var s := ExplosiveSpread.new()
	var r := s.radius_for(32.0, 1)
	assert_gt(r, 0.0, "one charge reaches somewhere")
	assert_almost_eq(s.radius_for(64.0, 1) / r, 2.0, 0.0001, "the bomb is the node: radius scales linearly")


func test_radius_doubles_when_charges_go_times_four() -> void:
	var s := ExplosiveSpread.new()
	assert_almost_eq(s.radius_for(32.0, 12) / s.radius_for(32.0, 3), 2.0, 0.0001, "sqrt(charges)")


func test_radius_flat_at_exponent_zero() -> void:
	var s := ExplosiveSpread.new()
	s.charge_exponent = 0.0
	assert_almost_eq(s.radius_for(32.0, 9), s.radius_for(32.0, 1), 0.0001, "exponent 0 ignores charges")


func test_radius_zero_without_charges() -> void:
	assert_eq(ExplosiveSpread.new().radius_for(32.0, 0), 0.0, "no charge, no boom")


# --- acceptance 6: decay ------------------------------------------------------

func test_two_charges_lose_per_tick_at_turn_end() -> void:
	var def := _def()
	assert_not_null(def, "explosive.tres authored")
	var per_tick: float = (def.decay as FlatDecay).per_tick
	var c := _nodes[0].get_combat()
	c.apply_status(def, 2.0)
	c.tick_statuses()
	assert_almost_eq(c.get_status_power(def.id), 2.0 - per_tick, 0.0001, "decays by per_tick at turn end")


# --- acceptance 5: death spends every charge at once -------------------------

func test_death_removal_spends_all_charges_in_one_transfer() -> void:
	var def := _def()
	var c := _nodes[0].get_combat()
	c.apply_status(def, 3.0)
	var field := StackField.over_world(def, def.spread.ownership_mask, CombatWorld.live(), [_nodes[0]], _graph)
	var removed: Array[NodeCombat] = [c]
	var out := _spread().on_removed(field, removed, StatusSpread.CAUSE_DEATH)
	assert_eq(out.size(), 1, "one spend, not one per charge")
	assert_null(out[0].to, "charges burn, never spill onto a neighbour")
	assert_eq(out[0].amount, 3.0, "every charge is spent")


func test_dealloc_spends_nothing() -> void:
	var def := _def()
	var c := _nodes[0].get_combat()
	c.apply_status(def, 3.0)
	var field := StackField.over_world(def, def.spread.ownership_mask, CombatWorld.live(), [_nodes[0]], _graph)
	var removed: Array[NodeCombat] = [c]
	assert_eq(_spread().on_removed(field, removed, StatusSpread.CAUSE_DEALLOC).size(), 0, "only a kill booms")


# --- blast_for: the one door every emitter builds its blast through ----------

func test_blast_for_reaches_radius_for_and_shares_a_finder_per_reach() -> void:
	var s := ExplosiveSpread.new()
	var inners: Array[OnHitEffect] = [DamageEffect.new()]
	var a := s.blast_for(_nodes[0], 4, inners)
	var b := s.blast_for(_nodes[0], 4, inners)
	assert_false(a.hits_centre, "the centre already took the hit")
	assert_eq(a.inners, inners, "the caller's riders ride")
	assert_almost_eq(a.range_finder.max_reach(), s.radius_for(_nodes[0].radius, 4), 0.0001, "reach is radius_for's")
	assert_same(a.range_finder, b.range_finder, "one finder per reach, so gather_cache dedupes")
	assert_ne(s.blast_for(_nodes[0], 1, inners).range_finder, a.range_finder, "another reach, another finder")


# --- detonation (1594b): acceptance 1-6, 9 of the 10-13 spec ------------------
# Board: VolleyBoardFixture — target (450,0) hostile; cluster[0] (600,0) and
# cluster[1] (700,100) hostile; the attacker's leaves west of the target.

const _POISON_ARROW: AmmoType = preload("res://attack/ammo/types/poison.tres")
const _POISON_DEF: StatusDef = preload("res://effects/status/poison.tres")

var _f: VolleyBoardFixture


## The board, with the target sized so 2 charges reach cluster[0] (150 px)
## and never cluster[1] (~269 px) — asserted, so a knob move fails loudly here.
func _board() -> void:
	_f = await VolleyBoardFixture.build(self, true)
	for leaf in _f.leaves:
		VolleyBoardFixture.set_stat(leaf, &"ranged_damage", 10.0)
	_f.target.base_radius = 40.0
	var r := _spread().radius_for(_f.target.radius, 2)
	assert_between(r, 151.0, 268.0, "fixture: 2 charges on the target reach cluster[0] only")


func _charge(node: SkillNode, n: float) -> void:
	node.get_combat().apply_status(_def(), n)


func _charges(node: SkillNode) -> float:
	return node.get_combat().get_status_power(&"explosive")


func _explosive_arrow() -> AmmoType:
	var apply := ApplyStatusEffect.new()
	apply.def = _def()
	apply.power = 1.0
	var ammo := AmmoType.new()
	ammo.id = &"test_explosive"
	ammo.on_hit_effects = [apply]
	return ammo


## One arrow off leaf_0 onto [param at] typed [param ammo] (null = plain).
func _shoot(ammo: AmmoType, at: SkillNode = null) -> Array[HitInstance]:
	var arrow := RangedDamageFormula.compute(_f.attacker, _f.leaves[0], at if at != null else _f.target, ammo)
	var hits: Array[HitInstance] = [arrow]
	hits.append_array(RangedDamageFormula.riders_for(arrow))
	return hits


func _cures_on(hits: Array, node: SkillNode) -> int:
	var n := 0
	for h in hits:
		if h is CureInstance and h.target == node:
			n += 1
	return n


func _blast_hits(hits: Array) -> Array:
	return hits.filter(func(h): return h is PairedDamageInstance)


func _status_on(hits: Array, node: SkillNode, id: StringName) -> Array:
	return hits.filter(func(h): return h is StatusInstance and h.target == node and h.def.id == id)


## Land every rider of [param hits] (all but the arrow) on the live board.
func _land(hits: Array) -> void:
	for h in hits:
		if h is CureInstance or h is StatusInstance:
			h.land_on(h.target.get_combat(), CombatWorld.live())


## Go-off zero's disc, as Explosive's aspect authors it.
func _disc() -> DiscGoOff:
	return (load("res://aspects/defs/explosive.tres") as Aspect).go_off as DiscGoOff


## Land [param hits] through the gather on the live world, beat by beat; the
## copies its go-offs appended past the authored hits.
func _fire(hits: Array[HitInstance]) -> Array[HitInstance]:
	var authored := hits.size()
	await OutcomeApplier.drain(HitQueue.over(hits), CombatWorld.live(), BeatClock.instant_clock())
	return hits.slice(authored)


## [param n] arrows onto the target, each its own schedule entry and so its own
## beat (one entry per hit outside a spell).
func _volley(n: int, ammo: AmmoType = null) -> Array[HitInstance]:
	var hits: Array[HitInstance] = []
	for i in n:
		for h in _shoot(ammo):
			h.schedule_index = i
			h.structural_key = float(i)
			hits.append(h)
	return hits


## The distinct marks on [param copies], in landing order.
func _marks(copies: Array) -> Array[BlastMark]:
	var out: Array[BlastMark] = []
	for h: HitInstance in copies:
		if h.blast_mark != null and not out.has(h.blast_mark):
			out.append(h.blast_mark)
	return out


func _poison_copies(copies: Array) -> Array:
	return copies.filter(func(h): return h is StatusInstance and h.def.id == _POISON_DEF.id)


func test_a_poison_arrow_on_two_charges_spends_one_and_blasts_poison_outward() -> void:
	await _board()
	_charge(_f.target, 2.0)
	var hits := _shoot(_POISON_ARROW)
	var own := _status_on(hits, _f.target, _POISON_DEF.id)
	var copies := await _fire(hits)
	assert_false(copies.is_empty(), "the blast throws shrapnel")
	for h in copies:
		assert_ne(h.target, _f.target, "never the centre")
	assert_true(copies.any(func(h): return h.target == _f.cluster[0]), "reaches the hostile in range")
	assert_false(copies.any(func(h): return h.target == _f.cluster[1]), "not past its reach")
	var rode := _status_on(copies, _f.cluster[0], _POISON_DEF.id)
	assert_eq(rode.size(), 1, "the poison rides the blast")
	if rode.size() == 1 and own.size() == 1:
		assert_eq(rode[0].power, ceilf(own[0].power * _disc().share), "a copy's rider lands ceil(r × share)")
	assert_false(hits.any(func(h): return h is CureInstance), "the spend lands at the read: no CureInstance")
	assert_almost_eq(_charges(_f.target), 1.0, 0.0001, "left holding 1 charge")


func test_explosive_only_landings_arm_and_never_fire() -> void:
	await _board()
	var ammo := _explosive_arrow()
	await _fire(_shoot(ammo))
	var per_landing := _charges(_f.target)
	assert_gt(per_landing, 0.0, "an explosive arrow plants")
	for i in 2:
		assert_true((await _fire(_shoot(ammo))).is_empty(), "an explosive-only hit never goes off")
	assert_almost_eq(_charges(_f.target), 3.0 * per_landing, 0.0001, "N landings leave N x one landing's charges")


func test_a_plain_arrow_on_a_charged_node_blasts_shrapnel_only() -> void:
	await _board()
	_charge(_f.target, 2.0)
	var copies := await _fire(_shoot(null))
	assert_almost_eq(_charges(_f.target), 1.0, 0.0001, "spends one")
	assert_false(copies.is_empty(), "a shrapnel blast")
	for h in copies:
		assert_true(h is DamageInstance, "shrapnel only: a plain arrow carries nothing else")


func _poison_rider() -> ApplyStatusEffect:
	var poison := ApplyStatusEffect.new()
	poison.def = _POISON_DEF
	return poison


## A spell landing on the target carrying [param effects] armed at [param load].
func _detonate(effects: Array[OnHitEffect], load: int) -> Array:
	var lctx := _spell_landing()
	OnHitEffect.run_all(DetonateEffect.arm(effects, load), lctx)
	return lctx.hits


func test_a_detonate_load_on_charges_spends_the_shared_chunk_and_blasts_poison() -> void:
	await _board()
	_charge(_f.target, 2.0)
	var hits := _detonate([_poison_rider()] as Array[OnHitEffect], 3)
	assert_eq(_cures_on(hits, _f.target), 1, "one blast, one spend")
	assert_eq(_status_on(hits, _f.cluster[0], _POISON_DEF.id).size(), 1, "poison rides the blast")
	for h in hits:
		if h is StatusInstance:
			assert_ne(h.def.id, &"explosive", "a DETONATE load plants nothing")
	_land(hits)
	assert_almost_eq(_charges(_f.target), 0.0, 0.0001, "spends max(1, min(3, 2)) = 2")


func test_spend_and_power_follow_the_formula() -> void:
	# [load, present, spent, power] at resonance 1.
	for row in [[3, 0, 0, 3], [3, 5, 3, 14], [3, 1, 1, 6], [0, 5, 1, 5], [0, 0, 0, 0], [3, 2, 2, 9]]:
		assert_eq(DetonateEffect.spend_of(row[0], row[1]), row[2], "spent for %s" % [row])
		assert_eq(DetonateEffect.power_of(row[0], row[1], 1), row[3], "power for %s" % [row])
	assert_eq(DetonateEffect.power_of(3, 2, 0), 5, "resonance 0: load + present")
	assert_eq(DetonateEffect.power_of(3, 2, 2), 13, "resonance weighs the shared chunk on each side")


func test_a_load_on_a_clean_node_blasts_and_spends_nothing() -> void:
	await _board()
	var hits := _detonate([] as Array[OnHitEffect], 3)
	assert_eq(_cures_on(hits, _f.target), 0, "nothing present, nothing spent")
	assert_false(_blast_hits(hits).is_empty(), "the load alone blasts")


func test_a_load_of_three_on_five_leaves_two() -> void:
	await _board()
	_charge(_f.target, 5.0)
	_land(_detonate([] as Array[OnHitEffect], 3))
	assert_almost_eq(_charges(_f.target), 2.0, 0.0001)


func test_a_load_of_three_on_one_leaves_none() -> void:
	await _board()
	_charge(_f.target, 1.0)
	var hits := _detonate([] as Array[OnHitEffect], 3)
	assert_false(_blast_hits(hits).is_empty(), "blasts")
	_land(hits)
	assert_almost_eq(_charges(_f.target), 0.0, 0.0001)


## A volley on a 5-charge node fires 5, 4, 3, 2, 1 with no ledger: each arrow is
## its own beat, and lands and spends on the world in turn.
func test_five_sparks_on_a_five_patch_each_take_one() -> void:
	await _board()
	_charge(_f.target, 5.0)
	var copies := await _fire(_volley(6))
	assert_eq(_marks(copies).map(func(m: BlastMark) -> int: return m.power), [5, 4, 3, 2, 1],
			"5, 4, 3, 2, 1 in turn; the sixth spark finds the patch spent")
	assert_almost_eq(_charges(_f.target), 0.0, 0.0001, "the patch is spent")


func test_a_plant_row_with_poison_on_a_charged_node_plants_and_never_blasts() -> void:
	await _board()
	_charge(_f.target, 2.0)
	var explosive := ApplyStatusEffect.new()
	explosive.def = _def()
	explosive.power = 1.0
	var hits := _detonate([_poison_rider(), explosive] as Array[OnHitEffect], 0)
	assert_eq(_cures_on(hits, _f.target), 0, "a PLANT hit spends nothing")
	assert_true(_blast_hits(hits).is_empty(), "nor blasts")
	assert_eq(_status_on(hits, _f.target, _POISON_DEF.id).size(), 1, "poison lands on the centre")
	var planted := _status_on(hits, _f.target, &"explosive")
	assert_eq(planted.size(), 1, "and the charge plants")
	_land(hits)
	assert_almost_eq(_charges(_f.target), 2.0 + planted[0].power, 0.0001, "nothing spent")


func test_a_chain_sets_each_charged_node_off_once_per_arrow() -> void:
	await _board()
	_charge(_f.target, 3.0)
	_charge(_f.cluster[0], 3.0)
	var hits := _shoot(_POISON_ARROW)
	var own := _status_on(hits, _f.target, _POISON_DEF.id)
	var copies := await _fire(hits)
	assert_almost_eq(_charges(_f.target), 2.0, 0.0001, "A blasts once, never twice")
	assert_almost_eq(_charges(_f.cluster[0]), 2.0, 0.0001, "A's blast sets B off, once")
	assert_eq(_marks(copies).filter(func(m: BlastMark) -> bool: return m.centre == _f.cluster[0]).size(), 1,
			"B's go-off is the chain's second link")
	var poison := _poison_copies(copies)
	assert_gt(poison.size(), 1, "fixture: both links carry the arrow's Poison")
	for h in poison:
		if own.size() == 1:
			assert_eq(h.power, ceilf(own[0].power * _disc().share), "flat: every link ceil(r × share), never share²")
	await _fire(_shoot(_POISON_ARROW))
	assert_almost_eq(_charges(_f.target), 1.0, 0.0001, "two arrows blast A twice")
	assert_almost_eq(_charges(_f.cluster[0]), 1.0, 0.0001, "and B twice")


## A head of one spell wave (beat 0, load 0) on [param at], as a landing places it.
func _wave_head(at: SkillNode) -> DamageInstance:
	var d := DamageInstance.new()
	d.target = at
	d.attacker = _f.attacker
	d.amount = 1.0
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	d.target_mask = SkillNode.Ownership.HOSTILE
	d.schedule_index = 0
	return d


## Two arrivals of one wave on one charged node both go off off one read of
## the pre-beat store; their spends are summed and clamped at 0.
func test_two_arrivals_of_one_wave_on_a_charged_node_both_go_off_off_one_read() -> void:
	await _board()
	_charge(_f.target, 3.0)
	var hits: Array[HitInstance] = [_wave_head(_f.target), _wave_head(_f.target)]
	var copies := await _fire(hits)
	assert_eq(_marks(copies).map(func(m: BlastMark) -> int: return m.power), [3, 3],
			"both go off, each reading the pre-beat 3")
	assert_almost_eq(_charges(_f.target), 1.0, 0.0001, "their spends summed: 3 − 1 − 1")
	_charge(_f.cluster[0], 1.0)
	var on_one: Array[HitInstance] = [_wave_head(_f.cluster[0]), _wave_head(_f.cluster[0])]
	await _fire(on_one)
	assert_almost_eq(_charges(_f.cluster[0]), 0.0, 0.0001, "two spends of 1 on 1 charge clamp at 0")


## Generations (ADR 0091 §1): one wave lands X on A (5 charges) and Y on B (3);
## A's disc reaches B, B's never A, and B's reaches C. Y sets B off in
## generation 0 off the pre-beat 3; X's copy reaches B in generation 1 and sets
## it off again off the 2 generation 0 left, never the pre-beat 3.
func test_a_copy_sets_a_node_off_again_a_generation_later_off_the_store_its_parent_left() -> void:
	await _board()
	var spread := _spread()
	var a := _f.world.add_node(&"gen_a", Vector2(0, 3000))
	var r := a.radius
	assert_between(6.0 * r, spread.radius_for(r, 3), spread.radius_for(r, 5), "fixture: A's disc reaches B, B's never A")
	var b := _f.world.add_node(&"gen_b", Vector2(7.0 * r, 3000))
	var c := _f.world.add_node(&"gen_c", Vector2(10.0 * r, 3000))
	_f.world.allocate(_f.hostile, [a, b, c])
	await get_tree().process_frame
	_charge(a, 5.0)
	_charge(b, 3.0)
	var outcome := AttackOutcome.new()
	outcome.hits.append_array([_wave_head(a), _wave_head(b)])
	var copies := await _fire(outcome.hits)
	var on_b := _marks(copies).filter(func(m: BlastMark) -> bool: return m.centre == b)
	assert_eq(on_b.map(func(m: BlastMark) -> Array: return [m.generation, m.power]), [[0, 3], [1, 2]],
			"B goes off in generation 0 off 3, then for X's copy in generation 1 off 2")
	var on_a := _marks(copies).filter(func(m: BlastMark) -> bool: return m.centre == a)
	assert_eq(on_a.map(func(m: BlastMark) -> int: return m.generation), [0], "X's go-off on A: generation 0")
	assert_almost_eq(_charges(b), 1.0, 0.0001, "B ends at 1")
	var rebuilt := AttackRecord.rebuild(AttackRecord.capture(outcome, _f.graph), _f.graph)
	var gens: Array = []
	for m in _marks(rebuilt.hits):
		gens.append(m.generation)
	gens.sort()
	assert_eq(gens, [0, 0, 1], "a record captured from the wave rebuilds those indices")


func test_no_hit_on_an_uncharged_node_blasts() -> void:
	await _board()
	assert_true((await _fire(_shoot(_POISON_ARROW))).is_empty(), "no charge, no boom")
	var plain := _shoot(null)
	assert_eq(plain.size(), 1, "a plain arrow emits nothing")
	assert_eq(plain[0].hit_key, 0, "and stays keyless")


# --- the booms never exceed the charges on the board ------------------------

func test_a_volley_on_one_charge_blasts_once() -> void:
	await _board()
	_charge(_f.target, 1.0)
	assert_eq(_marks(await _fire(_volley(3))).size(), 1, "one charge, one boom, however many arrows")
	assert_almost_eq(_charges(_f.target), 0.0, 0.0001, "and it is spent")


func test_a_core_hosted_charge_spends_off_the_entity() -> void:
	await _board()
	var core := _f.cluster[0]
	assert_true(core.get_combat().is_core(), "fixture: cluster[0] is the hostile core")
	_f.hostile.get_combat().apply_status(_def(), 2.0)
	await _fire(_shoot(null, core))
	assert_almost_eq(_f.hostile.get_combat().get_status_power(&"explosive"), 1.0, 0.0001,
			"the core-hosted charge sets off, spent off the entity")
	assert_almost_eq(_charges(core), 0.0, 0.0001, "the node held none and holds none")


## Open: the gather's stage one fires go-offs before any head's own gate runs
## (`OutcomeApplier.drain`), so an arrow its gate refuses still sets a charged
## node off. Whether a refused arrival goes off is undecided; held pending.
func test_a_dud_arrow_spends_no_charge() -> void:
	pending("a refused arrival still goes off at stage one: undecided (#1799 F-c2 report)")
	return
	@warning_ignore("unreachable_code")
	await _board()
	_charge(_f.target, 2.0)
	var hits := _shoot(null)
	hits[0].gated = true
	await _fire(hits)
	assert_almost_eq(_charges(_f.target), 2.0, 0.0001, "a dud spends nothing")


func _spell_landing() -> LandingContext:
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
	return LandingContext.for_test(payload, _f.target, cast)


# --- the shipped explosive arrow (#1398) ---------------------------------------

const _EXPLOSIVE_ARROW_PATH := "res://attack/ammo/types/explosive.tres"


func _shipped_explosive_arrow() -> AmmoType:
	var ammo := load(_EXPLOSIVE_ARROW_PATH) as AmmoType
	assert_not_null(ammo, "explosive.tres authored")
	return ammo


func test_three_shipped_explosive_arrows_plant_three_landings_and_never_fire() -> void:
	await _board()
	var ammo := _shipped_explosive_arrow()
	if ammo == null:
		return
	assert_true((await _fire(_shoot(ammo))).is_empty(), "the first plants")
	var per_landing := _charges(_f.target)
	assert_gt(per_landing, 0.0, "the shipped arrow plants")
	for i in 2:
		assert_true((await _fire(_shoot(ammo))).is_empty(), "an explosive arrow never goes off")
	assert_almost_eq(_charges(_f.target), 3.0 * per_landing, 0.0001, "three arrows, three landings' charges")


func test_a_poison_arrow_behind_a_shipped_explosive_arrow_cashes_one_charge_in() -> void:
	await _board()
	var ammo := _shipped_explosive_arrow()
	if ammo == null:
		return
	await _fire(_shoot(ammo))
	var planted := _charges(_f.target)
	assert_false((await _fire(_shoot(_POISON_ARROW))).is_empty(), "the follower blasts")
	assert_almost_eq(_charges(_f.target), planted - 1.0, 0.0001, "one charge gone")


func test_the_explosive_aspect_mints_the_shipped_arrow() -> void:
	var aspect := load("res://aspects/defs/explosive.tres") as Aspect
	assert_not_null(aspect.ammo, "explosive aspect sets ammo")
	if aspect.ammo != null:
		assert_eq(aspect.ammo.resource_path, _EXPLOSIVE_ARROW_PATH)

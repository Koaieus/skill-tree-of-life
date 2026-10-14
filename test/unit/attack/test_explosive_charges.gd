extends GutTest

## The explosive charge status (#1594): its def's decay, its death removal
## (every charge spent at once) and [method ExplosiveSpread.radius_for]'s
## shape. Ratios, never the authored literals — knobs move.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _EXPLOSIVE_PATH := "res://effects/status/explosive.tres"

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _nodes: Array[SkillNode] = []


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
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


func test_a_poison_arrow_on_two_charges_spends_one_and_blasts_poison_outward() -> void:
	await _board()
	_charge(_f.target, 2.0)
	var hits := _shoot(_POISON_ARROW)
	assert_eq(_cures_on(hits, _f.target), 1, "exactly one charge spent")
	var blast := _blast_hits(hits)
	assert_false(blast.is_empty(), "the blast throws shrapnel")
	for h in blast:
		assert_ne(h.target, _f.target, "never the centre")
	assert_true(blast.any(func(h): return h.target == _f.cluster[0]), "reaches the hostile in range")
	assert_false(blast.any(func(h): return h.target == _f.cluster[1]), "not past its reach")
	assert_eq(_status_on(hits, _f.cluster[0], _POISON_DEF.id).size(), 1, "the poison rides the blast")
	_land(hits)
	assert_almost_eq(_charges(_f.target), 1.0, 0.0001, "left holding 1 charge")


func test_explosive_only_landings_arm_and_never_fire() -> void:
	await _board()
	var ammo := _explosive_arrow()
	var one := _shoot(ammo)
	_land(one)
	var per_landing := _charges(_f.target)
	assert_gt(per_landing, 0.0, "an explosive arrow plants")
	for i in 2:
		var hits := _shoot(ammo)
		assert_eq(_cures_on(hits, _f.target), 0, "an explosive-only hit never spends")
		assert_true(_blast_hits(hits).is_empty(), "nor blasts")
		_land(hits)
	assert_almost_eq(_charges(_f.target), 3.0 * per_landing, 0.0001, "N landings leave N x one landing's charges")


func test_a_plain_arrow_on_a_charged_node_blasts_shrapnel_only() -> void:
	await _board()
	_charge(_f.target, 2.0)
	var hits := _shoot(null)
	assert_eq(_cures_on(hits, _f.target), 1, "spends one")
	var riders := hits.slice(1).filter(func(h): return not (h is CureInstance))
	assert_false(riders.is_empty(), "a shrapnel blast")
	for h in riders:
		assert_true(h is PairedDamageInstance, "shrapnel only: a plain arrow carries nothing else")
	assert_ne(hits[0].hit_key, 0, "the arrow keys its blast")


func test_a_spell_landing_with_poison_and_explosive_blasts_poison_then_plants() -> void:
	await _board()
	_charge(_f.target, 2.0)
	var poison := ApplyStatusEffect.new()
	poison.def = _POISON_DEF
	var explosive := ApplyStatusEffect.new()
	explosive.def = _def()
	var lctx := _spell_landing()
	OnHitEffect.run_all(DetonateEffect.arm([poison, explosive] as Array[OnHitEffect]), lctx)
	var hits := lctx.hits
	assert_eq(_cures_on(hits, _f.target), 1, "one blast, one spend")
	assert_eq(_status_on(hits, _f.cluster[0], _POISON_DEF.id).size(), 1, "poison rides the blast")
	for h in hits:
		if h is StatusInstance and h.def.id == &"explosive":
			assert_eq(h.target, _f.target, "explosive never rides a blast")
	var planted := _status_on(hits, _f.target, &"explosive")
	assert_eq(planted.size(), 1, "then the hit plants on the centre")
	_land(hits)
	var stacks: float = planted[0].power
	assert_almost_eq(_charges(_f.target), 2.0 - 1.0 + stacks, 0.0001, "net change is stacks - 1")


func test_a_chain_sets_each_charged_node_off_once_per_arrow() -> void:
	await _board()
	_charge(_f.target, 3.0)
	_charge(_f.cluster[0], 3.0)
	var one := _shoot(_POISON_ARROW)
	assert_eq(_cures_on(one, _f.target), 1, "A blasts once, never twice")
	assert_eq(_cures_on(one, _f.cluster[0]), 1, "A's blast sets B off")
	var two := one + _shoot(_POISON_ARROW)
	assert_eq(_cures_on(two, _f.target), 2, "two arrows blast A twice")
	assert_eq(_cures_on(two, _f.cluster[0]), 2, "and B twice")


func test_one_wave_touching_a_node_twice_blasts_it_once() -> void:
	await _board()
	_charge(_f.target, 3.0)
	var riders := DetonateEffect.arm([] as Array[OnHitEffect])
	var wave_scope := {}
	var hits: Array = []
	for i in 2:
		var lctx := _spell_landing()
		lctx.detonated = wave_scope
		OnHitEffect.run_all(riders, lctx)
		hits.append_array(lctx.hits)
	assert_eq(_cures_on(hits, _f.target), 1, "one blast per node per wave")


func test_no_hit_on_an_uncharged_node_blasts() -> void:
	await _board()
	var hits := _shoot(_POISON_ARROW)
	assert_eq(_cures_on(hits, _f.target), 0)
	assert_true(_blast_hits(hits).is_empty(), "no charge, no boom")
	var plain := _shoot(null)
	assert_eq(plain.size(), 1, "a plain arrow on an uncharged node emits nothing")
	assert_eq(plain[0].hit_key, 0, "and stays keyless")


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
	var all: Array = []
	var one := _shoot(ammo)
	all.append_array(one)
	_land(one)
	var per_landing := _charges(_f.target)
	assert_gt(per_landing, 0.0, "the shipped arrow plants")
	for i in 2:
		var hits := _shoot(ammo)
		all.append_array(hits)
		_land(hits)
	assert_eq(_cures_on(all, _f.target), 0, "an explosive arrow never spends a charge")
	assert_true(_blast_hits(all).is_empty(), "nor blasts")
	assert_almost_eq(_charges(_f.target), 3.0 * per_landing, 0.0001, "three arrows, three landings' charges")


func test_a_poison_arrow_behind_a_shipped_explosive_arrow_cashes_one_charge_in() -> void:
	await _board()
	var ammo := _shipped_explosive_arrow()
	if ammo == null:
		return
	_land(_shoot(ammo))
	var planted := _charges(_f.target)
	var hits := _shoot(_POISON_ARROW)
	assert_eq(_cures_on(hits, _f.target), 1, "the follower spends one charge")
	assert_false(_blast_hits(hits).is_empty(), "and blasts")
	_land(hits)
	assert_almost_eq(_charges(_f.target), planted - 1.0, 0.0001, "one charge gone")


func test_the_explosive_aspect_mints_the_shipped_arrow() -> void:
	var aspect := load("res://aspects/defs/explosive.tres") as Aspect
	assert_not_null(aspect.ammo, "explosive aspect sets ammo")
	if aspect.ammo != null:
		assert_eq(aspect.ammo.resource_path, _EXPLOSIVE_ARROW_PATH)

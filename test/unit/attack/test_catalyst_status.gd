extends GutTest

## The catalyst status (#1594): its def's world-turn decay and its death
## removal (every stack spent at once); then hits on a node Burning primes
## (Heat T + 1) through Burning's disc, and Catalyst landings that never set a
## node off. Knobs are read off the defs, never literals.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _CATALYST_PATH := "res://effects/status/catalyst.tres"

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _nodes: Array[SkillNode] = []


var _pay_pin: Array = []

func after_each() -> void:
	_unpin_pay_rule(_pay_pin)


func before_each() -> void:
	_pay_pin = _pin_pay_rule()
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
	return load(_CATALYST_PATH) as StatusDef


func _spread() -> CatalystSpread:
	return _def().spread as CatalystSpread



# --- world-turn decay ---------------------------------------------------------

func test_catalyst_keeps_at_turn_end_and_decays_per_tick_at_the_world_turn() -> void:
	var def := _def()
	assert_not_null(def, "catalyst.tres authored")
	var per_tick: float = (def.decay as FlatDecay).per_tick
	var c := _nodes[0].get_combat()
	c.apply_status(def, 2.0)
	c.tick_statuses()
	assert_almost_eq(c.get_status_power(def.id), 2.0, 0.0001, "no decay at the holder's turn end")
	CombatWorld.live().tick_world_turn_decay()
	assert_almost_eq(c.get_status_power(def.id), 2.0 - per_tick, 0.0001, "decays by per_tick at the world turn")


# --- death burns the whole row at once ----------------------------------------

func test_death_removal_burns_the_whole_row_in_one_transfer() -> void:
	var def := _def()
	var c := _nodes[0].get_combat()
	c.apply_status(def, 3.0)
	var field := StackField.over_world(def, def.spread.ownership_mask, CombatWorld.live(), [_nodes[0]], _graph)
	var removed: Array[NodeCombat] = [c]
	var out := _spread().on_removed(field, removed, StatusSpread.CAUSE_DEATH)
	assert_eq(out.size(), 1, "one spend, not one per stack")
	assert_null(out[0].to, "the row burns, never spills onto a neighbour")
	assert_eq(out[0].amount, 3.0, "every stack is spent")


func test_dealloc_spends_nothing() -> void:
	var def := _def()
	var c := _nodes[0].get_combat()
	c.apply_status(def, 3.0)
	var field := StackField.over_world(def, def.spread.ownership_mask, CombatWorld.live(), [_nodes[0]], _graph)
	var removed: Array[NodeCombat] = [c]
	assert_eq(_spread().on_removed(field, removed, StatusSpread.CAUSE_DEALLOC).size(), 0, "only a kill booms")


# --- Burning's disc on a primed node; Catalyst never goes off -----------------
# Board: VolleyBoardFixture — target (450,0) hostile; cluster[0] (600,0) and
# cluster[1] (700,100) hostile; the attacker's leaves west of the target.

const _POISON_ARROW: AmmoType = preload("res://attack/ammo/types/poison.tres")
const _POISON_DEF: StatusDef = preload("res://effects/status/poison.tres")

var _f: VolleyBoardFixture


## The board, with the target sized so Burning's power-1 disc reaches
## cluster[0] (150 px) and never cluster[1] (~269 px) — asserted, so a knob
## move fails loudly here.
func _board() -> void:
	_f = await VolleyBoardFixture.build(self, true)
	for leaf in _f.leaves:
		VolleyBoardFixture.set_stat(leaf, &"ranged_damage", 10.0)
	_f.target.base_radius = 40.0
	var r := _burning().disc_radius(1, _f.target.radius)
	assert_between(r, 151.0 - _f.cluster[0].radius, 268.0 - _f.cluster[1].radius,
			"fixture: a power-1 disc on the target reaches cluster[0] only")


func _burning() -> DiscGoOff:
	return ElementRoster.shared().by_id(&"fire").bands[0].go_off as DiscGoOff


## [param node]'s Heat set to its T + [param excess]: Burning, primed.
func _prime(node: SkillNode, excess: int) -> void:
	var c := node.get_combat()
	assert_gt(c.terrain_threshold(), 0, "fixture: %s has a T" % node.name)
	c.add_terrain(ElementRoster.shared().by_id(&"fire"), c.terrain_threshold() + excess - c.terrain_t())


func _heat(node: SkillNode) -> int:
	return node.get_combat().terrain_t()


func _plant(node: SkillNode, n: float) -> void:
	node.get_combat().apply_status(_def(), n)


func _stacks(node: SkillNode) -> float:
	return node.get_combat().get_status_power(&"catalyst")


func _catalyst_arrow() -> AmmoType:
	var apply := ApplyStatusEffect.new()
	apply.def = _def()
	apply.power = 1.0
	var ammo := AmmoType.new()
	ammo.id = &"test_catalyst"
	ammo.on_hit_effects = [apply]
	return ammo


## One arrow off leaf_0 onto [param at] typed [param ammo] (null = plain), its
## span placed as a volley places it: status riders ahead of their arrow.
func _shoot(ammo: AmmoType, at: SkillNode = null) -> Array[HitInstance]:
	var arrow := RangedDamageFormula.compute(_f.attacker, _f.leaves[0], at if at != null else _f.target, ammo)
	var hits: Array[HitInstance] = [arrow]
	RangedDamageFormula.ride(arrow, hits)
	return hits


func _status_on(hits: Array, node: SkillNode, id: StringName) -> Array:
	return hits.filter(func(h): return h is StatusInstance and h.target == node and h.def.id == id)


## Land [param hits] through the gather on the live world, beat by beat; the
## copies its go-offs appended past the authored hits.
func _fire(hits: Array[HitInstance]) -> Array[HitInstance]:
	var authored := hits.size()
	await OutcomeApplier.drain(HitQueue.over(hits), CombatWorld.live(), BeatClock.instant_clock())
	return hits.slice(authored)


func test_a_poison_arrow_on_a_burning_node_spends_heat_and_blasts_poison_outward() -> void:
	await _board()
	_prime(_f.target, 1)
	var before := _heat(_f.target)
	var hits := _shoot(_POISON_ARROW)
	var own := _status_on(hits, _f.target, _POISON_DEF.id)
	var copies := await _fire(hits)
	assert_false(copies.is_empty(), "the blast throws shrapnel")
	var centre := copies.filter(func(h): return h.target == _f.target)
	assert_eq(centre.filter(func(h): return h is DamageInstance).size(), 1, "the hit node takes its centre landing")
	assert_eq(_status_on(centre, _f.target, _POISON_DEF.id).size(), 1, "one landing per channel: its Poison too")
	assert_true(copies.any(func(h): return h.target == _f.cluster[0]), "reaches the hostile in range")
	assert_false(copies.any(func(h): return h.target == _f.cluster[1]), "not past its reach")
	var rode := _status_on(copies, _f.cluster[0], _POISON_DEF.id)
	assert_eq(rode.size(), 1, "the poison rides the blast")
	assert_eq(own.size(), 1, "fixture: the arrow carries one Poison rider")
	assert_eq(rode[0].power, ceilf(own[0].power * _burning().share), "a copy's rider lands ceil(r × share)")
	assert_false(hits.any(func(h): return h is CureInstance), "the spend lands at the read: no CureInstance")
	var marks := hits.filter(func(h): return h.blast_mark != null and h.blast_mark.centre == _f.target)
	assert_false(marks.is_empty(), "fixture: the go-off left its BlastMark")
	if marks.is_empty():
		return
	# The disc reaches every node in its radius, friend or foe; only hostiles take a copy.
	var reached := EuclideanRangeFinder.new().gather_reach(_f.target, _f.graph.navigator, marks[0].blast_mark.reach)
	reached.erase(_f.target)
	assert_gt(reached.size(), 1, "fixture: the disc reaches past the one hostile it hits")
	assert_eq(before - _heat(_f.target), reached.size(), "the disc spends Heat, 1 per other node reached")


func test_catalyst_only_landings_plant_and_never_go_off() -> void:
	await _board()
	var ammo := _catalyst_arrow()
	await _fire(_shoot(ammo))
	var per_landing := _stacks(_f.target)
	assert_gt(per_landing, 0.0, "an catalyst arrow plants")
	for i in 2:
		assert_true((await _fire(_shoot(ammo))).is_empty(), "an catalyst-only hit never goes off")
	assert_almost_eq(_stacks(_f.target), 3.0 * per_landing, 0.0001, "N landings leave N x one landing's stacks")


func test_a_plain_arrow_on_a_burning_node_blasts_shrapnel_only() -> void:
	await _board()
	_prime(_f.target, 1)
	var copies := await _fire(_shoot(null))
	assert_false(copies.is_empty(), "a shrapnel blast")
	for h in copies:
		assert_true(h is DamageInstance, "shrapnel only: a plain arrow carries nothing else")


func test_no_hit_on_an_unprimed_node_blasts() -> void:
	await _board()
	_plant(_f.target, 2.0)
	assert_true((await _fire(_shoot(_POISON_ARROW))).is_empty(), "Catalyst alone, no Burning: no boom")
	var plain := _shoot(null)
	assert_eq(plain[0].hit_key, 0, "a plain arrow stays keyless")
	assert_true((await _fire(plain)).is_empty(), "a plain arrow on Catalyst alone: no boom either")



## A dud arrow (its gate refuses: the target fell before it lands) takes no
## part in stage one: a primed node keeps its Heat and throws nothing, plain
## or typed (its status rider lands as a dud).
func test_a_dud_arrow_sets_off_nothing() -> void:
	for ammo: AmmoType in [null, _POISON_ARROW]:
		await _board()
		_prime(_f.target, 1)
		var hits := _shoot(ammo)
		_f.target.owned_by = null
		var c := _f.target.get_combat()
		assert_gt(c.terrain_t(), c.terrain_threshold(), "fixture: the fallen node is still primed")
		var before := _heat(_f.target)
		var copies := await _fire(hits)
		var arrow: HitInstance = hits.filter(func(h): return h is RangedDamageFormula.RangedHitInstance)[0]
		assert_true(arrow.gated, "fixture: the arrow is a dud")
		assert_eq(_heat(_f.target), before, "a dud arrow spends no Heat (%s)" % ammo)
		assert_eq(copies.size(), 0, "a dud arrow throws no copies (%s)" % ammo)
		CombatWorld.reset_live()


# --- the shipped catalyst arrow (#1398) ---------------------------------------

const _CATALYST_ARROW_PATH := "res://attack/ammo/types/catalyst.tres"


func _shipped_catalyst_arrow() -> AmmoType:
	var ammo := load(_CATALYST_ARROW_PATH) as AmmoType
	assert_not_null(ammo, "catalyst.tres authored")
	return ammo


func test_three_shipped_catalyst_arrows_plant_three_landings_and_never_go_off() -> void:
	await _board()
	var ammo := _shipped_catalyst_arrow()
	if ammo == null:
		return
	assert_true((await _fire(_shoot(ammo))).is_empty(), "the first plants")
	var per_landing := _stacks(_f.target)
	assert_gt(per_landing, 0.0, "the shipped arrow plants")
	for i in 2:
		assert_true((await _fire(_shoot(ammo))).is_empty(), "an catalyst arrow never goes off")
	assert_almost_eq(_stacks(_f.target), 3.0 * per_landing, 0.0001, "three arrows, three landings' stacks")


func test_the_catalyst_aspect_mints_the_shipped_arrow() -> void:
	var aspect := load("res://aspects/defs/catalyst.tres") as Aspect
	assert_not_null(aspect.ammo, "catalyst aspect sets ammo")
	if aspect.ammo != null:
		assert_eq(aspect.ammo.resource_path, _CATALYST_ARROW_PATH)


# --- not about the go-off pay rule ----------------------------------------------

## Pins the pre-floor bill on Fire's and Lightning's shared defs (no floor, the
## disc voids its per-reached Heat), holding both elements so the writes stay;
## [method _unpin_pay_rule] restores it. The pay rule's own cases live in
## `test/unit/elements/test_go_off_pay_rule.gd`.
func _pin_pay_rule() -> Array:
	var fire := ElementRoster.shared().by_id(&"fire")
	var light := ElementRoster.shared().by_id(&"lightning")
	var disc := fire.bands[0].go_off as DiscGoOff
	var edge := light.bands[0].go_off as EdgeGoOff
	var out := [fire, light, disc.void_floor, disc.spent_heat_goes_to, edge.void_floor]
	disc.void_floor = 0
	disc.spent_heat_goes_to = DiscGoOff.SpentHeatGoesTo.VOID
	edge.void_floor = 0
	return out


func _unpin_pay_rule(pin: Array) -> void:
	if pin.size() < 5:
		return
	var disc := (pin[0] as Element).bands[0].go_off as DiscGoOff
	var edge := (pin[1] as Element).bands[0].go_off as EdgeGoOff
	disc.void_floor = pin[2]
	disc.spent_heat_goes_to = pin[3]
	edge.void_floor = pin[4]

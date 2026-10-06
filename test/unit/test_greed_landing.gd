extends GutTest

## Greed's defender-side landing term: a debuff-tagged status landing on a host
## that holds Greed lands doubled, and each HIT (not each rider) spends one
## Greed stack. The hit is the [HitLanding]'s [member HitLanding.hit_key],
## carried on every [StatusInstance] it emits. A status on a cracked core
## falls through to the entity, so the entity's Greed is read only then.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GREED := preload("res://effects/status/greed.tres")
const _POISON := preload("res://effects/status/poison.tres")
const _CURSE := preload("res://effects/status/curse.tres")
const _SCOUTED := preload("res://effects/status/scouted.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _core: SkillNode
var _node: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Defender"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)

	_core = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(_core)
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(_node)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _core)
	_alloc.force_allocate(_entity, _node)
	_entity.core_location = _core


## One landing on [param target] carrying [param riders] (`[def, power]`
## pairs) — each rider an [ApplyStatusEffect], no attacker (authored power).
func _landing(target: SkillNode, riders: Array) -> Array[StatusInstance]:
	var landing := HitLanding.new()
	landing.target = target
	for r in riders:
		var effect := ApplyStatusEffect.new()
		effect.def = r[0]
		effect.power = r[1]
		effect.apply(landing)
	var out: Array[StatusInstance] = []
	for h in landing.hits:
		out.append(h as StatusInstance)
	return out


func _land(hits: Array[StatusInstance]) -> void:
	for h in hits:
		h.land_on(h.target.get_combat(), CombatWorld.live())


func _hit(target: SkillNode, riders: Array) -> void:
	_land(_landing(target, riders))


func _greed_on(n: SkillNode, stacks: float) -> void:
	n.get_combat().apply_status(_GREED, stacks)


func _power(n: SkillNode, id: StringName) -> float:
	return n.get_combat().get_status_power(id)


func test_each_landing_gets_its_own_key() -> void:
	var a := HitLanding.new()
	var b := HitLanding.new()
	assert_ne(a.hit_key, 0, "a landing is keyed")
	assert_ne(a.hit_key, b.hit_key, "two landings never share a key")


func test_the_rider_carries_its_landings_key() -> void:
	var hits := _landing(_node, [[_POISON, 1.0], [_CURSE, 1.0]])
	assert_eq(hits.size(), 2)
	assert_ne(hits[0].hit_key, 0)
	assert_eq(hits[0].hit_key, hits[1].hit_key, "riders of one hit share its key")


# 1
func test_one_greed_doubles_one_poison_hit_and_is_spent() -> void:
	_greed_on(_node, 1.0)
	_hit(_node, [[_POISON, 1.0]])
	assert_almost_eq(_power(_node, &"poison"), 2.0, 0.001, "poison doubled")
	assert_almost_eq(_power(_node, &"greed"), 0.0, 0.001, "greed spent")


# 2
func test_three_greed_over_four_hits_lands_2_2_2_1() -> void:
	_greed_on(_node, 3.0)
	var gains: Array[float] = []
	for i in 4:
		var before := _power(_node, &"poison")
		_hit(_node, [[_POISON, 1.0]])
		gains.append(_power(_node, &"poison") - before)
	assert_eq(gains, [2.0, 2.0, 2.0, 1.0] as Array[float], "owner's example")
	assert_almost_eq(_power(_node, &"greed"), 0.0, 0.001)


# 3
func test_two_riders_on_one_hit_both_double_for_one_spend() -> void:
	_greed_on(_node, 1.0)
	_hit(_node, [[_POISON, 1.0], [_CURSE, 1.0]])
	assert_almost_eq(_power(_node, &"poison"), 2.0, 0.001)
	assert_almost_eq(_power(_node, &"curse"), 2.0, 0.001)
	assert_almost_eq(_power(_node, &"greed"), 0.0, 0.001, "one spend per hit")


# Two landings whose riders interleave (A1, B1, A2) each spend once.
func test_interleaved_riders_spend_once_per_landing() -> void:
	_greed_on(_node, 1.0)
	var a := _landing(_node, [[_POISON, 1.0], [_CURSE, 1.0]])
	var b := _landing(_node, [[_POISON, 1.0]])
	_land([a[0], b[0], a[1]] as Array[StatusInstance])
	assert_almost_eq(_power(_node, &"poison"), 3.0, 0.001, "A doubled, B did not")
	assert_almost_eq(_power(_node, &"curse"), 2.0, 0.001, "A's second rider rides A's spend")
	assert_almost_eq(_power(_node, &"greed"), 0.0, 0.001)


# 4
func test_greed_on_a_clean_node_lands_plain() -> void:
	_hit(_node, [[_GREED, 2.0]])
	assert_almost_eq(_power(_node, &"greed"), 2.0, 0.001)


func test_greed_on_a_greedy_node_doubles_itself() -> void:
	_greed_on(_node, 1.0)
	_hit(_node, [[_GREED, 2.0]])
	assert_almost_eq(_power(_node, &"greed"), 4.0, 0.001, "1 − 1 + 2·2")


# 5
func test_a_non_debuff_is_never_doubled_and_spends_nothing() -> void:
	_greed_on(_node, 1.0)
	_hit(_node, [[_SCOUTED, 1.0]])
	assert_almost_eq(_node.get_combat().get_status_power(&"scout", &""), 1.0, 0.001,
			"scouted lands plain")
	assert_almost_eq(_power(_node, &"greed"), 1.0, 0.001, "greed unspent")


# 6
func test_a_rebuilt_instance_lands_its_recorded_power_and_still_spends() -> void:
	_greed_on(_node, 1.0)
	var hit := StatusInstance.new()
	hit.def = _POISON
	hit.power = 2.0
	hit.power_resolved = true
	hit.hit_key = HitLanding.new().hit_key
	hit.target = _node
	_land([hit] as Array[StatusInstance])
	assert_almost_eq(_power(_node, &"poison"), 2.0, 0.001, "recorded power, never doubled again")
	assert_almost_eq(_power(_node, &"greed"), 0.0, 0.001, "the live host spends what the shadow spent")


func test_the_record_round_trip_keeps_the_hit_key() -> void:
	var outcome := AttackOutcome.new()
	for h in _landing(_node, [[_POISON, 1.0]]):
		outcome.hits.append(h)
	var key: int = (outcome.hits[0] as StatusInstance).hit_key
	OutcomeApplier.apply(outcome, CombatWorld.live())
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _graph)))
	var rebuilt := AttackRecord.rebuild(wired, _graph)
	assert_eq((rebuilt.hits[0] as StatusInstance).hit_key, key, "the key rides the record")


# 7
func _crack_core() -> void:
	var crack := DamageInstance.new()
	crack.type = DamageInstance.Type.TRUE
	crack.amount = _core.get_combat().get_max_hp()
	_core.get_combat().take_damage(crack.amount, crack)
	assert_almost_eq(_core.get_current_hp(), 0.0, 0.001, "cracked shell")


func test_entity_greed_doubles_a_fallen_through_rider() -> void:
	_entity.get_combat().apply_status(_GREED, 1.0)
	_crack_core()
	var hits := _landing(_core, [[_POISON, 1.0]])
	_land(hits)
	assert_eq(hits[0].host_kind, StatusInstance.HostKind.ENTITY, "fell through")
	assert_almost_eq(_entity.get_combat().get_status_power(&"poison"), 2.0, 0.001, "doubled")
	assert_almost_eq(_entity.get_combat().get_status_power(&"greed"), 0.0, 0.001, "entity greed spent")


func test_entity_greed_is_dormant_for_a_hit_on_its_nodes() -> void:
	_entity.get_combat().apply_status(_GREED, 1.0)
	_hit(_node, [[_POISON, 1.0]])
	assert_almost_eq(_power(_node, &"poison"), 1.0, 0.001, "not doubled")
	assert_almost_eq(_entity.get_combat().get_status_power(&"greed"), 1.0, 0.001, "dormant")

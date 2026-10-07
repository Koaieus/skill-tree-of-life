extends GutTest

## Crit rolls at LANDING: each hit draws from the outcome's crit stream as it
## lands, in landing order, reading the landing world — so a status landed
## earlier in the same attack (a hex rider) reaches the crit chance of the
## hits behind it, and never the ones in front. A rebuilt record carries no
## stream and lands its recorded crits without drawing.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _HEXED := preload("res://effects/status/hexed.tres")
const _SEED := 0x1473

var _attacker: Entity
var _defender: Entity
var _graph: Graph
var _n: Dictionary = {}


func before_each() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	_graph = graph
	for i in 4:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = ["a0", "a1", "t", "u"][i]
		graph.add_skill_node(node)
		node.global_position = Vector2(i * 300.0, 0.0)
		_n[node.name] = node
	graph.add_edge(_n.a0, _n.a1)
	graph.add_edge(_n.a1, _n.t)
	graph.add_edge(_n.t, _n.u)

	_attacker = Entity.new()
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_attacker.stat_board.get_stat(&"crit_chance").base_value = 0.0
	graph.entities_container.add_child(_attacker)
	_defender = Entity.new()
	_defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(_defender)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(_attacker, _n.a0)
	alloc.force_allocate(_attacker, _n.a1)
	_attacker.core_location = _n.a0
	alloc.force_allocate(_defender, _n.t)
	alloc.force_allocate(_defender, _n.u)
	_defender.core_location = _n.u


func _arrow(key: float) -> DamageInstance:
	var hit := DamageInstance.new()
	hit.attacker = _attacker
	hit.read_node = _n.a1
	hit.origin = _n.a1
	hit.target = _n.t
	hit.amount = 1.0
	hit.structural_key = key
	return hit


func _hex_rider(key: float) -> StatusInstance:
	var hit := StatusInstance.new()
	hit.def = _HEXED
	hit.attacker = _attacker
	hit.read_node = _n.a1
	hit.origin = _n.a1
	hit.target = _n.t
	# Deep enough that the hexed chance clears 1.0 for a zero-crit attacker.
	hit.power = ceilf(1.5 / _HEXED.incoming_modifiers[0].value)
	hit.structural_key = key
	return hit


## arrow (key 0) → hex rider on the same node (key 0, after it) → arrow (key 1).
func _volley() -> AttackOutcome:
	var outcome := AttackOutcome.new()
	outcome.hits.append(_arrow(0.0))
	outcome.hits.append(_hex_rider(0.0))
	outcome.hits.append(_arrow(1.0))
	outcome.resolve_seed = _SEED
	outcome.crit_stream = CritRoll.stream_for(_SEED)
	return outcome


func _crits(outcome: AttackOutcome) -> Array:
	var out: Array = []
	for hit in outcome.hits:
		out.append([hit.is_crit, hit.crit_tier, hit.crit_multiplier])
	return out


# ── 1. A hex landed earlier in the attack reaches the hits behind it ───────

func test_an_arrow_behind_the_hex_rider_crits_and_one_in_front_does_not() -> void:
	var world := CombatWorld.shadow()
	var outcome := _volley()
	OutcomeApplier.apply(outcome, world)
	assert_almost_eq(CritRoll.chance_for(_arrow(1.0)), 0.0, 0.0001,
		"fixture: no crit without the hex")
	assert_false(outcome.hits[0].is_crit, "the arrow landing before the riders never saw the hex")
	assert_true(outcome.hits[2].is_crit, "the arrow landing after the riders reads the hex overlay")
	assert_eq(outcome.hits[2].crit_tier, 1, "one draw, stat path only")


# ── 2. Determinism ──────────────────────────────────────────────────────────

func test_the_same_seed_lands_the_same_crits() -> void:
	var a := _volley()
	OutcomeApplier.apply(a, CombatWorld.shadow())
	var b := _volley()
	OutcomeApplier.apply(b, CombatWorld.shadow())
	assert_eq(_crits(a), _crits(b))


func test_a_rebuilt_record_lands_its_recorded_crits_without_drawing() -> void:
	var resolved := _volley()
	OutcomeApplier.apply(resolved, CombatWorld.shadow())
	assert_true(resolved.hits[2].is_crit, "fixture: the resolve crit the trailing arrow")
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(resolved, _graph)))
	var rebuilt := AttackRecord.rebuild(wired, _graph)
	assert_null(rebuilt.crit_stream, "a record carries no crit stream")
	var sentinel_state: int = resolved.crit_stream.state
	# The live replay lands the recorded hex before the trailing arrow, so a
	# replay that drew would stack a second tier on top of the recorded one.
	OutcomeApplier.apply(rebuilt, CombatWorld.live())
	assert_eq(resolved.crit_stream.state, sentinel_state, "the replay never touches the stream")
	assert_false(rebuilt.hits[0].is_crit)
	assert_true(rebuilt.hits[2].is_crit, "the recorded crit lands")
	assert_eq(rebuilt.hits[2].crit_tier, 1, "recorded tier, never re-drawn")

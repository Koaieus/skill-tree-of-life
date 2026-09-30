extends GutTest

## ToggleGatesCommand (#1205): every flip applies first, connectivity is judged
## once (the owner's order-independence case), the host stamps the stranded set
## and it equals the preview, and validation refuses frozen / off-turn toggles.
##
## Board: owned `Core–A`, `Core–D`; gate G1 on `A–B` (open), gate G2 on `D–B`
## (closed); B owned. `O` belongs to another entity, gate GF on `B–O` (frozen).

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _applier: CommandApplier
var _player: Entity
var _other: Entity
var _nodes: Dictionary
var _g1: Gate
var _g2: Gate
var _gf: Gate
var _confirmed: Array[StringName]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = {}
	for id in ["Core", "A", "B", "D", "O"]:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = id
		_graph.add_skill_node(sn)
		_nodes[id] = sn
	_graph.add_edge(_n("Core"), _n("A"))
	_graph.add_edge(_n("Core"), _n("D"))
	_g1 = _graph.add_gate(_n("A"), _n("B"), true)
	_g2 = _graph.add_gate(_n("D"), _n("B"), false)
	_gf = _graph.add_gate(_n("B"), _n("O"), false)

	_tm = autofree(TurnManager.new())
	add_child(_tm)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	_alloc.navigator = _graph.navigator
	_alloc.turn_manager = _tm
	add_child_autofree(_alloc)

	_player = _entity("Player")
	_other = _entity("Other")
	await get_tree().process_frame

	_player.core_location = _n("Core")
	for id in ["Core", "A", "D", "B"]:
		_alloc.force_allocate(_player, _n(id))
	_other.core_location = _n("O")
	_alloc.force_allocate(_other, _n("O"))

	_applier = CommandApplier.new()
	_applier.graph = _graph
	_applier.allocation_system = _alloc
	_applier.turn_manager = _tm
	add_child_autofree(_applier)
	_confirmed = []
	_applier.command_confirmed.connect(func(c: Command) -> void: _confirmed.append(c.type_tag()))


func _entity(label: String) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.display_name = label
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(e)
	return e


func _n(id: String) -> SkillNode:
	return _nodes[id]


func _sid(id: String) -> int:
	return _graph.get_stable_id(_n(id))


func _pairs(gates: Array[Gate]) -> Array[int]:
	var out: Array[int] = []
	for g in gates:
		out.append(_graph.get_stable_id(g.from))
		out.append(_graph.get_stable_id(g.to))
	return out


func _run(command: Command) -> void:
	_applier.submit(command)
	while _applier.is_applying:
		await _applier.applying_changed


func _toggle(gates: Array[Gate]) -> ToggleGatesCommand:
	_tm.start_turn(_player)
	var cmd := ToggleGatesCommand.new(_player.entity_id, _pairs(gates))
	await _run(cmd)
	return cmd


func _wounded() -> int:
	return _player.stat_board.skill_points.wounded


# ── The owner's order-independence test ─────────────────────────────────────

func _assert_both_flips_keep_b(gates: Array[Gate]) -> void:
	assert_eq(_alloc.gate_flip_cascade(gates, _player), [] as Array[SkillNode],
			"preview: B stays reachable through the gate that opens")
	var cmd: ToggleGatesCommand = await _toggle(gates)
	assert_eq(_confirmed, [ToggleGatesCommand.TAG] as Array[StringName], "the toggle confirmed")
	assert_false(_g1.is_open(), "G1 closed")
	assert_true(_g2.is_open(), "G2 opened")
	assert_eq(_n("B").owned_by, _player, "B survives: connectivity is judged after every flip")
	assert_eq(cmd.stranded_ids, [] as Array[int], "nothing stamped")
	assert_eq(_wounded(), 0, "no wound")


func test_toggle_g1_then_g2_keeps_b() -> void:
	await _assert_both_flips_keep_b([_g1, _g2] as Array[Gate])


func test_toggle_g2_then_g1_keeps_b() -> void:
	await _assert_both_flips_keep_b([_g2, _g1] as Array[Gate])


func test_toggle_g1_alone_strands_b_with_the_cascade_charge() -> void:
	var gates: Array[Gate] = [_g1]
	var preview := _alloc.gate_flip_cascade(gates, _player)
	assert_eq(preview, [_n("B")] as Array[SkillNode], "preview strands B")
	var health := _player.stat_board.get_stat(&"health") as PoolStat
	var hp_before := health.current
	var cmd: ToggleGatesCommand = await _toggle(gates)
	assert_eq(cmd.stranded_ids, [_sid("B")] as Array[int], "host stamped exactly the preview")
	assert_null(_n("B").owned_by, "B deallocated")
	assert_eq(_wounded(), 1, "one wound, the normal cascade charge")
	assert_lt(health.current, hp_before, "and the core-HP chip")


# ── Preview equals the direct apply path ────────────────────────────────────

func test_direct_apply_strands_the_preview_g1_alone() -> void:
	var gates: Array[Gate] = [_g1]
	var preview := _alloc.gate_flip_cascade(gates, _player)
	assert_eq(_alloc.apply_gate_flip(gates, _player), preview)
	assert_null(_n("B").owned_by)


func test_direct_apply_strands_the_preview_both_orders() -> void:
	var gates: Array[Gate] = [_g2, _g1]
	var preview := _alloc.gate_flip_cascade(gates, _player)
	assert_eq(_alloc.apply_gate_flip(gates, _player), preview)
	assert_eq(_n("B").owned_by, _player)


func test_preview_mutates_nothing() -> void:
	var gates: Array[Gate] = [_g1, _g2]
	_alloc.gate_flip_cascade(gates, _player)
	assert_true(_g1.is_open())
	assert_false(_g2.is_open())
	assert_eq(_alloc.gate_flip_cascade([_g1] as Array[Gate], _player), [_n("B")] as Array[SkillNode],
			"mirror restored after the flood")


# ── Replay applies the stamped set without re-walking ───────────────────────

func test_recorded_apply_uses_the_stamped_set() -> void:
	var stranded: Array[SkillNode] = [_n("D")]
	_alloc.apply_gate_flip_recorded([_g1, _g2] as Array[Gate], _player, stranded)
	assert_null(_n("D").owned_by, "the recorded set, not a fresh walk")
	assert_eq(_n("B").owned_by, _player)


# ── Validation ──────────────────────────────────────────────────────────────

func test_refuses_a_frozen_gate() -> void:
	await _toggle([_gf] as Array[Gate])
	assert_eq(_confirmed, [] as Array[StringName])
	assert_false(_gf.is_open())


func test_refuses_an_off_turn_toggle() -> void:
	await _run(ToggleGatesCommand.new(_player.entity_id, _pairs([_g1] as Array[Gate])))
	assert_eq(_confirmed, [] as Array[StringName])
	assert_true(_g1.is_open())


func test_refuses_a_pair_naming_no_gate() -> void:
	_tm.start_turn(_player)
	var pairs: Array[int] = [_sid("Core"), _sid("A")]
	await _run(ToggleGatesCommand.new(_player.entity_id, pairs))
	assert_eq(_confirmed, [] as Array[StringName])


# ── Codec ───────────────────────────────────────────────────────────────────

func test_round_trips_through_the_codec() -> void:
	var pairs: Array[int] = [3, 4, 5, 6]
	var cmd := ToggleGatesCommand.new(7, pairs)
	cmd.stranded_ids = [9] as Array[int]
	var back := CommandCodec.from_dict(cmd.to_dict()) as ToggleGatesCommand
	assert_not_null(back)
	if back == null:
		return
	assert_eq(back.to_dict().hash(), cmd.to_dict().hash())
	assert_eq(back.pairs, pairs)
	assert_eq(back.stranded_ids, [9] as Array[int])
	assert_eq(back.type_tag(), ToggleGatesCommand.TAG)

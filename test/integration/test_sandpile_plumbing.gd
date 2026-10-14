extends GutTest

## Corruption's sandpile settles inside the beat that pushed it:
## [method CombatWorld.flush_removals] ends every beat with
## [method CombatWorld.settle_topples] (stabilize → burst → deaths → recompute
## degrees, repeat). An attack RECORDS its topples on the landing hit and a
## replay RECEIVES them. Corruption is the authored sandpile
## (burn 1, keep 0, Mine|Ally): a host topples at `T = masked degree + 1`.
## The core never topples here (#1568).

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _CORRUPTION := preload("res://effects/status/corruption.tres")


## A hit that reads [member watch]'s corruption in the world it lands in —
## what the next arrow "sees" — and lands nothing.
class Probe:
	extends HitInstance
	var watch: SkillNode
	var seen: float = -1.0

	func land_on(_node: NodeCombat, world: CombatWorld) -> void:
		seen = world.combat_for(watch).get_status_power(&"corruption")


var _graph: Graph
var _alloc: AllocationSystem
var _a: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_a = Entity.new()
	_a.name = "A"
	_a.display_name = "A"
	_a.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_a)
	await get_tree().process_frame


## [param count] nodes, the first [param owned] owned by A (index 0 its core),
## joined by [param edges] (index pairs).
func _territory(count: int, edges: Array, owned: int = -1) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for i in count:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.position = Vector2(i * 100, 0)
		_graph.add_skill_node(sn)
		out.append(sn)
	for e: Array in edges:
		_graph.add_edge(out[e[0]], out[e[1]])
	await get_tree().process_frame
	_alloc.force_allocate(_a, out[0])
	_a.core_location = out[0]
	for i in range(1, count if owned < 0 else owned):
		_alloc.force_allocate(_a, out[i])
	return out


func _stacks(n: SkillNode, world: CombatWorld = null) -> float:
	var w := world if world != null else CombatWorld.live()
	return w.combat_for(n).get_status_power(&"corruption")


func _hp(n: SkillNode, world: CombatWorld = null) -> float:
	var w := world if world != null else CombatWorld.live()
	return w.combat_for(n).get_current_hp()


## One corruption arrow: [param power] stacks, landed as-is, its own beat.
func _arrow(target: SkillNode, power: float, beat: int) -> StatusInstance:
	var s := StatusInstance.new()
	s.def = _CORRUPTION
	s.power = power
	s.power_resolved = true
	s.target = target
	s.schedule_index = beat
	s.structural_key = float(beat)
	return s


func _battle() -> void:
	var battle := BattleSystem.new()
	battle.allocation_system = _alloc
	battle.graph = _graph
	add_child_autofree(battle)


## C–1–2: 2 is a leaf (T 2) preseeded 1, 1 (T 3). Arrows 1, 2 put a stack each
## on 1; arrow 3 tips the leaf; arrow 4 is [param fourth].
func _volley(n: Array[SkillNode], fourth: HitInstance) -> AttackOutcome:
	n[2].get_combat().apply_status(_CORRUPTION, 1.0)
	var o := AttackOutcome.new()
	o.hits.append(_arrow(n[1], 1.0, 0))
	o.hits.append(_arrow(n[1], 1.0, 1))
	o.hits.append(_arrow(n[2], 1.0, 2))
	fourth.schedule_index = 3
	fourth.structural_key = 3.0
	o.hits.append(fourth)
	return o


# ── 1. The volley: arrow 3's topple lands inside arrow 3's beat ─────────────

func test_arrow_three_topples_the_leaf_and_arrow_four_sees_the_settled_pile() -> void:
	var n := await _territory(3, [[0, 1], [1, 2]])
	var probe := Probe.new()
	probe.target = n[2]
	probe.watch = n[1]
	var o := _volley(n, probe)
	var hp_before := _hp(n[2])
	var shadow := CombatWorld.shadow()
	OutcomeApplier.apply(o, shadow)
	# Leaf 2 → T: sends 1 to 1 (now 3 = T), burns 1. 1 topples: 1 to C, 1 to 2.
	assert_eq(probe.seen, 0.0, "arrow 4 sees 1 already toppled, not its pre-topple 3")
	assert_eq([_stacks(n[0], shadow), _stacks(n[1], shadow), _stacks(n[2], shadow)],
			[1.0, 0.0, 1.0], "the settled pile after arrow 3's beat")
	assert_lt(_hp(n[2], shadow), hp_before, "the leaf's burst damage landed")
	shadow.free_shadow()


# ── 2. A burst that kills: stacks vanish, a degree drop topples a neighbour ──

func test_a_burst_kill_drops_a_neighbours_threshold_and_it_topples_in_the_same_beat() -> void:
	# C–X, C–D, X–D. X (T 3) holds 1, D (T 3) is near death.
	var n := await _territory(3, [[0, 1], [0, 2], [1, 2]])
	var x := n[1]
	var d := n[2]
	x.get_combat().apply_status(_CORRUPTION, 1.0)
	var dc := d.get_combat()
	dc.take_damage(dc.get_current_hp() - 1.0, null)
	var x_hp := _hp(x)
	var o := AttackOutcome.new()
	o.hits.append(_arrow(d, 3.0, 0))
	var shadow := CombatWorld.shadow()
	OutcomeApplier.apply(o, shadow)
	assert_false(shadow.combat_for(d).is_allocated(), "D's burst killed it")
	assert_eq(_stacks(d, shadow), 0.0, "a dead node's stacks vanish")
	# D sent X 1 (X = 2 = T − 1); D died, X's T dropped to 2: X topples.
	assert_eq(_stacks(x, shadow), 0.0, "X toppled on its new degree in the same beat")
	assert_eq(_stacks(n[0], shadow), 2.0, "the core kept D's and X's stack")
	assert_lt(_hp(x, shadow), x_hp, "X's burst landed")
	shadow.free_shadow()


# ── 3. Dealloc / allocate commands move T ───────────────────────────────────

func test_deallocating_a_neighbour_pops_a_critical_node_inside_the_command() -> void:
	# C–X, C–Y, X–Y: X (T 3) at 2. Y leaves: X's T is 2.
	var n := await _territory(3, [[0, 1], [0, 2], [1, 2]])
	n[1].get_combat().apply_status(_CORRUPTION, 2.0)
	assert_true(_alloc.deallocate(n[2], _a), "precondition: the dealloc is legal")
	assert_eq(_stacks(n[1]), 0.0, "X popped inside the dealloc: 1 to C, 1 burned")
	assert_eq(_stacks(n[0]), 1.0, "the core received X's stack")


func test_allocating_a_neighbour_raises_t_and_nothing_pops() -> void:
	# C–X, X–Z, Z unowned. X (T 2) at 1; allocating Z makes it T 3.
	var n := await _territory(3, [[0, 1], [1, 2]], 2)
	n[1].get_combat().apply_status(_CORRUPTION, 1.0)
	_alloc.force_allocate(_a, n[2])
	CombatWorld.live().flush_removals()
	assert_eq(_stacks(n[1]), 1.0, "X still holds its stack")
	assert_eq(_stacks(n[2]), 0.0, "Z received nothing")


# ── 4. A recorded volley replays identically ────────────────────────────────

func test_a_recorded_volley_replays_identical_stacks_and_hp_on_the_live_world() -> void:
	var n := await _territory(3, [[0, 1], [1, 2]])
	var o := _volley(n, _arrow(n[2], 1.0, 3))
	var shadow := CombatWorld.shadow()
	OutcomeApplier.apply(o, shadow)
	var want := []
	for sn in n:
		want.append([_stacks(sn, shadow), _hp(sn, shadow)])
	shadow.free_shadow()
	var settles := 0
	for hit in o.hits:
		settles += hit.settle.size()
	assert_gt(settles, 0, "precondition: the shadow recorded its topples on the hits")

	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(o, _graph)))
	var rebuilt := AttackRecord.rebuild(wired, _graph)
	var rebuilt_settles := 0
	for hit in rebuilt.hits:
		rebuilt_settles += hit.settle.size()
	assert_eq(rebuilt_settles, settles, "the record carries every settle op")
	_battle()
	OutcomeApplier.apply(rebuilt, CombatWorld.live(), null, _alloc)
	var got := []
	for sn in n:
		got.append([_stacks(sn), _hp(sn)])
	assert_eq(got, want, "live replay lands the shadow's stacks and HP")


# ── 5. Turn end topples once ────────────────────────────────────────────────

func test_a_row_at_turn_end_never_topples_twice() -> void:
	# C–1–2, leaf 2 (T 2) handed 2 outside any beat: one topple at turn end.
	var n := await _territory(3, [[0, 1], [1, 2]])
	n[2].get_combat().apply_status(_CORRUPTION, 2.0)
	var hp := _hp(n[2])
	_a.resolve_turn_end()
	assert_eq([_stacks(n[1]), _stacks(n[2])], [1.0, 0.0], "one topple: 1 to node 1, 1 burned")
	var max_hp := n[2].get_combat().get_max_hp()
	assert_almost_eq(hp - _hp(n[2]), HitPoints.whole(2.0 * 0.02 * max_hp), 0.001,
			"exactly one burst (topples 1 × T 2 × 2%)")


func test_the_sandpile_turn_tick_moves_nothing_the_driver_owns_it() -> void:
	var n := await _territory(3, [[0, 1], [1, 2]])
	n[2].get_combat().apply_status(_CORRUPTION, 4.0)
	var def: StatusDef = _CORRUPTION
	var spread := def.spread as SandpileSpread
	assert_not_null(spread, "corruption's spread is a SandpileSpread")
	if spread == null:
		return
	var field := StackField.over_world(_CORRUPTION, spread.ownership_mask, CombatWorld.live(),
			[n[2]] as Array[SkillNode], _graph)
	assert_eq(spread.on_tick(field).size(), 0, "on_tick leaves topples to the settle driver")


# ── 6. A plain kill drops a neighbour's degree: the shadow still sees it ────

func test_a_corruption_free_kill_pops_its_critical_neighbour_in_the_shadow() -> void:
	# C–X, C–Y, X–Y: Y (T 3) at 2, X holds no corruption and dies.
	var n := await _territory(3, [[0, 1], [0, 2], [1, 2]])
	n[2].get_combat().apply_status(_CORRUPTION, 2.0)
	var o := AttackOutcome.new()
	var d := DamageInstance.new()
	d.target = n[1]
	d.amount = 1.0e6
	d.type = DamageInstance.Type.TRUE
	d.structural_key = 0.0
	o.hits.append(d)
	var shadow := CombatWorld.shadow()
	OutcomeApplier.apply(o, shadow)
	assert_false(shadow.combat_for(n[1]).is_allocated(), "precondition: X died")
	assert_eq(_stacks(n[2], shadow), 0.0, "Y's T dropped to 2: it popped in the kill's beat")
	assert_eq(_stacks(n[0], shadow), 1.0, "the core received Y's stack")
	shadow.free_shadow()


func test_the_live_replay_lands_the_recorded_bursts_not_its_own() -> void:
	var n := await _territory(3, [[0, 1], [1, 2]])
	var o := _volley(n, _arrow(n[2], 1.0, 3))
	var shadow := CombatWorld.shadow()
	OutcomeApplier.apply(o, shadow)
	shadow.free_shadow()
	var rebuilt := AttackRecord.rebuild(
			bytes_to_var(var_to_bytes(AttackRecord.capture(o, _graph))), _graph)
	var bursts := 0
	for hit in rebuilt.hits:
		for op in hit.settle:
			if op.threshold > 0:
				op.amount = 0.0
				bursts += 1
	assert_gt(bursts, 0, "precondition: the record carries bursts")
	var hp := []
	for sn in n:
		hp.append(_hp(sn))
	_battle()
	OutcomeApplier.apply(rebuilt, CombatWorld.live(), null, _alloc)
	var after := []
	for sn in n:
		after.append(_hp(sn))
	assert_eq(after, hp, "zeroed recorded bursts deal nothing: the replay computed none")


# ── 7. The worklist: settle visits what may topple, never the territory ─────

const _BLEEDING := preload("res://effects/status/bleeding.tres")


func _flush() -> CombatWorld:
	var w := CombatWorld.live()
	w.flush_removals()
	return w


func test_a_beat_with_no_sandpile_movement_visits_zero_holders() -> void:
	# A star of 6 around the core, no corruption anywhere.
	var n := await _territory(6, [[0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [1, 2]])
	_flush()  # drain whatever an earlier beat left on the live worklist
	assert_true(_alloc.deallocate(n[5], _a), "precondition: the dealloc is legal")
	assert_eq(CombatWorld.live().settle_visits, 0, "a corruption-free dealloc visits nothing")
	_a.resolve_turn_end()
	assert_eq(CombatWorld.live().settle_visits, 0, "a corruption-free turn end visits nothing")


func test_a_landing_visits_only_the_critical_node_and_its_fed_neighbours() -> void:
	# A 20-node line; node 10 (T 3) at 2.
	var edges := []
	for i in 19:
		edges.append([i, i + 1])
	var n := await _territory(20, edges)
	n[10].get_combat().apply_status(_CORRUPTION, 2.0)
	_flush()
	n[10].get_combat().apply_status(_CORRUPTION, 1.0)
	var w := _flush()
	assert_eq([_stacks(n[9]), _stacks(n[10]), _stacks(n[11])], [1.0, 0.0, 1.0],
			"node 10 toppled in the landing's beat")
	assert_between(w.settle_visits, 1, 3, "visits: node 10 plus its two masked neighbours at most")


func test_a_two_hop_cascade_settles_in_one_round() -> void:
	# C–a–b–c: a, b (T 3) at 2, leaf c (T 2) at 1.
	var n := await _territory(4, [[0, 1], [1, 2], [2, 3]])
	n[1].get_combat().apply_status(_CORRUPTION, 2.0)
	n[2].get_combat().apply_status(_CORRUPTION, 2.0)
	n[3].get_combat().apply_status(_CORRUPTION, 1.0)
	_flush()
	var hp := [_hp(n[1]), _hp(n[2]), _hp(n[3])]
	n[1].get_combat().apply_status(_CORRUPTION, 1.0)
	var w := _flush()
	# a → C, b; b → a, c; c → b: each toppled once.
	assert_eq([_stacks(n[0]), _stacks(n[1]), _stacks(n[2]), _stacks(n[3])],
			[1.0, 1.0, 1.0, 0.0], "a, then b, then c toppled once each")
	for i in 3:
		assert_lt(_hp(n[i + 1]), hp[i], "node %d burst" % (i + 1))
	assert_eq(w.settle_rounds, 1, "the cascade toppled inside one round")


func test_closing_a_gate_pops_a_critical_endpoint() -> void:
	# C–X, C–Y, gate X–Y: X (T 3) at 2; closing the gate makes X's T 2.
	var n := await _territory(3, [[0, 1], [0, 2]])
	var gate := _graph.add_gate(n[1], n[2], true)
	await get_tree().process_frame
	n[1].get_combat().apply_status(_CORRUPTION, 2.0)
	_flush()
	assert_eq(_stacks(n[1]), 2.0, "precondition: X is stable at degree 2")
	_alloc.apply_gate_flip([gate] as Array[Gate], _a)
	_flush()
	assert_eq(_stacks(n[1]), 0.0, "X popped inside the toggle-gates beat")
	assert_eq(_stacks(n[0]), 1.0, "the core received X's stack")


func test_a_core_move_pops_the_pile_on_the_departed_node() -> void:
	# C–X–N. X (T 3) at 2, N leaf (T 2) at 1.
	var n := await _territory(3, [[0, 1], [1, 2]])
	var x := n[1]
	var nn := n[2]
	_a.stat_board.movement_points.restore_to_full()
	x.get_combat().apply_status(_CORRUPTION, 2.0)
	nn.get_combat().apply_status(_CORRUPTION, 1.0)
	_flush()
	assert_true(_alloc.move_core(_a, x), "precondition: the core moves onto X")
	nn.get_combat().apply_status(_CORRUPTION, 1.0)
	_flush()
	assert_eq([_stacks(x), _stacks(nn)], [3.0, 0.0], "N toppled into X; X, the core, holds T")
	assert_true(_alloc.move_core(_a, n[0]), "precondition: the core moves off X")
	_flush()
	assert_eq([_stacks(n[0]), _stacks(x), _stacks(nn)], [1.0, 0.0, 1.0],
			"the departed X toppled exactly once")


func test_a_bleeding_grow_a_cure_and_a_crit_move_enqueue_nothing() -> void:
	var n := await _territory(3, [[0, 1], [1, 2]])
	var xc := n[1].get_combat()
	xc.apply_status(_CORRUPTION, 2.0)
	xc.apply_status(_BLEEDING, 1.0)
	_flush()
	xc.adjust_status_power(_BLEEDING, 2.0)
	xc.adjust_status_power(_CORRUPTION, -1.0)
	xc.on_crit_taken()
	var w := _flush()
	assert_eq(w.settle_visits, 0, "no rise of a sandpile row, no degree change: nothing visited")


func test_a_row_risen_before_a_replay_beat_is_checked_at_the_next_computing_flush() -> void:
	var n := await _territory(3, [[0, 1], [1, 2]])
	n[2].get_combat().apply_status(_CORRUPTION, 1.0)
	var w := CombatWorld.live()
	w.feed_settle([CombatWorld.SettleOp.new()] as Array[CombatWorld.SettleOp])
	w.flush_removals()
	assert_eq(w.settle_visits, 0, "a replay beat computes nothing")
	w.flush_removals()
	assert_eq(w.settle_visits, 1, "the risen row waited and was checked once")

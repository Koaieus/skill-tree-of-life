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

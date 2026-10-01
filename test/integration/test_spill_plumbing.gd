extends GutTest

## The removal collector on [CombatWorld]: every way a node leaves its owner
## (a voluntary dealloc, a cascade, a death) on either world feeds
## [method CombatWorld.note_removed], and the spill rule runs once per beat in
## [method CombatWorld.flush_removals] over the beat's whole removed union.
## Curse is the authored spiller (SpillSpread, both triggers, 1.0, Mine).

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _CURSE := preload("res://effects/status/curse.tres")


## Diffusion on the tick, spill on removal — one def that exercises both
## halves of the turn-end step, so the order between them is observable.
class SpillingDiffusion:
	extends DiffusionSpread
	var _spill := SpillSpread.new()

	func on_removed(field: StackField, removed: Array[NodeCombat], cause: int) -> Array[StackTransfer]:
		return _spill.on_removed(field, removed, cause)


## A DoT that kills its node from inside the tick, the way a lethal tick
## reaches [method BattleSystem._on_node_depleted]'s derive branch.
class KillerDef:
	extends StatusDef
	var alloc: AllocationSystem

	func _on_tick(node: NodeCombat, _before: float, _after: float) -> void:
		var ec := node.owner()
		ec.apply_cascade(ec.cascade_set(node), alloc)


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


## [param count] nodes owned by A, the first its core, joined by [param edges]
## (index pairs).
func _territory(count: int, edges: Array) -> Array[SkillNode]:
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
	for i in range(1, count):
		_alloc.force_allocate(_a, out[i])
	return out


func _chain(count: int) -> Array[SkillNode]:
	var edges := []
	for i in count - 1:
		edges.append([i, i + 1])
	return await _territory(count, edges)


func _curse(n: SkillNode) -> float:
	return n.get_combat().get_status_power(&"curse")


func _kill(target: SkillNode) -> AttackOutcome:
	var o := AttackOutcome.new()
	var d := DamageInstance.new()
	d.target = target
	d.amount = 1.0e6
	d.type = DamageInstance.Type.TRUE
	d.structural_key = 0.0
	o.hits.append(d)
	return o


# ── 1. A voluntary dealloc spills to the owned survivors ────────────────────

func test_voluntary_deallocate_spills_floor_half_to_each_of_two_survivors() -> void:
	# C–X, C–Y, X–Y: X leaves, C and Y stay connected and both border X.
	var n := await _territory(3, [[0, 1], [0, 2], [1, 2]])
	n[1].get_combat().apply_status(_CURSE, 5.0)
	assert_true(_alloc.deallocate(n[1], _a), "precondition: the dealloc is legal")
	assert_eq([_curse(n[0]), _curse(n[2])], [2.0, 2.0], "⌊5/2⌋ to each survivor")
	assert_eq(_curse(n[1]), 0.0, "the stripped node keeps nothing")


# ── 2. deallocate_set is one beat: its own members never receive ────────────

func test_deallocate_set_spills_over_the_union_only() -> void:
	var n := await _chain(4)  # 1C–2–3–4 as indices 0–1–2–3
	n[2].get_combat().apply_status(_CURSE, 4.0)
	n[1].get_combat().apply_status(_CURSE, 3.0)
	var dp := _a.stat_board.deallocation_points
	if dp != null:
		dp.restore_to_full()
	assert_true(_alloc.deallocate_set([n[1], n[2], n[3]] as Array[SkillNode], _a),
			"precondition: the set dealloc is legal")
	assert_eq(_curse(n[0]), 3.0, "2's curse lands on its one survivor, the core")
	assert_eq([_curse(n[1]), _curse(n[2]), _curse(n[3])], [0.0, 0.0, 0.0],
			"3's curse has no survivor around it and vanishes")


# ── 3. A real snipe: shadow preview and live landing agree ──────────────────

func test_sniped_chain_spills_identically_in_the_shadow_and_live() -> void:
	var n := await _chain(7)  # 1C–2–3X–4–5–6#–7
	n[2].get_combat().apply_status(_CURSE, 4.0)
	n[5].get_combat().apply_status(_CURSE, 4.0)

	var shadow := CombatWorld.shadow()
	OutcomeApplier.apply(_kill(n[2]), shadow)
	var preview: Array[float] = []
	for sn in n:
		preview.append(shadow.combat_for(sn).get_status_power(&"curse"))
	shadow.free_shadow()

	var battle := BattleSystem.new()
	battle.allocation_system = _alloc
	battle.graph = _graph
	add_child_autofree(battle)
	OutcomeApplier.apply(_kill(n[2]), CombatWorld.live(), null, _alloc)
	var landed: Array[float] = []
	for sn in n:
		landed.append(_curse(sn))

	assert_eq(preview, [0.0, 4.0, 0.0, 0.0, 0.0, 0.0, 0.0],
			"3's curse lands on 2; 6's has no survivor and vanishes")
	assert_eq(landed, preview, "the live landing agrees with the shadow preview")


# ── 4. Two cascades on one beat spill over their union ──────────────────────

func test_two_cascades_on_one_beat_share_one_union() -> void:
	# C–q, q–u, q–v, u–w, v–w: killing u leaves w hanging off v; killing v in
	# the same beat islands w. q borders both removed sets.
	var n := await _territory(5, [[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]])
	var q := n[1]
	var u := n[2]
	var v := n[3]
	u.get_combat().apply_status(_CURSE, 4.0)
	v.get_combat().apply_status(_CURSE, 4.0)
	var o := _kill(u)
	o.hits.append_array(_kill(v).hits)
	# One timeline event carrying both hits: one schedule entry, one beat.
	var ev := PropagationEvent.new()
	ev.target = u
	ev.hits.assign(o.hits)
	o.timeline.append(ev)

	var shadow := CombatWorld.shadow()
	OutcomeApplier.apply(o, shadow)
	var at := func(sn: SkillNode) -> float:
		return shadow.combat_for(sn).get_status_power(&"curse")
	assert_eq(at.call(q), 8.0, "q receives all of both: w, removed in the same beat, takes no share")
	assert_eq(at.call(n[4]), 0.0, "w, removed by v's cascade, receives nothing from u")
	shadow.free_shadow()


# ── 5. A DoT kill at turn end spills before the diffusion sweep ─────────────

func test_a_dot_kill_spills_before_the_diffusion_sweep_reads_the_field() -> void:
	var n := await _chain(3)  # C–1–2
	var seep := StatusDef.new()
	seep.id = &"seep"
	seep.power_max = 0.0
	seep.decay = FlatDecay.new(0.0)
	seep.spread = SpillingDiffusion.new()
	var killer := KillerDef.new()
	killer.id = &"killer"
	killer.power_max = 0.0
	killer.decay = FlatDecay.new(0.0)
	killer.alloc = _alloc
	n[2].get_combat().apply_status(seep, 4.0)
	n[2].get_combat().apply_status(killer, 1.0)

	_a.resolve_turn_end()
	var c := n[0].get_combat().get_status_power(&"seep")
	var one := n[1].get_combat().get_status_power(&"seep")
	assert_eq(n[2].owned_by, null, "precondition: the tick killed 2")
	assert_eq(c + one, 4.0, "all four stacks spilled to 1 and stayed in the territory")
	assert_gt(c, 0.0, "the sweep read the spilled field: 1 diffused onto the core")


# ── 6. Parity: a shadow cascade releases statuses ───────────────────────────

func test_a_shadow_cascade_releases_the_stripped_nodes_statuses() -> void:
	var n := await _chain(2)
	n[1].get_combat().apply_status(_CURSE, 3.0)
	var shadow := CombatWorld.shadow()
	var node := shadow.combat_for(n[1])
	shadow.combat_for_entity(_a).apply_cascade([node] as Array[NodeCombat])
	assert_true(node.get_statuses().is_empty(), "the shadow strip released the row")
	assert_eq(_curse(n[1]), 3.0, "the real node is untouched")
	shadow.free_shadow()

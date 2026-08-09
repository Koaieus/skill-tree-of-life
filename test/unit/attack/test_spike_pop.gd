extends GutTest

## #170 — defensive spikes pop an incoming enemy blade vertex. A popped vertex
## deals no more damage and *disconnects* everything downstream of it from the
## driven handle (those vertices disintegrate). Drives BladePopResolver directly
## with hand-built events + a BladeState so the kill + disconnection logic is
## tested deterministically, without the physics server. Also covers the
## SkillNode.get_spike_power predicate the resolver keys on.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SPIKE_SCENE := preload("res://skill_node/addons/spike_ring_addon.tscn")

const _SPIKE_POWER := 5.0


func _spawn_node(graph: Node, nm: String) -> SkillNode:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = nm
	graph.skill_nodes_container.add_child(node)
	return node


func _make_entity(graph: Node) -> Entity:
	var board: EntityStatBoard = _BOARD.duplicate(true)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	graph.add_child(entity)
	return entity


## Attacker owns nothing here that the resolver reads; defender owns a spiked
## node and a plain node. Returns graph, both entities, and the two target nodes.
func _setup() -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var attacker := _make_entity(graph)
	var defender := _make_entity(graph)

	var spike_node := _spawn_node(graph, "Spiked")
	var plain_node := _spawn_node(graph, "Plain")
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(defender, spike_node)
	alloc.force_allocate(defender, plain_node)

	# Spike is a plain direct child of the carrier (#334).
	var spike := _SPIKE_SCENE.instantiate() as SpikeRingAddon
	var mod := StatModifier.new()
	mod.stat_id = &"blade_damage"
	mod.operation = StatModifier.Operation.ADD_BONUS
	mod.value = _SPIKE_POWER
	spike.local_modifiers = [mod]
	spike_node.add_child(spike)

	return {
		"graph": graph, "attacker": attacker, "defender": defender,
		"spike_node": spike_node, "plain_node": plain_node,
	}


## A chain blade pivot(0)-A(1)-B(2)-C(3).
func _chain_state() -> BladeState:
	var positions: Array[Vector2] = [
		Vector2.ZERO, Vector2(50, 0), Vector2(100, 0), Vector2(150, 0)]
	var radii: Array[float] = [16.0, 16.0, 16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3)]
	return BladeState.build(positions, 0, edges, radii)


func _ev(t: float, particle_idx: int, target: SkillNode) -> BladeHitEvent:
	return BladeHitEvent.new(t, particle_idx, -1, target)


# ── Predicate ────────────────────────────────────────────────────────────────

func test_get_spike_power() -> void:
	var ctx: Dictionary = await _setup()
	assert_almost_eq((ctx.spike_node as SkillNode).get_spike_power(), _SPIKE_POWER,
			0.001, "spiked node reports its spike power")
	assert_almost_eq((ctx.plain_node as SkillNode).get_spike_power(), 0.0,
			0.001, "unspiked node reports 0")


# ── Pop kills the vertex + disconnects the downstream fragment ────────────────

func test_pop_kills_and_disconnects_downstream() -> void:
	var ctx: Dictionary = await _setup()
	var state := _chain_state()
	# Vertex 1 (A) sweeps into the spiked node at t=0.3.
	var events: Array[BladeHitEvent] = [_ev(0.3, 1, ctx.spike_node)]
	var res := BladePopResolver.resolve(events, state, ctx.attacker)

	assert_eq(res.pops.size(), 1, "one killing contact")
	assert_eq(res.pops[0].particle_idx, 1, "vertex 1 was popped")
	assert_eq(res.pops[0].defender, ctx.spike_node, "pop records the spiked node")

	# A is killed; B(2) and C(3) are severed from the pivot -> disintegrated.
	assert_true(res.is_dead(1, 0.3), "killed vertex is dead at contact time")
	assert_true(res.is_dead(2, 0.3), "downstream B disintegrates on disconnect")
	assert_true(res.is_dead(3, 0.3), "downstream C disintegrates on disconnect")
	assert_false(res.is_dead(0, 1.0), "pivot never dies")


func test_pre_kill_hits_still_land() -> void:
	var ctx: Dictionary = await _setup()
	var state := _chain_state()
	# Vertex 1 hits a plain node at t=0.1, THEN the spike at t=0.3.
	var events: Array[BladeHitEvent] = [
		_ev(0.1, 1, ctx.plain_node), _ev(0.3, 1, ctx.spike_node)]
	var res := BladePopResolver.resolve(events, state, ctx.attacker)
	assert_false(res.is_dead(1, 0.1), "hit before the pop still lands")
	assert_true(res.is_dead(1, 0.3), "the killing contact and later are dropped")


func test_disconnected_vertex_drops_its_later_hits() -> void:
	var ctx: Dictionary = await _setup()
	var state := _chain_state()
	# A pops at 0.3; B would hit a plain node at 0.5 but is already disintegrated.
	var events: Array[BladeHitEvent] = [
		_ev(0.3, 1, ctx.spike_node), _ev(0.5, 2, ctx.plain_node)]
	var res := BladePopResolver.resolve(events, state, ctx.attacker)
	assert_true(res.is_dead(2, 0.5), "severed vertex deals no damage downstream")


# ── Guards ───────────────────────────────────────────────────────────────────

func test_pivot_is_exempt() -> void:
	var ctx: Dictionary = await _setup()
	var state := _chain_state()
	# Pivot (0) overlapping a spiked node must not self-kill the blade.
	var events: Array[BladeHitEvent] = [_ev(0.2, 0, ctx.spike_node)]
	var res := BladePopResolver.resolve(events, state, ctx.attacker)
	assert_eq(res.pops.size(), 0, "pivot contact produces no pop")
	assert_false(res.is_dead(0, 1.0), "pivot stays alive")


func test_plain_node_does_not_pop() -> void:
	var ctx: Dictionary = await _setup()
	var state := _chain_state()
	var events: Array[BladeHitEvent] = [_ev(0.3, 1, ctx.plain_node)]
	var res := BladePopResolver.resolve(events, state, ctx.attacker)
	assert_eq(res.pops.size(), 0, "an unspiked enemy node never pops the blade")
	assert_false(res.is_dead(1, 0.3), "vertex survives a plain contact")


func test_attacker_own_spike_does_not_pop() -> void:
	var ctx: Dictionary = await _setup()
	var state := _chain_state()
	# Re-own the spiked node to the attacker: your own spikes can't pop your blade.
	(ctx.spike_node as SkillNode).owned_by = ctx.attacker
	var events: Array[BladeHitEvent] = [_ev(0.3, 1, ctx.spike_node)]
	var res := BladePopResolver.resolve(events, state, ctx.attacker)
	assert_eq(res.pops.size(), 0, "own-territory spike is not a defensive pop")


func test_persistent_pops_every_call() -> void:
	var ctx: Dictionary = await _setup()
	var state := _chain_state()
	var events: Array[BladeHitEvent] = [_ev(0.3, 1, ctx.spike_node)]
	var first := BladePopResolver.resolve(events, state, ctx.attacker)
	var second := BladePopResolver.resolve(events, state, ctx.attacker)
	assert_eq(first.pops.size(), 1, "first swing pops")
	assert_eq(second.pops.size(), 1, "spike is persistent — it pops again")


# ── Live swing wiring: MeleePreview._on_live_hit gating + pop signal ──────────

func _make_preview() -> MeleePreview:
	var preview := MeleePreview.new()
	add_child_autofree(preview)
	return preview


func test_live_dead_vertex_pops_once_and_deals_no_damage() -> void:
	var ctx: Dictionary = await _setup()
	var spike_node: SkillNode = ctx.spike_node
	var plain_node: SkillNode = ctx.plain_node
	var preview := _make_preview()
	preview._attacker = ctx.attacker
	preview._dead_at = {1: 0.3}
	preview._pending_pops = {
		1: BladePopResolver.Pop.new(1, 0.3, spike_node, spike_node.get_spike_power())}

	watch_signals(Events)
	var spike_hp := spike_node.get_current_hp()
	# The killing contact: vertex 1 reaches the spiked node at its death time.
	preview._on_live_hit(1, false, spike_node, 0.3, 999.0)
	assert_almost_eq(spike_node.get_current_hp(), spike_hp, 0.001,
			"the popping node takes no damage from the vertex it killed")
	assert_signal_emit_count(Events, "blade_vertex_popped", 1)

	# A later hit by the same (now disintegrated) vertex: no damage, no 2nd pop.
	var plain_hp := plain_node.get_current_hp()
	preview._on_live_hit(1, false, plain_node, 0.5, 999.0)
	assert_almost_eq(plain_node.get_current_hp(), plain_hp, 0.001,
			"a disintegrated vertex deals no further damage")
	assert_signal_emit_count(Events, "blade_vertex_popped", 1)


func test_live_alive_vertex_deals_damage() -> void:
	var ctx: Dictionary = await _setup()
	var plain_node: SkillNode = ctx.plain_node
	var preview := _make_preview()
	preview._attacker = ctx.attacker
	preview._dead_at = {}
	preview._pending_pops = {}

	watch_signals(Events)
	var before := plain_node.get_current_hp()
	preview._on_live_hit(0, false, plain_node, 0.1, 5.0)
	assert_true(plain_node.get_current_hp() < before,
			"a live vertex still applies its damage")
	assert_signal_emit_count(Events, "blade_vertex_popped", 0)

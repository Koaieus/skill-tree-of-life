extends GutTest

## Blade damage is per-node: each swept vertex deals its own
## get_local_value(&"blade_damage"), merging the wielder's board baseline with
## any node-local SpikeRing contribution. Guards the #-refactor that folded the
## old `base_damage + vertex_spikes[i]` split into one localized read, so
## preview (MeleeAttackPlan) and commit (SkillBlade) agree.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SPIKE_SCENE := preload("res://skill_node/addons/spike_ring_addon.tscn")

const _SPIKE_DAMAGE := 7.0


func _spawn_node(graph: Node, nm: String) -> SkillNode:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = nm
	graph.skill_nodes_container.add_child(node)
	return node


func _setup() -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var board: EntityStatBoard = _BOARD.duplicate(true)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	graph.add_child(entity)

	var source := _spawn_node(graph, "Source")
	var member := _spawn_node(graph, "Member")
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(entity, source)
	alloc.force_allocate(entity, member)

	# Spike goes on `member` only — a plain direct child of the carrier (#334).
	var spike := _SPIKE_SCENE.instantiate() as SpikeRingAddon
	var mod := StatModifier.new()
	mod.stat_id = &"blade_damage"
	mod.operation = StatModifier.Operation.ADD_BONUS
	mod.value = _SPIKE_DAMAGE
	spike.local_modifiers = [mod]
	member.add_child(spike)

	return {"graph": graph, "entity": entity, "source": source, "member": member}


# ── Merge linchpin: node-local spike stacks on the wielder's board ───────────

func test_spike_stacks_on_entity_blade_damage() -> void:
	var ctx: Dictionary = await _setup()
	var source: SkillNode = ctx.source
	var member: SkillNode = ctx.member
	# Both nodes share the same wielder (same board blade_damage). The only
	# difference is the +7 node-local spike on `member`.
	var base_dmg: float = float(source.get_local_value(&"blade_damage"))
	var spiked_dmg: float = float(member.get_local_value(&"blade_damage"))
	assert_almost_eq(spiked_dmg, base_dmg + _SPIKE_DAMAGE, 0.001,
			"spiked node must deal wielder base + spike")


func test_spike_removed_reverts_blade_damage() -> void:
	var ctx: Dictionary = await _setup()
	var member: SkillNode = ctx.member
	var source: SkillNode = ctx.source
	var spike := member.get_addons()[0]
	spike.free()
	await get_tree().process_frame
	assert_almost_eq(float(member.get_local_value(&"blade_damage")),
			float(source.get_local_value(&"blade_damage")), 0.001,
			"removing the spike (by identity) must revert to the bare wielder value")


# ── Production fill: build_blade_state writes per-vertex damage ───────────────

func test_build_blade_state_fills_per_vertex_damage() -> void:
	var ctx: Dictionary = await _setup()
	var entity: Entity = ctx.entity
	var source: SkillNode = ctx.source
	var member: SkillNode = ctx.member

	var plan := MeleeAttackPlan.new()
	plan.attacker = entity
	plan.source = source
	var members: Array[SkillNode] = [member]
	plan.blade_nodes = members

	var state := plan.build_blade_state()
	assert_not_null(state)
	# selection order is [source, member] — see build_blade_state.
	assert_almost_eq(state.vertex_damage[0], float(source.get_local_value(&"blade_damage")),
			0.001, "pivot vertex damage = its own blade_damage")
	assert_almost_eq(state.vertex_damage[1], state.vertex_damage[0] + _SPIKE_DAMAGE,
			0.001, "spiked member vertex carries base + spike")


# ── Live path: SkillBlade fills the same per-vertex damage ────────────────────

func test_skill_blade_build_fills_per_vertex_damage() -> void:
	var ctx: Dictionary = await _setup()
	var entity: Entity = ctx.entity
	var source: SkillNode = ctx.source
	var member: SkillNode = ctx.member

	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	add_child_autofree(blade)
	var nodes: Array[SkillNode] = [source, member]
	blade.build_from_skill_nodes(nodes, source, [], entity)

	# Same ordering ([source, member]) and same numbers as the plan path — the
	# two build sites must agree so preview matches commit.
	assert_almost_eq(blade.state.vertex_damage[0],
			float(source.get_local_value(&"blade_damage")), 0.001)
	assert_almost_eq(blade.state.vertex_damage[1],
			blade.state.vertex_damage[0] + _SPIKE_DAMAGE, 0.001,
			"live blade must localize spike damage identically to the plan")

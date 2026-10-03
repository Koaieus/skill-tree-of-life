extends GutTest

## `StatusDef.OnDealloc.LINGER` (#1344): a LINGER row survives deallocation
## (a CLEAR row beside it does not), and while its node is unowned it ticks
## once per ANY entity's [method Entity.resolve_turn_end] through the
## lingering-host registry on [method CombatWorld.live]. Re-allocated, it
## ticks on its new owner's turn end only; a death strip releases it. Every
## assertion counts turn ends — never frames or seconds.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
## A file-backed LINGER def (FlatDecay 1, power_max 10): the save interns
## statuses by `resource_path`, so the round-trip case needs a real path.
const _LINGER := preload("res://test/unit/effects/linger_status_fixture.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _a: Entity
var _b: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_a = _make_entity("A")
	_b = _make_entity("B")
	await get_tree().process_frame


func _make_entity(n: String) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.name = n
	e.display_name = n
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(e)
	return e


func _new_node() -> SkillNode:
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(n)
	return n


func _clear_def() -> StatusDef:
	var d := StatusDef.new()
	d.id = &"clearing"
	d.power_max = 10.0
	d.decay = FlatDecay.new(1.0)
	return d


## A node owned by [param owner] holding 5 LINGER stacks.
func _lingering_node(owner: Entity) -> SkillNode:
	var node := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(owner, node)
	node.get_combat().apply_status(_LINGER, 5.0)
	return node


func _power(node: SkillNode) -> float:
	return node.get_combat().get_status_power(_LINGER.id)


# ── (a) dealloc keeps LINGER, drops CLEAR ───────────────────────────────────

func test_linger_row_survives_force_deallocate_and_clear_row_does_not() -> void:
	var node := await _lingering_node(_a)
	node.get_combat().apply_status(_clear_def(), 4.0)
	_alloc.force_deallocate(node)
	assert_null(node.owned_by, "the node is unowned")
	assert_eq(_power(node), 5.0, "the LINGER row survives deallocation untouched")
	assert_eq(node.get_combat().get_status_power(&"clearing"), 0.0, "the CLEAR row is gone")
	assert_true(CombatWorld.live().is_lingering(node.get_combat()), "the unowned host registered")


# ── (b) unowned: one tick per entity turn end ───────────────────────────────

func test_unowned_linger_row_ticks_on_every_entitys_turn_end() -> void:
	var node := await _lingering_node(_a)
	_alloc.force_deallocate(node)
	_a.resolve_turn_end()
	assert_eq(_power(node), 4.0, "A's turn end ticks the unowned row once")
	_b.resolve_turn_end()
	assert_eq(_power(node), 3.0, "B's turn end ticks it once more")


func test_a_linger_def_lands_on_an_unowned_node() -> void:
	var node := _new_node()
	await get_tree().process_frame
	node.get_combat().apply_status(_LINGER, 2.0)
	assert_eq(_power(node), 2.0, "_may_host admits a LINGER def on an unallocated node")
	_b.resolve_turn_end()
	assert_eq(_power(node), 1.0)
	_b.resolve_turn_end()
	assert_eq(_power(node), 0.0, "decayed out")
	assert_false(CombatWorld.live().is_lingering(node.get_combat()), "its last row leaving unregisters it")


# ── (c) re-allocated: the new owner's turn end only ─────────────────────────

func test_reallocated_linger_row_ticks_only_on_the_new_owners_turn_end() -> void:
	var node := await _lingering_node(_a)
	_alloc.force_deallocate(node)
	_alloc.force_allocate(_b, node)
	assert_eq(_power(node), 5.0, "the row stays through re-allocation")
	_a.resolve_turn_end()
	assert_eq(_power(node), 5.0, "a non-owner's turn end no longer ticks it")
	_b.resolve_turn_end()
	assert_eq(_power(node), 4.0, "the new owner's turn end ticks it exactly once")
	assert_false(CombatWorld.live().is_lingering(node.get_combat()), "an owned host is not lingering")


# ── (d) death releases ──────────────────────────────────────────────────────

func test_a_death_strip_releases_the_linger_row() -> void:
	var core := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(_a, core)
	_a.core_location = core
	var node := await _lingering_node(_a)
	_alloc.deallocate_all_owned(_a)
	CombatWorld.live().flush_removals()
	assert_null(node.owned_by)
	assert_eq(_power(node), 0.0, "a death strip releases every row, LINGER included")
	_b.resolve_turn_end()
	assert_eq(_power(node), 0.0, "nothing is left to tick")


# ── shadow worlds never register ────────────────────────────────────────────

func test_a_shadow_slice_never_registers() -> void:
	var node := _new_node()
	await get_tree().process_frame
	var world := CombatWorld.shadow()
	var shadow := world.combat_for(node)
	shadow.apply_status(_LINGER, 3.0)
	assert_eq(shadow.get_status_power(_LINGER.id), 3.0, "the shadow holds the row")
	assert_false(CombatWorld.live().is_lingering(shadow), "a shadow host never reaches the live registry")
	world.free_shadow()


# ── (e) save -> load keeps ticking ──────────────────────────────────────────

func test_save_load_of_an_unowned_linger_row_keeps_ticking() -> void:
	var source := await _procgen_graph(12, 20261003)
	var target := await _procgen_graph_empty()
	var target_owner: Entity = autofree(Entity.new())
	target_owner.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	target.entities_container.add_child(target_owner)

	var node: SkillNode = source.get_skill_nodes()[0]
	assert_null(node.owned_by, "the source node is unowned")
	node.get_combat().apply_status(_LINGER, 4.0)
	GraphSnapshot.decode(GraphSnapshot.encode(source), target)

	var decoded := target.get_by_stable_id(source.get_stable_id(node))
	assert_eq(_power(decoded), 4.0, "the unowned node's LINGER row restored")
	assert_true(CombatWorld.live().is_lingering(decoded.get_combat()), "loading re-registers the host")
	target_owner.resolve_turn_end()
	assert_eq(_power(decoded), 3.0, "the restored row ticks on a turn end")


func _procgen_graph(node_count: int, seed_value: int) -> Graph:
	var graph := await _procgen_graph_empty()
	var cfg := GraphProcgenConfig.new()
	cfg.topology = GraphProcgenTopology.new()
	cfg.topology.node_count = node_count
	cfg.seed = seed_value
	cfg.shape = GraphProcgenShape.new()
	cfg.shape.shape_mask = CircularShapeMask.new()
	await GraphProcgen.generate(cfg, graph)
	return graph


func _procgen_graph_empty() -> Graph:
	var graph: Graph = autofree(_GRAPH_SCENE.instantiate())
	add_child(graph)
	await get_tree().process_frame
	return graph

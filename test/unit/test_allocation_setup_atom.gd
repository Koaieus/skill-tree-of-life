extends GutTest

## The 0->1 ownership setup side effects (owner, spikes, mirror, modifiers,
## effects, fill = 1) have one writer in AllocationSystem; allocate,
## force_allocate and register_scene_authored_ownership differ only in their
## SP accounting and whether they announce. Each path is pinned to the same
## world, and each teardown path to the world it started from.

const _SPIKE_SCENE := preload("res://skill_node/addons/defs/spike_ring_addon.tscn")
const _STR := 7.0

var _w: TestWorld
var _ent: Entity
var _node: SkillNode
var _base_str: float


func _strength_mod() -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"strength"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = _STR
	return m


## Core at `a`, the node under test is `b`. [param scene_authored] bakes
## `b.owned_by` before the entity enters the tree, the order a .tscn loads.
func _setup(scene_authored := false) -> void:
	_w = TestWorld.create(self)
	var a := _w.add_node(&"a", Vector2(0, 0))
	_node = _w.add_node(&"b", Vector2(100, 0))
	_w.link(a, _node)
	_node.modifiers = [_strength_mod()]
	_ent = TestWorld.new_entity("Red")
	_base_str = _ent.stat_board.get_stat(&"strength").value
	if scene_authored:
		a.owned_by = _ent
		_node.owned_by = _ent
		_w.graph.entities_container.add_child(_ent)
		_ent.core_location = a
	else:
		_w.graph.entities_container.add_child(_ent)
		_w.allocate(_ent, [a])
	await get_tree().process_frame


func _assert_owned_world(path: String) -> void:
	assert_eq(_node.owned_by, _ent, "%s: owner written" % path)
	assert_eq(_node.allocation_level, 1, "%s: first slot filled" % path)
	assert_true(_ent.navigator.get_mirrored_nodes().has(_node), "%s: mirrored" % path)
	assert_eq(_ent.stat_board.get_stat(&"strength").value, _base_str + _STR,
		"%s: node modifier on the owner's board" % path)
	assert_eq(_node.granted_entity_modifiers().size(), 1,
		"%s: one granted modifier handle" % path)
	assert_eq(_ent.stat_board.skill_points.used, 2, "%s: two SP used (a + b)" % path)


func _assert_stripped_world(path: String) -> void:
	assert_null(_node.owned_by, "%s: owner cleared" % path)
	assert_eq(_node.allocation_level, 0, "%s: fill cleared" % path)
	assert_false(_ent.navigator.get_mirrored_nodes().has(_node), "%s: unmirrored" % path)
	assert_eq(_ent.stat_board.get_stat(&"strength").value, _base_str,
		"%s: modifier off the board" % path)
	assert_eq(_ent.navigator.get_mirrored_nodes().size(), 1, "%s: core stays" % path)


# ── Setup: three callers, one world ──────────────────────────────────────────

func test_allocate_builds_the_owned_world_and_announces() -> void:
	await _setup()
	var alloc := _w.allocator()
	watch_signals(alloc)
	assert_true(alloc.allocate(_node, _ent))
	_assert_owned_world("allocate")
	assert_signal_emitted_with_parameters(alloc, "allocated", [_node, _ent, false])


func test_force_allocate_builds_the_owned_world_and_announces_forced() -> void:
	await _setup()
	var alloc := _w.allocator()
	watch_signals(alloc)
	alloc.force_allocate(_ent, _node)
	_assert_owned_world("force_allocate")
	assert_signal_emitted_with_parameters(alloc, "allocated", [_node, _ent, true])


func test_scene_authored_builds_the_owned_world_silently() -> void:
	await _setup(true)
	var alloc := _w.allocator()
	watch_signals(alloc)
	alloc.register_scene_authored_ownership()
	_assert_owned_world("scene-authored")
	assert_signal_not_emitted(alloc, "allocated", "level load emits no allocation")


## The setup atom restores a spiked node's pool on every 0->1 path, the
## scene-authored one included.
func test_scene_authored_restores_spikes_like_force_allocate() -> void:
	await _setup(true)
	_node.add_child(_SPIKE_SCENE.instantiate())
	await get_tree().process_frame
	var pool := _node.get_combat().board().get_stat(&"spikes") as PoolStat
	assert_not_null(pool, "spike ring mints a spikes pool")
	pool.restore_to_full()
	var full: float = pool.current
	assert_gt(full, 0.0, "a full ring has spikes")
	pool.deplete(full)
	_w.allocator().register_scene_authored_ownership()
	assert_eq(pool.current, full, "scene-authored ownership refills the spike ring")


# ── Teardown: both strip back to the pre-allocation world ────────────────────

func test_deallocate_strips_back_to_the_unowned_world() -> void:
	await _setup()
	var alloc := _w.allocator()
	alloc.force_allocate(_ent, _node)
	assert_true(alloc.deallocate(_node, _ent))
	_assert_stripped_world("deallocate")
	assert_eq(_ent.stat_board.skill_points.used, 1, "deallocate refunds the SP")


func test_force_deallocate_strips_back_to_the_unowned_world() -> void:
	await _setup()
	var alloc := _w.allocator()
	alloc.force_allocate(_ent, _node)
	assert_eq(alloc.force_deallocate(_node), _ent)
	CombatWorld.live().flush_removals()
	_assert_stripped_world("force_deallocate")

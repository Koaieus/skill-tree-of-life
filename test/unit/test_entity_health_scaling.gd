extends GutTest

## Entity `health` scales with CON through `core_health_scaling`, and the D-21
## ratchet grants the max delta as current HP. Acceptance for #276 / D-21 / D-26.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func _board() -> EntityStatBoard:
	var b := _BOARD.duplicate(true) as EntityStatBoard
	b.apply_intrinsics()
	return b


func _make_entity() -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "T"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	return ent


func _make_node() -> SkillNode:
	var n: SkillNode = _NODE_SCENE.instantiate()
	autofree(n)
	return n


func _mod(stat_id: StringName, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value
	return m


# --- 1. the pool exists, and CON moves it ---------------------------------

func test_core_health_scaling_present_on_default_board() -> void:
	assert_not_null(StatRegistry.get_def(&"core_health_scaling"),
		"core_health_scaling StatDef should be registered")
	var board := _board()
	assert_not_null(board.core_health_scaling, "default board should carry core_health_scaling")
	assert_almost_eq(float(board.core_health_scaling.get_value()), 1.0, 0.001,
		"D-26 default coefficient is 1.0 — every D-21 published number assumes it")


func test_health_max_is_base_plus_scaling_times_con() -> void:
	# Acceptance 1: at CON 109 with base 10 the pool is ~119.
	var board := _board()
	board.constitution.base_value = 109.0
	assert_almost_eq(float(board.health.get_value()), 119.0, 0.001,
		"health max should be 10 + core_health_scaling x CON")


func test_class_knob_resizes_the_pool() -> void:
	# Acceptance: a class overriding core_health_scaling changes its pool size.
	# Mutated at runtime on purpose — this is what catches a formula that failed
	# to declare core_health_scaling among its inputs (no reactive rebind).
	var board := _board()
	board.constitution.base_value = 100.0
	assert_almost_eq(float(board.health.get_value()), 110.0, 0.001, "precondition")

	board.core_health_scaling.base_value = 0.5
	assert_almost_eq(float(board.health.get_value()), 60.0, 0.001,
		"halving core_health_scaling should halve the CON term reactively")


# --- 2. the D-21 ratchet, through a real allocation ------------------------

func test_allocating_con_grants_the_max_hp_delta_as_current() -> void:
	# Acceptance 2: +40 CON -> +40 max AND +40 current. Driven through
	# force_allocate rather than a synthetic add_modifier, because the wiring
	# under test is the dependent-formula path (mod_con_to_health rebinding when
	# constitution moves), not add_modifier's own cap-change hook.
	var alloc := autofree(AllocationSystem.new()) as AllocationSystem
	var ent := _make_entity()
	var node := _make_node()
	add_child(alloc)
	add_child(ent)
	add_child(node)
	await get_tree().process_frame

	var health: PoolStat = ent.stat_board.health
	var max_before := float(health.get_value())
	var current_before := health.current
	node.modifiers.append(_mod(&"constitution", 40.0))

	alloc.force_allocate(ent, node)

	assert_almost_eq(float(health.get_value()), max_before + 40.0, 0.001,
		"+40 CON should raise max HP by 40")
	assert_almost_eq(health.current, current_before + 40.0, 0.001,
		"D-21: the max delta is granted as current HP")


func test_deallocating_con_clamps_current_but_does_not_subtract_it() -> void:
	# Acceptance 6: a damaged entity loses no current HP on dealloc; a healthy
	# one is clamped to the new max. The rejected alternative (subtract the
	# delta) would nearly kill a damaged entity for reshaping its graph.
	var alloc := autofree(AllocationSystem.new()) as AllocationSystem
	var ent := _make_entity()
	var node := _make_node()
	add_child(alloc)
	add_child(ent)
	add_child(node)
	await get_tree().process_frame

	# CON 100 so the entity survives the removal with headroom to spare —
	# D-21's worked example is current 30 / max 119 -> max 79, current 30.
	ent.stat_board.constitution.base_value = 100.0
	var health: PoolStat = ent.stat_board.health
	node.modifiers.append(_mod(&"constitution", 40.0))
	alloc.force_allocate(ent, node)
	var max_with_con := float(health.get_value())
	health.set_current(30.0)

	alloc.force_deallocate(node)

	assert_almost_eq(float(health.get_value()), max_with_con - 40.0, 0.001,
		"removing the node should drop max HP by the CON term")
	assert_almost_eq(health.current, 30.0, 0.001,
		"a damaged entity keeps its current HP — clamp-to-new-max, never subtract-the-delta")


func test_deallocating_con_clamps_a_full_pool_to_the_new_max() -> void:
	var alloc := autofree(AllocationSystem.new()) as AllocationSystem
	var ent := _make_entity()
	var node := _make_node()
	add_child(alloc)
	add_child(ent)
	add_child(node)
	await get_tree().process_frame

	var health: PoolStat = ent.stat_board.health
	node.modifiers.append(_mod(&"constitution", 40.0))
	alloc.force_allocate(ent, node)
	health.restore_to_full()

	alloc.force_deallocate(node)

	assert_almost_eq(health.current, float(health.get_value()), 0.001,
		"a full pool clamps down to the new max (not max - 40 twice over)")


# --- 3. the infinite-heal guard -------------------------------------------

func test_raising_max_dp_does_not_grant_a_spendable_point() -> void:
	# Acceptance 3, D-21's pinned guard: big CON + `+1 max DP` on one node is an
	# infinite heal ONLY if the raised DP maximum also hands over the point.
	# deallocation_points.tres therefore sets heal_on_max_increase = false.
	var alloc := autofree(AllocationSystem.new()) as AllocationSystem
	var ent := _make_entity()
	var node := _make_node()
	add_child(alloc)
	add_child(ent)
	add_child(node)
	await get_tree().process_frame

	var dp: SurplusPoolStat = ent.stat_board.deallocation_points
	var dp_max_before := float(dp.get_value())
	var dp_current_before := dp.current
	node.modifiers.append(_mod(&"deallocation_points", 1.0))

	alloc.force_allocate(ent, node)

	assert_almost_eq(float(dp.get_value()), dp_max_before + 1.0, 0.001,
		"the DP maximum should rise")
	assert_almost_eq(dp.current, dp_current_before, 0.001,
		"but no spendable DP is granted — that is the infinite-heal guard")


# --- 4. dealloc_damage regression (the paired class knob) -----------------

func test_dealloc_damage_is_an_ordinary_board_stat_a_class_can_modify() -> void:
	# D-21's "paired per-class knob" needs no bespoke mechanism: dealloc_damage
	# is a plain board stat, so a CoreClass tunes it with an ordinary modifier.
	var board := _board()
	assert_not_null(board.dealloc_damage)
	assert_almost_eq(float(board.dealloc_damage.get_value()), 1.0, 0.001, "default 1")
	board.add_modifier(_mod(&"dealloc_damage", 2.0))
	assert_almost_eq(float(board.dealloc_damage.get_value()), 3.0, 0.001,
		"a class modifier should move it like any other stat")

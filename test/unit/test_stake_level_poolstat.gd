extends GutTest

## #374 — stake_level as a PoolStat + proxy props on SkillNode.
##
## cap = `stake_level` (the stake ceiling), current = `allocation_level` (the
## fill). Both authored at SkillNode scope through proxy properties; the pool
## is minted on node_board by `_init_node_board` (called from _ready), and the
## pool's clamp replaces the old hand-written guard. `heal_on_max_increase =
## false` on the def, so a granted slot raises the cap WITHOUT auto-filling.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _STAKE_DEF := preload("res://stats_system/defs/stake_level.tres")

var _node: SkillNode
var _entity: Entity


func before_each() -> void:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	_entity = autofree(Entity.new())
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.add_child(_entity)
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	# Owned by default so _refresh_alloc_count keeps an authored fill (an
	# unowned node correctly zeroes it). Individual tests may author after.
	_node.owned_by = _entity


func after_each() -> void:
	if is_instance_valid(_node):
		_node.free()


func _add_to_tree() -> SkillNode:
	add_child(_node)
	await get_tree().process_frame
	return _node


func _pool() -> PoolStat:
	return _node.node_board.get_stat(&"stake_level") as PoolStat


# --- 1/2. pre-_ready authored values land in the pool after _ready -----------

func test_authored_stake_level_survives_into_pool_max_after_ready() -> void:
	_node.stake_level = 3
	await _add_to_tree()
	var pool := _pool()
	assert_not_null(pool, "the stake pool is minted on _ready")
	assert_eq(int(pool.value), 3, "authored cap survives into pool.max")
	assert_eq(_node.stake_level, 3, "proxy getter reads it back")


func test_authored_allocation_level_lands_in_pool_current() -> void:
	_node.stake_level = 3
	_node.allocation_level = 2
	await _add_to_tree()
	var pool := _pool()
	assert_eq(int(pool.current), 2, "authored fill lands in pool.current")
	assert_eq(_node.allocation_level, 2, "proxy getter reads it back")


# --- 3/4. pool semantics clamp, no hand-written guard ------------------------

func test_allocation_level_above_cap_clamps_to_cap() -> void:
	# stake_level stays at the default 1; the authored fill of 2 must clamp.
	_node.allocation_level = 2
	await _add_to_tree()
	assert_eq(_node.allocation_level, 1, "fill clamps to the cap (pool semantics)")
	assert_eq(int(_pool().current), 1)


func test_stake_level_below_fill_clamps_current_down() -> void:
	_node.stake_level = 3
	_node.allocation_level = 2
	await _add_to_tree()
	assert_eq(_node.allocation_level, 2, "2/3 starts unclamped")
	_node.stake_level = 1
	assert_eq(_node.allocation_level, 1, "cap fall clamps the fill down with it")
	assert_eq(int(_pool().current), 1)


# --- 5. on_cap_rise == PIN ---------------------------------------------------

func test_raising_cap_does_not_auto_fill() -> void:
	assert_eq((_STAKE_DEF as PoolStatDef).on_cap_rise, PoolStatDef.CapRise.PIN,
			"the def PINs on a cap rise — a granted slot must not mint a fill")
	_node.stake_level = 1
	_node.allocation_level = 1
	await _add_to_tree()
	_node.stake_level = 2
	assert_eq(_node.allocation_level, 1, "cap 1→2 leaves the fill at 1 (no auto-fill)")
	assert_eq(int(_pool().current), 1)


# --- 6. sparseness: reads never mint -----------------------------------------

func test_get_local_value_absent_stat_returns_entity_value_no_mint() -> void:
	await _add_to_tree()
	var v: Variant = _node.get_local_value(&"wisdom")
	assert_eq(v, 10, "absent local stat passes through to the entity board")
	assert_null(_node.node_board.get_stat(&"wisdom"),
			"get_local_value must not mint the stat on node_board")
	assert_null(_node.node_board.get_stat(&"armor"),
			"an untouched board stays sparse apart from the stake pool")


# --- 7. duplicate(true) round-trip (scene inheritance) ------------------------

func test_duplicate_round_trips_authored_values() -> void:
	# NOTE: a full deep duplicate (`duplicate(true)`) of this scene returns
	# null with "Required object rp_child is null" — reproduced on master on a
	# CLEAN instance, a pre-existing engine/scene bug unrelated to #374 (the
	# scene's instanced children; out of scope — skill_node.tscn is not owned
	# here). The property-copy mechanism scene inheritance uses (exported
	# properties copied via their setters) is exercised through
	# DUPLICATE_SCRIPTS, which is what the round-trip guarantee is about. The
	# copy is deliberately NOT added to the tree — a childless SkillNode's
	# _ready trips null @onready refs (another pre-existing fragility).
	_node.stake_level = 3
	_node.allocation_level = 2
	var copy := _node.duplicate(Node.DUPLICATE_SCRIPTS) as SkillNode
	assert_not_null(copy)
	if copy == null:
		return
	assert_eq(copy.stake_level, 3, "stake_level survives the property copy")
	assert_eq(copy.allocation_level, 2, "allocation_level survives the property copy")
	# The re-mint path (authored backing -> pool) is the same one _ready uses.
	copy._ensure_local_stat(&"stake_level")
	var copy_pool := copy.node_board.get_stat(&"stake_level") as PoolStat
	assert_not_null(copy_pool, "the copy mints its own pool on demand")
	assert_eq(int(copy_pool.value), 3, "mint pushes the copied cap")
	assert_eq(int(copy_pool.current), 2, "mint pushes the copied fill")
	copy.free()


# --- 8. the plain-int docstring is gone ---------------------------------------

func test_docstring_no_longer_describes_plain_ints() -> void:
	var src := FileAccess.get_file_as_string("res://skill_node/skill_node.gd")
	assert_false(src.contains("these are not Stats and must never be registered"),
			"the old 'plain int, never a Stat' docstring must be gone (#374 acceptance 8)")
	assert_true(src.contains("PROXY properties"), "the new proxy-pool docstring is present")

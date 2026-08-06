extends GutTest

## Allocation VFX live panel (#260) — the played showcase's heir. Asserts the
## embedded world builds (the 3×3 cell grid against the REAL systems via
## SandboxWorld) and that the explicit beats drive real state: ▶ Play beat
## allocates the single-node cell, ⟲ Reset strips it.

const _PANEL := preload("res://addons/allocation_sandbox/allocation_sandbox_panel.tscn")

var _panel


func before_each() -> void:
	_panel = _PANEL.instantiate()
	add_child(_panel)
	await get_tree().process_frame
	# Tiny holds so a beat completes in a few frames, not ~5 seconds.
	_panel.setup_hold = 0.05
	_panel.play_hold = 0.05


func after_each() -> void:
	_panel.queue_free()


func _entities() -> Array:
	return _panel.graph.get_node("Entities").get_children()


func test_world_builds_full_grid() -> void:
	# 3 single-node cells + 6 five-node cells = 33 nodes, one entity per cell.
	assert_eq(_panel.graph.get_skill_nodes().size(), 33,
		"grid must build 33 nodes")
	assert_eq(_entities().size(), 9, "grid must build 9 entities")


func test_ready_presents_cells_armed() -> void:
	# alloc_single starts with an EMPTY owned set — but a fully-allocated cell
	# (e.g. force_dealloc_first) must already own its row at rest. Node layout:
	# 3 single-node cells (0-2) then five 5-node cells (3-7, 8-12, 13-17,
	# 18-22, 23-27, 28-32); cell 6 (force_dealloc_first) spans nodes 18-22.
	var nodes: Array = _panel.graph.get_skill_nodes()
	var e = _entities()[6]   # force_dealloc_first: row 3, fully allocated
	assert_eq(nodes[18].owned_by, e, "armed grid must own the initial set")


func test_play_beat_runs_the_alloc_single_scenario() -> void:
	var nodes: Array = _panel.graph.get_skill_nodes()
	var e = _entities()[0]
	assert_null(nodes[0].owned_by, "alloc_single cell starts unowned")

	await _panel.play_beat()

	assert_eq(nodes[0].owned_by, e, "beat must allocate the single-node cell")
	var str_val: Variant = e.stat_board.get_value(&"strength")
	assert_gt(float(str_val), 0.0, "owned node's STR modifier must apply")
	assert_false(_panel._busy, "beat must clear the busy gate")


func test_reset_world_rearms_a_played_cell() -> void:
	var nodes: Array = _panel.graph.get_skill_nodes()
	var e = _entities()[0]
	await _panel.play_beat()
	assert_eq(nodes[0].owned_by, e)

	_panel.reset_world()

	assert_null(nodes[0].owned_by, "reset must strip the played allocation")

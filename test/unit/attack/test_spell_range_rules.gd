extends GutTest

## SpellRangeRules.reach() — the spell's authored reach folded as an overlay
## bin under `cast_range_hops` / `cast_range_distance`, in 3 tiers: the
## cast-from node's merged read (entity + node + overlay), the caster's board
## alone (the tooltip's no-cast-from-node preview), the raw authored number.
##
## Every value assert runs on a HAND-BUILT board with no intrinsics — the
## shipped boards' INT line is the owner's to tune; the two shipped-board tests
## at the bottom are structural, never goldens.

const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _DEFAULT_BOARD := preload("res://entity/default_entity_board.tres")
const _BLOCKER_BOARDS: Array[String] = [
	"res://entity/blocker/blocker_small_board.tres",
	"res://entity/blocker/blocker_medium_board.tres",
	"res://entity/blocker/blocker_large_board.tres",
]
const _INT_PACK := "res://procgen/pools/intelligence.tres"
const _SPELL_DEFS_DIR := "res://attack/spell/defs/"


## A bare EntityStatBoard holding only the two cast-range stats, minted off
## their registry defs, base 0, no intrinsics.
func _bare_board() -> EntityStatBoard:
	var board := EntityStatBoard.new()
	for id in [&"cast_range_hops", &"cast_range_distance"]:
		var s := ScalarStat.new()
		s.definition = StatRegistry.get_def(id)
		s.base_value = 0.0
		board.set(id, s)
	return board


func _node() -> SkillNode:
	var node := _NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	return node


## An owned node: a graph, an entity on [param board], one node force-allocated
## to it — so the node tier folds entity bins + node bins + the overlay.
func _owned_node(board: EntityStatBoard) -> Dictionary:
	var graph := preload("res://graph/graph.tscn").instantiate()
	add_child_autofree(graph)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	graph.add_child(entity)
	var node := _NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(node)
	autofree(node)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(entity, node)
	return {"entity": entity, "node": node}


func _static_mod(id: StringName, op: int, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = op as StatModifier.Operation
	m.value = value
	return m


# ── tier 1: the cast-from node's merged read ─────────────────────────────────


func test_node_local_increase_scales_the_authored_hops_and_floors_once() -> void:
	var o := _owned_node(_bare_board())
	var node: SkillNode = o["node"]
	node.add_local_modifier(_static_mod(&"cast_range_hops", StatModifier.Operation.INCREASE, 50.0))
	var finder := HopRangeFinder.new()
	finder.max_hops = 3

	assert_eq(finder.effective_max_hops(o["entity"], node), 4,
			"3 hops × 1.5 = 4.5, floored once by the INT stat → 4")


func test_node_local_add_base_and_multiply_fold_onto_the_authored_distance() -> void:
	var o := _owned_node(_bare_board())
	var node: SkillNode = o["node"]
	var finder := EuclideanRangeFinder.new()
	finder.max_distance = 250.0

	assert_almost_eq(finder.effective_distance(o["entity"], node), 250.0, 0.001,
			"no modifiers: the authored reach comes back untouched")

	node.add_local_modifier(_static_mod(&"cast_range_distance", StatModifier.Operation.ADD_BASE, 50.0))
	assert_almost_eq(finder.effective_distance(o["entity"], node), 300.0, 0.001,
			"+50 base-add on top of the authored 250")

	node.add_local_modifier(_static_mod(&"cast_range_distance", StatModifier.Operation.MULTIPLY, 1.5))
	assert_almost_eq(finder.effective_distance(o["entity"], node), 450.0, 0.001,
			"(250 + 50) × 1.5")


func test_entity_board_modifier_reaches_an_owned_node() -> void:
	var board := _bare_board()
	board.add_modifier(_static_mod(&"cast_range_hops", StatModifier.Operation.ADD_BASE, 2.0))
	var o := _owned_node(board)

	assert_eq(SpellRangeRules.reach(&"cast_range_hops", 3.0, o["entity"], o["node"]), 5.0,
			"the node tier folds the owner's board bins under the overlay")


# ── tier 2: the caster's board alone (tooltip preview) ───────────────────────


func test_board_set_replaces_the_authored_reach_outright() -> void:
	var board := _bare_board()
	board.add_modifier(_static_mod(&"cast_range_hops", StatModifier.Operation.SET, 5.0))
	var short_finder := HopRangeFinder.new()
	short_finder.max_hops = 3
	var long_finder := HopRangeFinder.new()
	long_finder.max_hops = 10

	assert_eq(short_finder.effective_max_hops(null, null, board), 5)
	assert_eq(long_finder.effective_max_hops(null, null, board), 5,
			"a SET on the stat is the reach, whatever the spell authored")


func test_board_without_the_stat_falls_back_to_the_authored_reach() -> void:
	var board := EntityStatBoard.new()
	assert_eq(SpellRangeRules.reach(&"cast_range_distance", 250.0, null, null, board), 250.0)


# ── tier 3: the aura clause ──────────────────────────────────────────────────


func test_null_attacker_gets_the_raw_authored_reach_even_with_a_local_bonus() -> void:
	var node := _node()
	node.add_local_modifier(_static_mod(&"cast_range_hops", StatModifier.Operation.ADD_BASE, 5.0))

	assert_eq(SpellRangeRules.reach(&"cast_range_hops", 3.0, null, node), 3.0,
			"a null attacker never inherits a source node's local cast range — auras don't scale")
	assert_eq(SpellRangeRules.reach(&"cast_range_hops", 3.0, null, null, null), 3.0)


# ── the INT pool's distance entry moves euclid reach ─────────────────────────


func test_int_pool_distance_entry_rolled_onto_a_node_scales_euclid_reach() -> void:
	var pack := load(_INT_PACK)
	var entry: StatPool = null
	for pool in pack.pools:
		if pool.stat_id == &"cast_range_distance":
			entry = pool
	assert_not_null(entry, "the INT pack carries a cast_range_distance entry")
	if entry == null:
		return
	assert_eq(entry.operation, StatModifier.Operation.INCREASE,
			"the entry is a % increase — it must move euclid reach, not add pixels")

	var o := _owned_node(_bare_board())
	var node: SkillNode = o["node"]
	var finder := EuclideanRangeFinder.new()
	finder.max_distance = 250.0
	assert_almost_eq(finder.effective_distance(o["entity"], node), 250.0, 0.001)

	node.add_local_modifier(_static_mod(entry.stat_id, entry.operation, entry.unit_value))
	assert_almost_eq(finder.effective_distance(o["entity"], node),
			250.0 * (1.0 + entry.unit_value / 100.0), 0.001,
			"reach scales by the entry's own unit_value, read off the entry")


# ── structural guards on the shipped boards (no goldens) ─────────────────────


func test_shipped_spells_hops_are_unchanged_by_the_default_board_at_baseline() -> void:
	# The INT ladder's first breakpoint sits above the baseline INT, so the
	# shipped board contributes nothing to a hop-ranged spell's reach.
	var board: EntityStatBoard = _DEFAULT_BOARD.duplicate(true)
	var checked := 0
	for file in DirAccess.get_files_at(_SPELL_DEFS_DIR):
		if not file.ends_with(".tres"):
			continue
		var spell := load(_SPELL_DEFS_DIR + file) as SpellDef
		if spell == null or spell.targeting == null:
			continue
		var rf := spell.targeting.get_range_finder() as HopRangeFinder
		if rf == null:
			continue
		checked += 1
		assert_eq(rf.effective_max_hops(null, null, board), rf.max_hops,
				"%s: hops at baseline INT must be the authored number" % file)
	assert_gt(checked, 0, "fixture: at least one shipped spell is hop-ranged")


func test_both_cast_range_scalars_have_base_zero_on_every_shipped_board() -> void:
	var boards: Dictionary = {"default_entity_board": _DEFAULT_BOARD}
	for path in _BLOCKER_BOARDS:
		boards[path.get_file()] = load(path)
	for name in boards:
		var board: EntityStatBoard = boards[name]
		for id in [&"cast_range_hops", &"cast_range_distance"]:
			var s := board.get_stat(id)
			assert_not_null(s, "%s: holds a %s stat" % [name, id])
			if s != null:
				assert_eq(s.base_value, 0.0,
						"%s: %s base must be 0 — the spell contributes the base as an overlay" % [name, id])

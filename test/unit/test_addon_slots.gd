extends GutTest

## #375 — addon_slots = base(0) + allocation_level as a node-local Stat.
##
## `addon_slots` is a Stat on the node board, minted (with its formula
## modifier) only when the node carries addons: `addon_slots = base(0) +
## allocation_level`, plain 1:1, the formula reading the stake pool through
## the `stake_level__current` accessor so fill changes recompute reactively.
## No enforcement yet (nothing caps addon attach) — the cap just exists.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _BUNKER_SCENE := preload("res://skill_node/addons/bunker_addon.tscn")
const _ADDON_SLOTS_DEF := preload("res://stats_system/defs/addon_slots.tres")

var _node: SkillNode


func before_each() -> void:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = _BOARD.duplicate(true) as StatBoard
	graph.add_child(entity)
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_node.stake_level = 3
	_node.owned_by = entity
	add_child(_node)
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(_node):
		_node.free()


func _attach_bunker() -> void:
	_node.add_child(_BUNKER_SCENE.instantiate())
	await get_tree().process_frame


func _slots() -> int:
	return int(_node.get_local_value(&"addon_slots"))


# --- 1/2. reads ---------------------------------------------------------------

func test_fill_3_reads_three_slots() -> void:
	await _attach_bunker()
	_node.allocation_level = 3
	assert_eq(_slots(), 3, "addon_slots == allocation_level at 3/3")


func test_fill_zero_reads_zero() -> void:
	await _attach_bunker()
	assert_eq(_slots(), 0, "freshly generated node (al 0) reads 0 slots")


# --- 3. reactivity ------------------------------------------------------------

func test_fill_ramp_recomputes_reactively() -> void:
	await _attach_bunker()
	assert_eq(_slots(), 0)
	_node.allocation_level = 2
	assert_eq(_slots(), 2, "0 -> 2 recomputes through the bound formula")


# --- 4. authored base ---------------------------------------------------------

func test_authored_base_adds_on_top_of_fill() -> void:
	await _attach_bunker()
	_node.node_board.get_stat(&"addon_slots").base_value = 1.0
	_node.allocation_level = 2
	assert_eq(_slots(), 3, "base(1) + allocation_level(2)")


# --- 5. sparseness ------------------------------------------------------------

func test_addonless_node_does_not_mint_addon_slots() -> void:
	assert_null(_node.node_board.get_stat(&"addon_slots"),
			"no addons, no authored base -> no addon_slots stat (stays sparse)")
	assert_null(_node.node_board.get_stat(&"addon_slots"))


# --- 6. guard: the formula reads the pool, not the accessor token -------------

func test_formula_input_ids_strip_to_the_base_id() -> void:
	# Same construction the mint uses; get_input_ids() must report the BASE id
	# (&"stake_level"), never the decorated accessor token — that's what keeps
	# the cycle graph seeing the pool (#333 acceptance 3).
	var f := ExpressionFormula.new()
	f.formula = "stake_level__current"
	f.inputs = [&"stake_level__current"]
	assert_eq(f.get_input_ids(), [&"stake_level"] as Array[StringName])

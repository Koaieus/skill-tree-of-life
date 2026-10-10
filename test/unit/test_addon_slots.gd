extends GutTest

## addon_slots = base(0) + stake_level as a node-local Stat.
##
## `addon_slots` is a node-OWNED Stat, baked as a typed NodeStatBoard field on
## `default_node_board.tres`: the cap reads the node's STAKE LEVEL (the
## stake pool's cap N, the bare `stake_level` token), never its fill M. A plain
## unallocated node has stake 1, so it reads 1 slot; fill never moves slots.
## The formula is authored as a board intrinsic bound to the file-backed
## `stake_scaling.tres`, so a stake change recomputes reactively.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _BUNKER_SCENE := preload("res://skill_node/addons/defs/bunker_addon.tscn")
const _ADDON_SLOTS_DEF := preload("res://stats_system/defs/addon_slots.tres")

var _node: SkillNode


func before_each() -> void:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
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

func test_fresh_node_reads_one_slot() -> void:
	# A plain node: default stake 1, fill 0 -> the cap is the stake level, 1.
	# Its board is lazy (never wired: stake 1 is the default, so no write path
	# ran), so this read is StatDef.default_value, not the formula.
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(n)
	await get_tree().process_frame
	assert_eq(n.allocation_level, 0, "fresh node is unallocated")
	assert_eq(int(n.get_local_value(&"addon_slots")), 1,
			"stake 1, fill 0 -> 1 slot")
	n.allocation_level = 1
	n.allocation_level = 0
	assert_eq(int(n.get_local_value(&"addon_slots")), 1,
			"wired at stake 1 -> base(0) + stake 1, the default never stacks on top")


func test_stake_3_reads_three_slots_at_every_fill() -> void:
	await _attach_bunker()
	assert_eq(_slots(), 3, "stake 3, fill 0 -> 3")
	_node.allocation_level = 1
	assert_eq(_slots(), 3, "stake 3, fill 1 -> 3")
	_node.allocation_level = 3
	assert_eq(_slots(), 3, "stake 3, fill 3 -> 3")


# --- 3. reactivity ------------------------------------------------------------

func test_stake_raise_recomputes_reactively() -> void:
	await _attach_bunker()
	_node.stake_level = 1
	assert_eq(_slots(), 1)
	_node.stake_level = 4
	assert_eq(_slots(), 4, "1 -> 4 recomputes through the bound formula")


# --- 4. authored base ---------------------------------------------------------

func test_authored_base_adds_on_top_of_stake() -> void:
	await _attach_bunker()
	_node.node_board.get_stat(&"addon_slots").base_value = 1.0
	_node.allocation_level = 2
	assert_eq(_slots(), 4, "base(1) + stake_level(3), fill irrelevant")


# --- 5. baked, not minted -----------------------------------------------------

func test_addonless_node_still_carries_addon_slots_baked() -> void:
	# `addon_slots` is a node-OWNED stat, so it is baked on default_node_board.tres
	# rather than minted when the first addon lands (it used to be the latter, and
	# an addonless node had no such stat at all). Baking is what makes the stat
	# authorable and its formula a one-file edit; the sparse promise now covers
	# only BORROWED stats. See NodeStatBoard.
	assert_not_null(_node.node_board.get_stat(&"addon_slots"),
			"addon_slots is baked on every node board, addons or not")
	assert_eq(_slots(), 3, "addonless, stake 3, al 0 -> base(0) + stake_level(3)")
	# Baked, NOT minted: the node-owned stats are typed fields, so they never
	# appear in _extra_stats. (`node_health` does — it is BORROWED from the
	# owner's board, and allocation mints the node's combat pool for it.)
	var dynamic := _node.node_board.get_dynamic_stat_ids()
	assert_false(dynamic.has(&"addon_slots"), "addon_slots is a field, not a mint")
	assert_false(dynamic.has(&"stake_level"), "stake_level is a field, not a mint")


# --- 6. guard: the formula reads the pool, not the accessor token -------------

func test_formula_input_ids_strip_to_the_base_id() -> void:
	# Same construction the mint uses; get_input_ids() must report the BASE id
	# (&"stake_level"), never the decorated accessor token — that's what keeps
	# the cycle graph seeing the pool (#333 acceptance 3).
	var f := ExpressionFormula.new()
	f.formula = "stake_level__current"
	f.inputs = [&"stake_level__current"]
	assert_eq(f.get_input_ids(), [&"stake_level"] as Array[StringName])


# --- 7. the scaling formula must stay file-backed, never inlined -------------

func test_stake_scaling_formula_is_shared_across_every_node_board() -> void:
	# `duplicate(true)` PRESERVES the identity of a file-backed sub-resource and
	# COPIES an inline one. Inlining `stake_scaling.tres` into
	# default_node_board.tres would therefore fork the curve into one private
	# ExpressionFormula per node — 2500 of them in a level — with no error, and
	# retuning the file would silently stop reaching anything. Same contract as
	# level_scaling.tres for core classes (stats-system.md).
	const _TEMPLATE := preload("res://skill_node/default_node_board.tres")
	const _SHARED := preload("res://stats_system/formulas/stake_scaling.tres")
	var a: NodeStatBoard = _TEMPLATE.duplicate(true)
	var b: NodeStatBoard = _TEMPLATE.duplicate(true)
	assert_eq(a.intrinsic_modifiers[0].formula, _SHARED,
			"the addon_slots formula must remain the file-backed shared instance")
	assert_eq(a.intrinsic_modifiers[0].formula, b.intrinsic_modifiers[0].formula,
			"two cloned boards must share one formula instance, not fork it")
	# The MODIFIER, by contrast, is deliberately inline/per-board: it is the
	# reactive subscriber, and one shared instance would make a single node's
	# stake change recompute addon_slots on every node in the level.
	assert_ne(a.intrinsic_modifiers[0], b.intrinsic_modifiers[0],
			"each board owns its own modifier instance")


# --- 8. an AUTHORED board is initialized just like a cloned template ---------

func test_scene_authored_board_still_gets_its_intrinsics_applied() -> void:
	# `node_board` is exported and scene-composable (a level, cluster or single
	# node may author its own), so "already non-null" must NOT be read as
	# "already initialized". If it were, an authored board would skip
	# apply_intrinsics() forever and addon_slots would silently stop tracking
	# stake level — no error, correct-looking board, dead formula.
	var authored: NodeStatBoard = preload("res://skill_node/default_node_board.tres").duplicate(true)
	authored.addon_slots.base_value = 2.0
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	n.node_board = authored
	add_child(n)
	await get_tree().process_frame
	n.stake_level = 3

	assert_eq(int(n.get_local_value(&"addon_slots")), 5,
			"authored base(2) + stake_level(3) — intrinsics ran on the authored board")
	assert_ne(n.node_board, authored,
			"the authored resource is a template: the node runs on a deep clone of it")
	assert_eq(authored.addon_slots.base_value, 2.0,
			"and the authored resource is never mutated by the node using it")
	n.free()

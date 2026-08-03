extends GutTest

## #340 — SkillNode.add_local_modifier now binds a formula-driven leaf to
## node_board (mirroring StatBoard.add_modifier's cycle-check -> bind ->
## resolve-target sequence, WITHOUT routing through StatBoard.add_modifier —
## see the issue body / the cross-reference comment on both sites for why).
##
## Acceptance criteria 1-6 from the issue, one test group each.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func _node() -> SkillNode:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	return node


func _static_mod(id: StringName, op: int, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = op
	m.value = value
	return m


## A formula-driven modifier targeting `target_id`, reading `source_id`
## (another node-board stat) through a LinearFormula, scaled by `coefficient`.
func _formula_mod(target_id: StringName, source_id: StringName, coefficient: float) -> StatModifier:
	var lin := LinearFormula.new()
	lin.source_stat_id = source_id
	var m := StatModifier.new()
	m.stat_id = target_id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = coefficient
	m.formula = lin
	return m


# --- 1. Formula-driven local modifier computes through get_local_value -----

func test_formula_driven_local_modifier_computes_through_get_local_value() -> void:
	var node := _node()
	# Zero both bases so the expected value is just the formula contribution.
	node._ensure_local_stat(&"strength").base_value = 0.0
	node._ensure_local_stat(&"dexterity").base_value = 0.0

	node.add_local_modifier(_static_mod(&"strength", StatModifier.Operation.ADD_BASE, 10.0))
	node.add_local_modifier(_formula_mod(&"dexterity", &"strength", 2.0))

	# Fails on master: add_local_modifier never binds, so the formula leaf's
	# _board stays null and get_effective_value() falls back to the raw
	# coefficient (2.0) instead of 2.0 * strength(10.0).
	assert_almost_eq(float(node.get_local_value(&"dexterity")), 20.0, 0.001,
			"formula-driven dexterity should read 2x the node-local strength")


# --- 2. Reactivity: changing the source recomputes the dependent modifier --

func test_source_change_recomputes_dependent_local_modifier() -> void:
	var node := _node()
	node._ensure_local_stat(&"strength").base_value = 0.0
	node._ensure_local_stat(&"dexterity").base_value = 0.0
	node.add_local_modifier(_static_mod(&"strength", StatModifier.Operation.ADD_BASE, 10.0))
	node.add_local_modifier(_formula_mod(&"dexterity", &"strength", 2.0))
	assert_almost_eq(float(node.get_local_value(&"dexterity")), 20.0, 0.001)

	node.add_local_modifier(_static_mod(&"strength", StatModifier.Operation.ADD_BASE, 5.0))

	assert_almost_eq(float(node.get_local_value(&"dexterity")), 30.0, 0.001,
			"the bind subscribes to strength, so dexterity must recompute reactively")


# --- 3. Cycle rejection, atomic, board left untouched -----------------------

func test_cycle_closing_local_modifier_is_rejected_and_board_untouched() -> void:
	var node := _node()
	# strength -> depends on dexterity
	node.add_local_modifier(_formula_mod(&"strength", &"dexterity", 1.0))
	var strength_before: float = float(node.get_local_value(&"strength"))
	var dexterity_before: float = float(node.get_local_value(&"dexterity"))

	# dexterity -> depends on strength closes strength -> dexterity -> strength.
	var closing := _formula_mod(&"dexterity", &"strength", 1.0)
	node.add_local_modifier(closing)

	assert_almost_eq(float(node.get_local_value(&"strength")), strength_before, 0.001,
			"rejected candidate must not perturb strength")
	assert_almost_eq(float(node.get_local_value(&"dexterity")), dexterity_before, 0.001,
			"rejected candidate must not perturb dexterity")
	var dex_stat := node.node_board.get_stat(&"dexterity")
	assert_false(dex_stat.has_modifier(closing),
			"rejected modifier must never be attached to its target stat")


# --- 4. remove_local_modifier unbinds ---------------------------------------

func test_remove_local_modifier_unbinds() -> void:
	var node := _node()
	node._ensure_local_stat(&"strength").base_value = 0.0
	node._ensure_local_stat(&"dexterity").base_value = 0.0
	node.add_local_modifier(_static_mod(&"strength", StatModifier.Operation.ADD_BASE, 10.0))
	var dex_mod := _formula_mod(&"dexterity", &"strength", 2.0)
	node.add_local_modifier(dex_mod)
	assert_almost_eq(float(node.get_local_value(&"dexterity")), 20.0, 0.001)

	node.remove_local_modifier(dex_mod)
	node.add_local_modifier(_static_mod(&"strength", StatModifier.Operation.ADD_BASE, 100.0))

	assert_almost_eq(float(node.get_local_value(&"dexterity")), 0.0, 0.001,
			"removed modifier must no longer contribute, and must not recompute off strength")


# --- 5. Sparseness ------------------------------------------------------------

func test_no_local_modifiers_leaves_extra_stats_empty() -> void:
	var node := _node()
	assert_null(node.node_board, "no local modifier ever added -> node_board itself stays unallocated")


func test_entity_only_value_passes_through_without_allocating_node_board() -> void:
	var graph := preload("res://graph/graph.tscn").instantiate()
	add_child_autofree(graph)
	var board: StatBoard = preload("res://entity/default_entity_board.tres").duplicate(true)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	graph.add_child(entity)

	var node := _node()
	graph.skill_nodes_container.add_child(node)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(entity, node)

	# node_board now exists (combat health pool from allocation), but no local
	# modifier has targeted `strength` — reading it must pass through to the
	# entity board without minting a node-board stat for it.
	assert_not_null(node.node_board, "allocation creates node_board for combat health")
	assert_eq(node.node_board._extra_stats.has(&"strength"), false,
			"reading an entity-only stat must not allocate it on node_board")
	assert_eq(node.get_local_value(&"strength"), entity.stat_board.get_stat(&"strength").get_value(),
			"should pass through to the entity value")


# --- 6. Entity board never gains a node-only stat (regression guard) --------

func test_entity_board_add_modifier_still_noops_for_unknown_id() -> void:
	var board: StatBoard = preload("res://entity/default_entity_board.tres").duplicate(true)
	var m := _static_mod(&"stake_level", StatModifier.Operation.ADD_BASE, 1.0)
	board.add_modifier(m)
	assert_false(board._extra_stats.has(&"stake_level"),
			"StatBoard.add_modifier must still no-op (get_stat, not ensuring) for a node-only id")

extends GutTest

## NodeCombat.get_local_value_with(stat_id, overlays) — the node-local merged
## read with caller overlays folded AFTER the node bins, through
## Stat.get_value_with (one fold, one floor). get_local_value(id) is the
## empty-overlay delegate; the only behavioural difference is tier 4 (no stat
## on either board): the wrapper falls to the def default, the door to null.
##
## Every Stat/StatDef here is hand-built under an unregistered id — the file
## names no shipped stat, so a rename elsewhere cannot break it. Stats are
## seeded via StatBoard._register_minted, the documented mint choke point:
## EntityStatBoard refuses to mint and the id has no registry def.

const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _ID := &"overlay_test_stat"


func _stat(value_type: int, base: float) -> ScalarStat:
	var d := StatDef.new()
	d.id = _ID
	d.value_type = value_type as StatDef.ValueType
	var s := ScalarStat.new()
	s.definition = d
	s.base_value = base
	return s


func _mod(op: int, value: float, priority: int = 0) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = _ID
	m.operation = op as StatModifier.Operation
	m.value = value
	m.priority = priority
	return m


func _overlay(base_add: float) -> ModifierBins:
	var b := ModifierBins.new()
	b.base_add = base_add
	return b


## An owned node whose owner's board carries [param es] under _ID, and whose
## own board carries [param ns] (skipped when null). Built like
## test_spell_range_rules.gd's owned-node fixture so the SkillNode passthrough
## is the path under test.
func _owned_node(es: ScalarStat, ns: ScalarStat) -> SkillNode:
	var graph := preload("res://graph/graph.tscn").instantiate()
	add_child_autofree(graph)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = preload("res://entity/default_entity_board.tres").duplicate(true)
	graph.add_child(entity)
	# After _ready: Entity duplicates its board there, and a minted stat is
	# not a stored property, so seeding before would be lost to the copy.
	entity.stat_board._register_minted(_ID, es)

	var node := _NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(node)
	autofree(node)
	if ns != null:
		node._init_node_board()
		node.node_board._register_minted(_ID, ns)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(entity, node)
	return node


func _orphan_node() -> SkillNode:
	var node := _NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	return node


# --- 1: overlay folds after entity + node bins ------------------------------

func test_overlay_base_add_folds_with_entity_and_node_bins() -> void:
	var node := _owned_node(_stat(StatDef.ValueType.FLOAT, 1.0), _stat(StatDef.ValueType.FLOAT, 0.0))
	node.add_local_modifier(_mod(StatModifier.Operation.ADD_BASE, 2.0))

	assert_eq(node.get_local_value_with(_ID, [_overlay(10.0)]), 13.0,
			"(1 + 2 + 10) — overlay base_add sums with the node-local ADD_BASE over the entity base")
	assert_eq(node.get_local_value(_ID), 3.0, "the bare read is unchanged")


# --- 2: the INT floor sits after the merged fold ----------------------------

func test_int_floor_applies_once_after_the_overlay_is_folded() -> void:
	var es := _stat(StatDef.ValueType.INT, 0.0)
	es.add_modifier(_mod(StatModifier.Operation.INCREASE, 50.0))
	var node := _owned_node(es, null)

	assert_eq(node.get_local_value_with(_ID, [_overlay(3.0)]), 4,
			"(0 + 3) × 1.5 = 4.5 floors once to 4 — never 3 × 1 + floor separately")


# --- 3: no stat on either board → null, while the wrapper keeps its default --

func test_orphan_without_local_stat_reads_null_with_overlays() -> void:
	var node := _orphan_node()

	assert_null(node.get_local_value_with(_ID, [_overlay(10.0)]),
			"no Stat to coerce through: the door answers null, never a def default or 0")
	# The id has no registry def, so the wrapper's def-default tail is its
	# 0.0 fallback — the point is that it is a number, not null.
	assert_eq(node.get_local_value(_ID), 0.0, "the bare read keeps its def-default fallback")


# --- 4: empty overlays equal today's read ------------------------------------

func test_empty_overlays_equal_the_bare_read_on_an_owned_node_with_a_local_stat() -> void:
	var node := _owned_node(_stat(StatDef.ValueType.FLOAT, 1.0), _stat(StatDef.ValueType.FLOAT, 0.0))
	node.add_local_modifier(_mod(StatModifier.Operation.ADD_BASE, 2.0))
	var empty: Array[ModifierBins] = []

	assert_eq(node.get_local_value_with(_ID, empty), node.get_local_value(_ID))
	assert_eq(node.get_local_value_with(_ID, empty), 3.0)


func test_empty_overlays_equal_the_bare_read_with_entity_stat_only() -> void:
	var node := _owned_node(_stat(StatDef.ValueType.FLOAT, 5.0), null)
	var empty: Array[ModifierBins] = []

	assert_eq(node.get_local_value_with(_ID, empty), node.get_local_value(_ID))
	assert_eq(node.get_local_value_with(_ID, empty), 5.0)


# --- 5: a SET on the entity stat beats the overlay's base --------------------

func test_entity_set_wins_over_overlay_base_add() -> void:
	var es := _stat(StatDef.ValueType.FLOAT, 1.0)
	es.add_modifier(_mod(StatModifier.Operation.SET, 7.0))
	var node := _owned_node(es, null)

	assert_eq(node.get_local_value_with(_ID, [_overlay(3.0)]), 7.0,
			"SET short-circuits the fold; the overlay's base_add is not added on top")


# --- 6: SET tie-break by locality, then by priority --------------------------

func test_node_local_set_wins_an_equal_priority_tie_against_the_entity_set() -> void:
	var es := _stat(StatDef.ValueType.FLOAT, 1.0)
	es.add_modifier(_mod(StatModifier.Operation.SET, 7.0))
	var node := _owned_node(es, _stat(StatDef.ValueType.FLOAT, 0.0))
	node.add_local_modifier(_mod(StatModifier.Operation.SET, 9.0))

	assert_eq(node.get_local_value_with(_ID, [_overlay(3.0)]), 9.0,
			"equal priority: the later (more local) source wins")


func test_higher_priority_entity_set_wins_over_the_node_local_set() -> void:
	var es := _stat(StatDef.ValueType.FLOAT, 1.0)
	es.add_modifier(_mod(StatModifier.Operation.SET, 7.0, 1))
	var node := _owned_node(es, _stat(StatDef.ValueType.FLOAT, 0.0))
	node.add_local_modifier(_mod(StatModifier.Operation.SET, 9.0))

	assert_eq(node.get_local_value_with(_ID, [_overlay(3.0)]), 7.0,
			"priority beats locality")

extends GutTest
## SpendRingCellCommand through its handler: validates against the RingTable,
## then grants through the core register. A refusal has no side effect.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _RING_PATH := "res://entity/ring/aspect_ring.tscn"

var _ent: Entity
var _ctx: CommandContext
var _handler := SpendRingCellCommandHandler.new()


func before_each() -> void:
	var graph: Graph = (load("res://graph/graph.tscn") as PackedScene).instantiate()
	add_child_autofree(graph)
	_ent = Entity.new()
	_ent.display_name = "T"
	_ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.get_node("Entities").add_child(_ent)
	var sys := RingSystem.new()
	sys.ring_scene = load(_RING_PATH)
	add_child_autofree(sys)
	_ctx = CommandContext.new()
	_ctx.graph = graph
	_ctx.ring_system = sys
	await get_tree().process_frame


## Earn `k` ring points the way play does: by reaching milestone levels.
func _earn(k: int) -> void:
	var target := int(_ent.level) + k * _ent.milestone_level_interval
	target -= target % _ent.milestone_level_interval
	while int(_ent.level) < target:
		_ent._on_xp_replenished()


func _try(cell: StringName) -> bool:
	var cmd := SpendRingCellCommand.new(_ent.entity_id, cell)
	if not _handler.validate(cmd, _ctx):
		return false
	return _handler.apply(cmd, _ctx)


func _value(id: StringName) -> float:
	return float(_ent.stat_board.get_stat(id).get_value())


func test_buying_a_t1_grants_its_aspect_and_spends_a_point() -> void:
	_earn(1)
	var pool := _ent.stat_board.ring_points
	assert_not_null(pool)
	if pool == null:
		return
	var before := _value(&"bleeding_aspect")
	var reg := _ent.core_modifiers.size()
	assert_true(_try(&"BleedingT1"), "a funded, adjacent T1 is bought")
	assert_eq(_value(&"bleeding_aspect"), before + 1.0, "+1 bleeding_aspect on the board")
	assert_eq(_ent.core_modifiers.size(), reg + 1, "the grant enters the core register")
	assert_true(_ent.ring_spent.has(&"BleedingT1"), "recorded as spent")
	assert_eq(pool.available(), 0, "one point spent")


func test_refusals_have_no_side_effect() -> void:
	_earn(2)
	var pool := _ent.stat_board.ring_points
	if pool == null:
		fail_test("no ring_points pool")
		return
	var reg := _ent.core_modifiers.size()
	assert_false(_try(&"PoisonT2"), "a cell with no edge to Core or a bought cell is refused")
	assert_eq(pool.available(), 2)
	assert_eq(_ent.core_modifiers.size(), reg)
	assert_true(_try(&"BleedingT1"))
	reg = _ent.core_modifiers.size()
	assert_false(_try(&"BleedingT1"), "a spent cell is refused")
	assert_eq(pool.available(), 1)
	assert_eq(_ent.core_modifiers.size(), reg)
	assert_eq(_ent.ring_spent.size(), 1)
	assert_true(_try(&"WeaknessT1"))
	assert_eq(pool.available(), 0)
	reg = _ent.core_modifiers.size()
	assert_false(_try(&"BleedingT2"), "zero points is refused")
	assert_eq(_ent.core_modifiers.size(), reg)
	assert_false(_ent.ring_spent.has(&"BleedingT2"))


func test_a_keystone_cell_grants_its_scenes_modifiers() -> void:
	_earn(2)
	assert_true(_try(&"BleedingT1"))
	var reg := _ent.core_modifiers.size()
	assert_true(_try(&"StrengthKeystone"), "a keystone touching a bought T1 is buyable")
	var granted := _ent.core_modifiers.slice(reg)
	var ids := granted.map(func(m: StatModifier) -> StringName: return m.stat_id)
	assert_true(ids.has(&"xp_per_turn"), "the natural-xp keystone's +xp_per_turn lands")
	assert_true(ids.has(&"wisdom"), "and its +wisdom")

extends GutTest

## The world-turn decay seat (#1801 W): an owned node row whose def sets
## `decay_per_world_turn` skips its holder's turn-end tick and decays once per
## WORLD turn instead. Composition "Decay per world turn"; acceptance 4b's shape.

var _tw: TestWorld
var _tm: TurnManager
var _node: SkillNode
var _def: StatusDef


func _build(per_world_turn: bool) -> void:
	_tw = TestWorld.create(self)
	_tm = autofree(TurnManager.new())
	_tm.entity_root = _tw.graph
	add_child(_tm)
	var a := _tw.add_entity("A")
	_tw.add_entity("B")
	_node = _tw.add_node(&"N0")
	_node.owned_by = a
	a.navigator.mirror_add(_node)
	_def = StatusDef.new()
	_def.id = &"wt_decay_probe"
	_def.reapply = StatusDef.Reapply.ACCUMULATE
	_def.power_max = 10.0
	_def.decay = FlatDecay.new()
	_def.decay_per_world_turn = per_world_turn
	_node.get_combat().apply_status(_def, 5.0)
	_tm.start_turn(a)


func _power() -> float:
	return _node.get_combat().get_status_power(_def.id)


func test_row_decays_once_when_the_world_turn_closes_not_at_holder_turn_end() -> void:
	_build(true)
	assert_eq(TurnManager.world_turn_period(2, _tm.world_clock), 2, "two carriers: a world turn per 2 turn ends")
	_tm.end_turn()
	assert_eq(_power(), 5.0, "after the first turn end the row is unchanged")
	_tm.end_turn()
	assert_eq(_power(), 4.0, "after the second (world turn closes) it is down by one, once")


func test_default_def_still_decays_at_holder_turn_end() -> void:
	_build(false)
	_tm.end_turn()
	assert_eq(_power(), 4.0, "default false: the holder's own turn end ticks it")

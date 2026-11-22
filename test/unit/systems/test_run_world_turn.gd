extends GutTest

## [method TurnManager.run_world_turn] is the public seam for exactly one
## world turn: it ends it and announces it once.

var _w: TestWorld
var _tm: TurnManager
var _ended := [0]


func before_each() -> void:
	_w = TestWorld.create(self)
	_w.build([[0, 1]])
	_tm = TurnManager.new()
	_tm.entity_root = _w.graph
	add_child_autofree(_tm)
	await get_tree().process_frame
	_ended[0] = 0
	_tm.world_turn_ended.connect(func() -> void: _ended[0] += 1)


func after_each() -> void:
	CombatWorld.live().flush_removals()


func test_run_world_turn_emits_world_turn_ended_once() -> void:
	_tm.run_world_turn()
	assert_eq(_ended[0], 1, "one world turn, one world_turn_ended")

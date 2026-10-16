extends GutTest

## The late-spill net: live removals still pending when the actor hands its
## turn off were noted outside a beat that flushes them, so
## [method TurnManager.end_turn] reports them loudly ([method push_error]).

var _w: TestWorld
var _tm: TurnManager
var _red: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_w = TestWorld.create(self)
	_nodes = _w.build([[0, 1]])
	_red = _w.add_entity("Red")
	_w.allocate(_red, _nodes)
	_tm = TurnManager.new()
	_tm.entity_root = _w.graph
	add_child_autofree(_tm)
	await get_tree().process_frame


func after_each() -> void:
	CombatWorld.live().flush_removals()


func test_a_pending_removal_at_turn_handoff_is_a_push_error() -> void:
	_w.allocator().force_deallocate(_nodes[1])
	assert_true(CombatWorld.live().has_pending_removals(), "a bare force leaves its removal pending")
	_tm.start_turn(_red)
	_tm.end_turn()
	assert_push_error("pending removals")


func test_a_flushed_strip_hands_off_quietly() -> void:
	_w.allocator().force_deallocate(_nodes[1])
	CombatWorld.live().flush_removals()
	_tm.start_turn(_red)
	_tm.end_turn()
	assert_push_error_count(0)

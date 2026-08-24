extends GutTest

## #525 — every confirmed territory change frames itself, for a NON-LOCAL actor.
##
## The trigger is [signal CommandApplier.command_confirmed], not
## [AllocationSystem]'s signals, so the assertions here are all against the pure
## [method CameraDirector._build_command_request] — a [Command] in, a
## [FocusRequest] or null out — exactly as `test_camera_director_attack.gd`
## tests `_build_attack_request`. The director stays stateless (one focus per
## command, re-arming), which is what lets every case below be a pure call with
## no frames and no drain.
##
## The geometry policy (`decide`'s fit, lattice zoom-out, centre-of-mass and pan
## clamp) is `test_camera_director.gd`'s job and is not re-tested here.

const _SKILL_NODE := preload("res://skill_node/skill_node.tscn")

var _dir: CameraDirector
var _vision: _StubVision
var _graph: _StubGraph
var _holder: Node2D
var _next_id: int = 1


## Fog with its answers dictated rather than computed. Everything is SENSED, so
## a director that reached for `is_sensed` instead of `is_visible` would frame
## the whole board and the fog cases below would go red.
class _StubVision:
	extends VisionSystem
	var visible_nodes: Array = []
	func is_visible(node: SkillNode) -> bool:
		return visible_nodes.has(node)
	func is_sensed(_node: SkillNode) -> bool:
		return true


## The two resolvers the director actually calls, answered off a dictionary.
## Standing up the real `graph.tscn` to look up two ids would test [Graph].
## Never entered into the tree — nothing here needs `_ready`.
class _StubGraph:
	extends Graph
	var nodes_by_id: Dictionary[int, SkillNode] = {}
	var entities_by_id: Dictionary[int, Entity] = {}
	func get_by_stable_id(id: int) -> SkillNode:
		return nodes_by_id.get(id)
	func get_by_entity_id(id: int) -> Entity:
		return entities_by_id.get(id)


func before_each() -> void:
	_next_id = 1
	_holder = Node2D.new()
	add_child_autofree(_holder)
	_vision = _StubVision.new()
	_holder.add_child(_vision)
	_graph = autofree(_StubGraph.new())
	_dir = CameraDirector.new()
	_dir.vision_system = _vision
	_dir.graph = _graph
	_dir.seat_policy = SeatPolicy.couch()
	_holder.add_child(_dir)


## A node at [param pos], registered under a fresh stable id. Returns the id,
## since that is what a command carries.
func _node_at(pos: Vector2, seen: bool = true) -> int:
	var n: SkillNode = _SKILL_NODE.instantiate()
	_holder.add_child(n)
	n.global_position = pos
	var id := _next_id
	_next_id += 1
	_graph.nodes_by_id[id] = n
	if seen:
		_vision.visible_nodes.append(n)
	return id


func _actor(human: bool) -> int:
	var e := Entity.new()
	e.is_human_controlled = human
	e.entity_id = 900 + _graph.entities_by_id.size()
	_holder.add_child(e)
	_graph.entities_by_id[e.entity_id] = e
	return e.entity_id


## An `npc` id by default — on a couch `seats()` is true for every human, so a
## human actor is the LOCAL player as far as this gate is concerned.
func _npc() -> int:
	return _actor(false)


func _node_command(type: GDScript, actor_id: int, node_id: int) -> NodeCommand:
	var c: NodeCommand = type.new(actor_id)
	c.node_id = node_id
	return c


# --- the seat gate ----------------------------------------------------------

func test_a_seated_actors_allocation_is_never_framed() -> void:
	# The player who clicked the node is already looking at it; focusing it is
	# the yank the feature exists to avoid. Owner: "in your own turn we don't
	# need a director."
	var hero := _actor(true)
	assert_null(_dir._build_command_request(
			_node_command(AllocateCommand, hero, _node_at(Vector2.ZERO))))


func test_an_unresolvable_actor_frames_nothing() -> void:
	# `seats(null)` is false, so an actor that fails to resolve would otherwise
	# fall THROUGH the gate and frame every such command.
	assert_null(_dir._build_command_request(
			_node_command(AllocateCommand, 4242, _node_at(Vector2.ZERO))))


# --- the single-node verbs --------------------------------------------------

func test_an_ai_allocation_builds_a_point_focus() -> void:
	var req := _dir._build_command_request(
			_node_command(AllocateCommand, _npc(), _node_at(Vector2(300, 120))))
	assert_not_null(req)
	assert_eq(req.points, PackedVector2Array([Vector2(300, 120)]))
	assert_false(req.allow_zoom_out, "a single node can never yank the zoom")
	assert_eq(req.hold, _dir.command_hold_seconds)


func test_deallocate_stake_and_extract_all_frame_their_node() -> void:
	for type: GDScript in [DeallocateCommand, StakeCommand, ExtractCommand]:
		var req := _dir._build_command_request(
				_node_command(type, _npc(), _node_at(Vector2(50, 50))))
		assert_not_null(req, "%s builds a request" % type)
		assert_eq(req.points, PackedVector2Array([Vector2(50, 50)]))
		assert_false(req.allow_zoom_out)


# --- the fog gate -----------------------------------------------------------

func test_a_fogged_node_builds_an_empty_request_not_a_missing_one() -> void:
	# An all-fogged command is a distinct outcome from a malformed one, and
	# `decide` has to be able to say which.
	var req := _dir._build_command_request(
			_node_command(AllocateCommand, _npc(), _node_at(Vector2.ZERO, false)))
	assert_not_null(req, "the request exists")
	assert_true(req.points.is_empty())
	assert_eq(req.empty_reason, &"fogged")
	var decision := _dir.decide(req, _ctx())
	assert_false(decision.act)
	assert_eq(decision.reason, &"fogged")


func test_a_sensed_but_not_visible_node_does_not_count() -> void:
	# The stub reports EVERYTHING sensed. `is_sensed` does not count (#515
	# decision 4) — only `is_visible` does.
	var id := _node_at(Vector2.ZERO, false)
	assert_true(_vision.is_sensed(_graph.nodes_by_id[id]), "the stub does sense it")
	var req := _dir._build_command_request(_node_command(AllocateCommand, _npc(), id))
	assert_true(req.points.is_empty())


# --- the multi-node verbs ---------------------------------------------------

func test_a_deallocate_set_spans_exactly_its_nodes() -> void:
	var c := DeallocateSetCommand.new(_npc())
	c.node_ids = [_node_at(Vector2(0, 0)), _node_at(Vector2(400, 100)),
			_node_at(Vector2(100, -200))]
	var req := _dir._build_command_request(c)
	assert_not_null(req)
	assert_eq(req.bounds(), Rect2(Vector2(0, -200), Vector2(400, 300)))


func test_a_mass_allocate_spans_its_whole_requested_path() -> void:
	# It over-frames by design: the affordable count is re-computed at apply
	# time (#458), so the path framed at confirm may be longer than what lands.
	# The requested path is the intent.
	var c := MassAllocateCommand.new(_npc())
	c.path_ids = [_node_at(Vector2(0, 0)), _node_at(Vector2(100, 0)),
			_node_at(Vector2(200, 0)), _node_at(Vector2(300, 0))]
	var req := _dir._build_command_request(c)
	assert_eq(req.points.size(), 4)
	assert_eq(req.bounds(), Rect2(Vector2.ZERO, Vector2(300, 0)))


func test_a_core_move_spans_the_whole_walk_and_holds_for_its_duration() -> void:
	var c := MoveCoreCommand.new(_npc())
	c.path_ids = [_node_at(Vector2(0, 0)), _node_at(Vector2(100, 0)),
			_node_at(Vector2(200, 0)), _node_at(Vector2(200, 300))]
	var req := _dir._build_command_request(c)
	assert_eq(req.points.size(), 4, "every hop is framed, not just the destination")
	# The applier's own beat: three gaps at CORE_HOP_SLIDE_DELAY plus the last
	# hop's glide. The two constants are deliberately unequal — the hops
	# overlap so the walk reads as a cascade.
	assert_almost_eq(req.hold,
			3.0 * CommandApplier.CORE_HOP_SLIDE_DELAY + SkillNode.CORE_SLIDE_DURATION,
			0.0001)
	assert_almost_eq(req.hold, 0.79, 0.0001)


func test_a_single_hop_core_move_holds_for_exactly_one_glide() -> void:
	# Guards the hop count against going negative on a degenerate path.
	var c := MoveCoreCommand.new(_npc())
	c.path_ids = [_node_at(Vector2.ZERO)]
	assert_almost_eq(_dir._build_command_request(c).hold,
			SkillNode.CORE_SLIDE_DURATION, 0.0001)


# --- the exclusions ---------------------------------------------------------

func test_an_attack_is_never_framed_from_this_path() -> void:
	# It is already framed by `BattleSystem.attack_committed` (#524). Wiring it
	# here too would raise TWO focus requests per attack.
	assert_null(_dir._build_command_request(LaunchAttackCommand.new(_npc())))


func test_the_geometryless_and_non_territorial_verbs_frame_nothing() -> void:
	var npc := _npc()
	assert_null(_dir._build_command_request(EndTurnCommand.new(npc)), "end_turn")
	assert_null(_dir._build_command_request(LootRoundCommand.new(npc)), "loot_round")
	# A NodeCommand WITH geometry, excluded on purpose: it is not a territory
	# change. This is what a subtype test instead of an allow-list would break.
	var toggle := ToggleTempUpgradeCommand.new(npc)
	toggle.node_id = _node_at(Vector2.ZERO)
	assert_null(_dir._build_command_request(toggle), "toggle_temp_upgrade")


# --- the non-negotiable -----------------------------------------------------

func test_nothing_built_here_is_ever_mandatory() -> void:
	# #515's non-negotiable: `mandatory` would switch off the grace window and
	# the skip-if-on-screen check, which is exactly the yank the feature avoids.
	# #459's handover stays the only mandatory focus.
	var npc := _npc()
	var set_cmd := DeallocateSetCommand.new(npc)
	set_cmd.node_ids = [_node_at(Vector2.ZERO), _node_at(Vector2(10, 10))]
	var move := MoveCoreCommand.new(npc)
	move.path_ids = [_node_at(Vector2.ZERO), _node_at(Vector2(10, 0))]
	for c: Command in [_node_command(AllocateCommand, npc, _node_at(Vector2.ZERO)),
			_node_command(DeallocateCommand, npc, _node_at(Vector2.ZERO)),
			set_cmd, move]:
		assert_false(_dir._build_command_request(c).mandatory, c.type_tag())


# --- helpers ----------------------------------------------------------------

## A context past the grace window, so `decide` reaches the real policy.
func _ctx() -> CameraContext:
	var ctx := CameraContext.new()
	ctx.seconds_since_manual_input = 999.0
	ctx.viewport_size = Vector2(1440, 960)
	ctx.zoom = 1.0
	return ctx

extends GutTest

## #532 acceptance bullet 5b: "each instance stays bound to its own player" —
## the multiplayer harness's client is a SEAT (`SeatPolicy.seat(entity_id)`),
## not a COUCH, so a turn handover to some OTHER entity must never swing the
## local view — see `mp_dev_sandbox.gd::_setup_level` and
## `session/seat_policy.gd`'s `follows_active_turn()`.
##
## Drives a real [GameRoot] (same composition-root pattern as
## test_hot_seat_handover.gd) rather than SeatPolicy in isolation: the trap is
## specifically whether [method GameRoot._on_turn_started_for_handover] honours
## the policy, not whether the policy answers its own question correctly.

const _GAME_ROOT := preload("res://scenes/game_root.tscn")
const _SKILL_NODE := preload("res://skill_node/skill_node.tscn")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")

var _root: GameRoot
var _red: Entity
var _blue: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_root = _GAME_ROOT.instantiate()
	_root.auto_start_turn = false
	add_child_autofree(_root)
	await wait_physics_frames(2)

	_nodes = []
	for i in 4:
		var sn := _SKILL_NODE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 120, 0)
		_root.graph.add_skill_node(sn)
		_nodes.append(sn)
	for i in 3:
		_root.graph.add_edge(_nodes[i], _nodes[i + 1])

	_red = _root.spawn_entity("Red", Color.RED, _nodes[0], _BALANCED)
	_red.faction = _CAMP_1
	_red.is_human_controlled = true
	_blue = _root.spawn_entity("Blue", Color.BLUE, _nodes[3], _BALANCED)
	_blue.faction = _CAMP_2
	_blue.is_human_controlled = false

	# The harness client: pinned to Red, wire-shaped ("any run with a peer on
	# the other end") regardless of which entity is human-controlled.
	_root.seat_policy = SeatPolicy.seat(_red.entity_id)
	_root.bind_player(_red)
	await wait_physics_frames(1)


func _hand_turn_to(ent: Entity) -> void:
	var tm := _root.turn_manager
	if tm.current_entity != null:
		var prev := tm.current_entity
		tm.current_entity = null
		tm.turn_ended.emit(prev)
	tm.start_turn(ent)


func test_a_seat_stays_pinned_across_a_turn_handover_to_someone_else() -> void:
	_hand_turn_to(_red)
	assert_eq(_root.player, _red, "sanity: opens bound to the seated hero")

	_hand_turn_to(_blue)
	await wait_physics_frames(1)

	assert_eq(_root.player, _red,
			"a SEAT policy must not swing the view onto whoever's turn it is — " \
			+ "that is the COUCH behaviour, and this is not a couch session")
	assert_eq(_root.input_ctl.player, _red)

	_hand_turn_to(_red)
	await wait_physics_frames(1)
	assert_eq(_root.player, _red, "and stays put once the turn returns too")


func test_a_couch_by_contrast_does_follow_the_active_turn() -> void:
	# Sanity check that this fixture is capable of proving a real handover —
	# without it, the SEAT test above could pass because nothing here ever
	# rebinds at all.
	_root.seat_policy = SeatPolicy.couch()
	_blue.is_human_controlled = true

	_hand_turn_to(_red)
	_hand_turn_to(_blue)
	await wait_physics_frames(1)

	assert_eq(_root.player, _blue, "sanity: a COUCH DOES follow the active turn")

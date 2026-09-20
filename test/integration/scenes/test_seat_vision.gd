extends GutTest

## [SeatPolicy] on a live [GameRoot] — the cases `test_hot_seat_handover.gd`
## does not cover, because it is a coop couch by construction:
##
##   1. **Couch versus** — two humans, DIFFERENT camps. Fog must not be shared,
##      and must swap on handover (the mirror image of coop's no-flash rule).
##   2. **A seated peer** — the view is pinned, so another human's turn moves
##      nothing, with no signal un-wiring anywhere.
##
## Same fixture shape as the handover test: a real `game_root.tscn`, a roster,
## a hand-driven turn loop.

const _GAME_ROOT := preload("res://scenes/game_root.tscn")
const _SKILL_NODE := preload("res://skill_node/skill_node.tscn")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")

var _root: GameRoot
var _p1: Entity
var _p2: Entity
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

	_p1 = _root.spawn_entity("P1", Color.CYAN, _nodes[0], _BALANCED)
	_p2 = _root.spawn_entity("P2", Color.ORANGE, _nodes[3], _BALANCED)

	# Versus: two local humans on two camps. One preset, one couch — the only
	# difference from coop is `Participant.camp` (#516's premise).
	var roster := ParticipantRoster.new()
	for i in 2:
		var p := Participant.new()
		p.id = i
		p.kind = Participant.Kind.HUMAN
		p.camp = _CAMP_1 if i == 0 else _CAMP_2
		roster.add(p)
	GameRoot.apply_roster({0: _p1, 1: _p2}, roster)
	_root.seat_policy = SeatPolicy.from_roster({0: _p1, 1: _p2}, roster)

	_root.bind_player(_p1)
	await wait_physics_frames(1)


func _hand_turn_to(ent: Entity) -> void:
	var tm := _root.turn_manager
	if tm.current_entity != null:
		var prev := tm.current_entity
		tm.current_entity = null
		tm.turn_ended.emit(prev)
	tm.start_turn(ent)


# --- Couch versus ---------------------------------------------------------

func test_two_local_humans_on_different_camps_are_hostile() -> void:
	assert_eq(_p1.attitude_to(_p2), Entity.Attitude.HOSTILE,
			"local versus falls out of the roster's camps — no mode flag needed")


func test_a_rival_does_not_see_for_me() -> void:
	assert_eq(_root.vision_system.viewers, [_p1] as Array[Entity],
			"versus fog is per-hero: my rival at the same keyboard is not my viewer")


func test_handover_swaps_the_fog_to_the_incoming_rival() -> void:
	_hand_turn_to(_p1)
	assert_eq(_root.vision_system.viewers, [_p1] as Array[Entity])

	_hand_turn_to(_p2)
	await wait_physics_frames(1)
	assert_eq(_root.player, _p2, "a couch hands over whatever the camps are")
	assert_eq(_root.vision_system.viewers, [_p2] as Array[Entity],
			"and the fog re-derives — the one case where a reassign is CORRECT")


# --- A seated peer --------------------------------------------------------

func test_a_seat_ignores_another_humans_turn() -> void:
	_root.seat_policy = SeatPolicy.seat(_p1.entity_id)
	_root.bind_player(_p1)
	await wait_physics_frames(1)

	_hand_turn_to(_p2)
	await wait_physics_frames(1)

	assert_eq(_root.player, _p1,
			"behind a wire the local view stays on the local hero")
	assert_eq(_root.input_ctl.player, _p1)
	assert_eq(_root.vision_system.viewers, [_p1] as Array[Entity],
			"and draws the local hero's fog, not the acting hero's")


## The handover signal stays connected on every machine — the policy is what
## decides, not the wiring. (The multiplayer harness used to disconnect it by
## hand; a policy that only works because someone remembered to un-wire a
## signal is not a policy.)
func test_the_handover_signal_is_connected_even_in_a_seat() -> void:
	_root.seat_policy = SeatPolicy.seat(_p1.entity_id)
	assert_true(_root.turn_manager.turn_started.is_connected(
			_root._on_turn_started_for_handover))

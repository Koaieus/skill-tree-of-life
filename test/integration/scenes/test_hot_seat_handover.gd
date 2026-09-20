extends GutTest

## #459 — hot-seat coop: two humans, one machine, alternating turns.
##
## Drives a real [GameRoot] (the composition root instantiated from its own
## scene, so the systems, the HUD and their wiring are the shipping ones) with
## a roster of two human participants at this peer on the same camp, per the issue's
## "test-driven, against a roster constructed in a test, not menu UI".
##
## The three seams under test:
##   1. [method HudRoot.rebind_player] — the clusters re-point, and stop
##      listening to the outgoing hero's board (the leak is the real bug: a
##      still-connected gauge keeps rendering player 1's pools).
##   2. Input transient state — armed modes / attack plan / targeting are
##      cleared on handover, so player 2 does not inherit a half-built swing.
##   3. Camp-wide [member VisionSystem.viewers] — an allied handover must not
##      re-derive fog from a different subgraph and flash the map.

const _GAME_ROOT := preload("res://scenes/game_root.tscn")
const _SKILL_NODE := preload("res://skill_node/skill_node.tscn")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _NPC := preload("res://entity/factions/npc.tres")

var _root: GameRoot
var _p1: Entity
var _p2: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_root = _GAME_ROOT.instantiate()
	# GameRoot._ready is a coroutine: its tail resumes a frame later and would
	# `start_turn` on whoever this fixture has bound by then, tripping the
	# "already in a turn" assert. The turn loop here is driven by hand.
	_root.auto_start_turn = false
	add_child_autofree(_root)
	await wait_physics_frames(2)

	# A tiny line graph: one core per hero, plus a spare each side.
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

	# The roster IS the fixture (#475's seam): two local humans, one camp.
	var roster := ParticipantRoster.new()
	for i in 2:
		var p := Participant.new()
		p.id = i
		p.kind = Participant.Kind.HUMAN
		p.camp = _CAMP_1
		roster.add(p)
	GameRoot.apply_roster({0: _p1, 1: _p2}, roster)

	_root.bind_player(_p1)
	await wait_physics_frames(1)


## Hand the turn to [param ent] deterministically.
##
## NOT [method TurnManager.end_turn]: that ends the turn AND auto-serves the
## next entity whose initiative happens to be ready, which is the right
## behaviour in play and the wrong thing for a seam test to depend on. The
## seam rides `turn_started`, so this reproduces the pair of beats the loop
## emits without letting initiative pick the actor.
func _hand_turn_to(ent: Entity) -> void:
	var tm := _root.turn_manager
	if tm.current_entity != null:
		var prev := tm.current_entity
		tm.current_entity = null
		tm.turn_ended.emit(prev)
	tm.start_turn(ent)


## The roster's own promise, re-asserted on a live level rather than in
## isolation: neither human is AI-driven, and they are allies.
func test_two_humans_are_allied_and_neither_is_ai_driven() -> void:
	assert_true(_p1.is_human_controlled)
	assert_true(_p2.is_human_controlled)
	assert_eq(_p1.attitude_to(_p2), Entity.Attitude.ALLIED)
	for ent in [_p1, _p2]:
		for child in ent.get_children():
			assert_false(child is AIController,
					"%s must not be AI-driven — a second human plays itself otherwise" % ent.name)


func test_two_turns_of_alternating_human_control() -> void:
	_hand_turn_to(_p1)
	assert_eq(_root.player, _p1, "player 1 opens")
	assert_eq(_root.input_ctl.player, _p1)

	_hand_turn_to(_p2)
	await wait_physics_frames(1)
	assert_eq(_root.player, _p2, "the turn handed over to player 2")
	assert_eq(_root.input_ctl.player, _p2, "input follows the active hero")
	assert_eq(_root.highlight_controller.player, _p2)

	_hand_turn_to(_p1)
	await wait_physics_frames(1)
	assert_eq(_root.player, _p1, "and back again")
	assert_eq(_root.input_ctl.player, _p1)


## An AI turn between two human turns must NOT steal the local view.
func test_an_ai_turn_does_not_rebind_the_player() -> void:
	var npc := _root.spawn_entity("NPC", Color.RED, _nodes[2], _BALANCED, true)
	npc.faction = _NPC
	npc.is_human_controlled = false

	_hand_turn_to(_p1)
	_hand_turn_to(npc)
	await wait_physics_frames(1)

	assert_eq(_root.player, _p1, "an AI turn leaves the local hero bound")
	assert_eq(_root.input_ctl.player, _p1)


# --- Seam 1: the HUD re-points, and lets go ------------------------------

func test_handover_releases_the_outgoing_heros_board() -> void:
	# Player 2 has never been bound, so its counts are the unbound baseline.
	# (An absolute "no connections" bar would never hold: a stat's
	# `value_changed` also carries the board's own modifier-graph edges.)
	var watched: Array[StringName] = [&"health", &"mana", &"action_points", &"xp", &"initiative"]
	var baseline := {}
	for stat_id in watched:
		baseline[stat_id] = _connection_count(_p2, stat_id)

	_hand_turn_to(_p1)
	_hand_turn_to(_p2)
	await wait_physics_frames(1)
	var bound_more := 0
	for stat_id in watched:
		if _connection_count(_p2, stat_id) > int(baseline[stat_id]):
			bound_more += 1
	assert_gt(bound_more, 0, "sanity: binding player 2 connected something at all")

	_hand_turn_to(_p1)
	await wait_physics_frames(1)
	for stat_id in watched:
		assert_eq(_connection_count(_p2, stat_id), int(baseline[stat_id]),
				"handing the turn back must leave nothing listening to player 2's %s" % stat_id)


func _connection_count(ent: Entity, stat_id: StringName) -> int:
	var stat: Stat = ent.stat_board.get_stat(stat_id)
	if stat == null:
		return 0
	var total := 0
	for sig in stat.get_signal_list():
		total += stat.get_signal_connection_list(sig["name"]).size()
	return total


func test_the_hud_follows_the_active_hero_and_not_the_previous_one() -> void:
	var gauge: PoolGauge = _root.hud_root.hero_sigil_card.get_node("%HealthGauge")

	_hand_turn_to(_p1)
	_hand_turn_to(_p2)
	await wait_physics_frames(1)
	var after_handover := gauge.max_value

	# The OUTGOING hero's pool must no longer drive the card...
	_p1.stat_board.health.base_value = _p1.stat_board.health.base_value + 50.0
	await wait_physics_frames(1)
	assert_eq(gauge.max_value, after_handover,
			"player 1's health must not move player 2's gauge")

	# ...and the INCOMING one must. (Without this, a rebind that connects
	# nothing at all would pass the assert above.)
	_p2.stat_board.health.base_value = _p2.stat_board.health.base_value + 50.0
	await wait_physics_frames(1)
	assert_ne(gauge.max_value, after_handover,
			"player 2's health must drive the gauge it is now bound to")


## The emblem carries ownership (same contract as a node's `entity_tint` on the
## board), so on a hot-seat handover it must recolour to whoever now holds the
## turn — otherwise the most prominent card on screen keeps flying the previous
## hero's colours.
func test_the_emblem_takes_the_active_heros_colour() -> void:
	var card := _root.hud_root.hero_sigil_card
	var ring: EmblemRing = card.get_node("%EmblemRing")
	var sigil: SigilGlyph = card.get_node("%SigilGlyph")

	# No extra `await` here: the very first bind comes from `compose` at level
	# open, and the card's marks are `@onready`. If that bind could land before
	# the card's own `_ready`, the tint would silently no-op and the emblem
	# would only ever colour after the first handover.
	assert_eq(ring.entity_tint, _p1.color, "the ring is coloured from level open")
	assert_eq(sigil.entity_tint, _p1.color, "and so is the sigil")

	_hand_turn_to(_p1)
	await wait_physics_frames(1)
	assert_eq(ring.entity_tint, _p1.color, "the ring holds player 1's colour")

	_hand_turn_to(_p2)
	await wait_physics_frames(1)
	assert_eq(ring.entity_tint, _p2.color, "the ring follows the incoming hero")
	assert_eq(sigil.entity_tint, _p2.color)

	# Binding nobody (level teardown) must let go of the colour too.
	card.bind(null)
	assert_eq(ring.entity_tint.a, 0.0, "an unbound card falls back to its authored hue")
	assert_eq(sigil.entity_tint.a, 0.0)


# --- Seam 2: transient input state ---------------------------------------

func test_handover_clears_a_half_built_swing() -> void:
	_hand_turn_to(_p1)
	_root.battle_system.request_attack_mode(BattleSystem.AttackMode.MELEE)
	_root.input_ctl.arm_manage_verb(PlayerInputController.ManageVerb.STAKE)
	assert_true(_root.battle_system.is_attacking, "sanity: player 1 armed a swing")

	_hand_turn_to(_p2)
	await wait_physics_frames(1)

	assert_false(_root.battle_system.is_attacking,
			"player 2 must not inherit player 1's attack plan")
	assert_eq(_root.input_ctl.manage_arm(), PlayerInputController.ManageVerb.NONE,
			"nor a leftover armed Manage verb")
	assert_null(_root.input_ctl.move_targeting_source())
	assert_true(_root.input_ctl.can_player_act(),
			"and must not arrive with input still frozen")


func test_rebinding_the_same_hero_leaves_a_live_arm_alone() -> void:
	# `bind_player` is documented as idempotently re-callable, and GameRoot
	# calls it more than once during setup — re-asserting the CURRENT hero
	# must not wipe the swing they are in the middle of building.
	_hand_turn_to(_p1)
	_root.battle_system.request_attack_mode(BattleSystem.AttackMode.MELEE)

	_root.bind_player(_p1)

	assert_true(_root.battle_system.is_attacking)


# --- Seam 3: camp-wide vision --------------------------------------------

func test_vision_viewers_are_the_whole_camp() -> void:
	assert_eq(_root.vision_system.viewers.size(), 2,
			"both allied humans see for the camp, not just whoever holds the turn")
	assert_true(_root.vision_system.viewers.has(_p1))
	assert_true(_root.vision_system.viewers.has(_p2))


func test_handover_does_not_re_derive_fog() -> void:
	_hand_turn_to(_p1)
	var before: Array[Entity] = _root.vision_system.viewers

	_hand_turn_to(_p2)
	await wait_physics_frames(1)

	# `is_same`, not `==`: Array equality in GDScript is element-wise, so `==`
	# would pass whether the setter was skipped OR reassigned an equal array —
	# and reassignment is exactly the flash (the setter unconditionally rebinds
	# every viewer stat and recomputes). Only reference identity proves the skip.
	assert_true(is_same(before, _root.vision_system.viewers),
			"an allied handover must not reassign viewers — that is the fog flash")


func test_an_enemy_camp_is_not_a_viewer() -> void:
	var npc := _root.spawn_entity("NPC", Color.RED, _nodes[2], _BALANCED, true)
	npc.faction = _NPC
	await wait_physics_frames(1)

	_root.bind_player(_p2)
	assert_false(_root.vision_system.viewers.has(npc),
			"fog is camp-wide, not everyone-wide")
	assert_eq(_root.vision_system.viewers.size(), 2)

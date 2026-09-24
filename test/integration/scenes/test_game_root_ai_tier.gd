extends GutTest

## The AI tier is run shape on the seat: [method GameRoot._ensure_controllers]
## builds each AI hero's [AIController] at its [member Participant.ai_tier],
## read from [member GameSession.roster] by [member Entity.participant_id]; a
## level with no roster (the hand-authored sandbox shape) keeps the default.
## The mid-run handover half lives in `test_game_root_link_loss.gd`.

const _GAME_ROOT := preload("res://scenes/game_root.tscn")
const _SKILL_NODE := preload("res://skill_node/skill_node.tscn")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")

var _root: GameRoot
var _human: Entity
var _bot: Entity


func before_each() -> void:
	GameSession.end()
	_root = _GAME_ROOT.instantiate()
	_root.get_node("%TurnManager").opens_first_turn = false
	_root.route_to_meta_on_run_end = false
	add_child_autofree(_root)
	await wait_frames(6)

	var nodes: Array[SkillNode] = []
	for i in 2:
		var sn := _SKILL_NODE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 120, 0)
		_root.graph.add_skill_node(sn)
		nodes.append(sn)
	_root.graph.add_edge(nodes[0], nodes[1])
	_human = _root.spawn_entity("Human", Color.CYAN, nodes[0], _BALANCED)
	_bot = _root.spawn_entity("Bot", Color.ORANGE, nodes[1], _BALANCED)


func after_each() -> void:
	GameSession.end()


func _seat(id: int, kind: Participant.Kind, camp: Faction) -> Participant:
	var p := Participant.new()
	p.id = id
	p.kind = kind
	p.camp = camp
	return p


func test_an_ai_seat_spawns_its_controller_at_the_seats_tier() -> void:
	var roster := ParticipantRoster.new()
	roster.add(_seat(1, Participant.Kind.HUMAN, _CAMP_1))
	var bot_seat := _seat(2, Participant.Kind.AI, _CAMP_2)
	bot_seat.ai_tier = AIController.Tier.BRAWLER
	roster.add(bot_seat)
	GameSession.roster = roster
	GameRoot.apply_roster({1: _human, 2: _bot}, roster)

	_root._ensure_controllers()

	var ai := GameRoot._find_controller(_bot) as AIController
	assert_not_null(ai, "the AI seat got an AIController")
	if ai != null:
		assert_eq(ai.ai_tier, AIController.Tier.BRAWLER)


func test_no_roster_leaves_the_default_tier() -> void:
	_bot.is_human_controlled = false
	_root._ensure_controllers()

	var ai := GameRoot._find_controller(_bot) as AIController
	assert_not_null(ai)
	if ai != null:
		assert_eq(ai.ai_tier, AIController.DEFAULT_TIER)

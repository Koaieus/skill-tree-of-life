extends GutTest

## #1333 — a level whose world ARRIVES generates none, with no network involved.
## The same outcome assertion `test_client_skips_procgen.gd` makes for a joining
## client, but with no client role set: [member GameSession.world_source] alone
## decides, so a world loaded from disk takes this path too.

const _LEVEL := preload("res://scenes/level.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")


func before_each() -> void:
	GameSession.end()
	GameSession.network = null
	GameSession.local_peer_id = 0


func after_each() -> void:
	GameSession.end()
	GameSession.network = null
	GameSession.local_peer_id = 0


func _roster() -> ParticipantRoster:
	var roster := ParticipantRoster.new()
	for spec in [[1, "Red", _PLAYER_FACTION], [2, "Blue", _NPC_FACTION]]:
		var p := Participant.new()
		p.id = int(spec[0])
		p.display_name = String(spec[1])
		p.camp = spec[2] as Faction
		p.kind = Participant.Kind.HUMAN
		roster.add(p)
	return roster


func _build_level() -> GameRoot:
	var cfg := RunConfig.new()
	cfg.seed = 90210715
	GameSession.apply_received(cfg, _roster())
	var root: GameRoot = _LEVEL.instantiate()
	root.name = "ArrivingLevel"
	root.get_node("%HudRoot").enabled = false
	root.get_node("%TurnManager").opens_first_turn = false
	root.get_node("%VisionSystem").enabled = false
	root.node_count_override = 40
	add_child_autofree(root)
	return root


## Both branches spawn the roster, and a generating one only after procgen has
## laid its nodes — so once entities exist, a generate call would have left
## nodes behind.
func _seated(root: GameRoot) -> void:
	await wait_until(func() -> bool: return not EntitySnapshot.entities_of(root.graph).is_empty(), 10.0)


func test_an_arriving_world_is_not_generated() -> void:
	var root := _build_level()
	await _seated(root)

	assert_eq(root.graph.get_skill_nodes().size(), 0,
			"world_source ARRIVES with no network still builds no map")
	assert_eq(root.graph.get_edges().size(), 0, "and no edges either")


func test_an_arriving_world_still_seats_the_roster() -> void:
	var root := _build_level()
	await _seated(root)

	var entities := EntitySnapshot.entities_of(root.graph)
	assert_eq(entities.size(), 2, "one entity per roster seat, and no blockers")
	assert_eq(entities[0].entity_id, 1, "ids mint by add-order")
	assert_eq(entities[1].entity_id, 2)

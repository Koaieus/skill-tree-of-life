extends GutTest

## ReloadCommand (#955): 1 AP, yield = Σ node-local arrows_per_reload over the
## turn-start leaf set ∪ core, specials flat, and the same on a mirror.
##
## World: a star — core A with leaves B, C, D — plus E hanging off B, which
## is allocated only AFTER the turn starts (the "pump closed" case). Every
## node sits at allocation level 1, so with the board's authored
## `arrows_per_reload` the expected yield is `4 * per_leaf` — the tests read
## the stat rather than pin the .tres number (owner tunes, agents test).

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


class World:
	var graph: Graph
	var alloc: AllocationSystem
	var tm: TurnManager
	var applier: CommandApplier
	var player: Entity
	var nodes: Dictionary = {}

	func n(id: String) -> SkillNode:
		return nodes[id]

	func per_leaf() -> int:
		return int(player.stat_board.arrows_per_reload.get_value())

	func ap() -> int:
		return player.stat_board.action_points.available()

	func quiver() -> Quiver:
		return player.stat_board.arrows


func _build_world(poison_per_reload: float) -> World:
	var w := World.new()
	w.graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(w.graph)
	for id in ["A", "B", "C", "D", "E"]:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = id
		w.graph.add_skill_node(sn)
		w.nodes[id] = sn
	w.graph.add_edge(w.n("A"), w.n("B"))
	w.graph.add_edge(w.n("A"), w.n("C"))
	w.graph.add_edge(w.n("A"), w.n("D"))
	w.graph.add_edge(w.n("B"), w.n("E"))

	w.tm = autofree(TurnManager.new())
	add_child(w.tm)
	w.alloc = AllocationSystem.new()
	w.alloc.graph = w.graph
	w.alloc.navigator = w.graph.navigator
	w.alloc.turn_manager = w.tm
	add_child_autofree(w.alloc)

	w.player = autofree(Entity.new())
	w.player.display_name = "Archer"
	w.player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	w.player.stat_board.poison_arrows_per_reload.base_value = poison_per_reload
	w.graph.entities_container.add_child(w.player)
	await get_tree().process_frame

	w.player.core_location = w.n("A")
	for id in ["A", "B", "C", "D"]:
		w.alloc.force_allocate(w.player, w.n(id))
	w.tm.start_turn(w.player)
	w.player.stat_board.skill_points.grant(5)
	w.player.stat_board.action_points.restore_to_full()

	w.applier = CommandApplier.new()
	w.applier.graph = w.graph
	w.applier.allocation_system = w.alloc
	w.applier.turn_manager = w.tm
	add_child_autofree(w.applier)
	return w


func _reload(w: World) -> ReloadCommand:
	return ReloadCommand.new(w.player.entity_id)


func test_reload_costs_one_ap_and_adds_arrows_per_reload_per_turn_start_leaf() -> void:
	var w: World = await _build_world(0.0)
	var ap_before := w.ap()
	assert_eq(w.quiver().stock_of(&"arrow"), 0, "starts empty")
	w.applier.submit(_reload(w))
	assert_eq(w.ap(), ap_before - 1, "reload costs 1 AP")
	assert_eq(w.quiver().stock_of(&"arrow"), 4 * w.per_leaf(),
			"three turn-start leaves + the core, each minting arrows_per_reload")
	assert_eq(roundi(w.quiver().current), 4 * w.per_leaf())


func test_leaves_allocated_this_turn_do_not_count_toward_the_reload() -> void:
	var w: World = await _build_world(0.0)
	assert_true(w.alloc.allocate(w.n("E"), w.player), "E allocated after turn start")
	w.applier.submit(_reload(w))
	# B is no longer a leaf and E is a fresh one — the SET is the turn-start
	# one, so B still produces and E does not: the count does not move.
	assert_eq(w.quiver().stock_of(&"arrow"), 4 * w.per_leaf(),
			"the producer set was fixed at turn start")


func test_special_arrows_are_flat_never_times_leaves() -> void:
	var w: World = await _build_world(1.0)
	w.applier.submit(_reload(w))
	assert_eq(w.quiver().stock_of(&"poison"), 1, "one poison arrow, not one per leaf")
	assert_eq(w.quiver().stock_of(&"arrow"), 4 * w.per_leaf())
	assert_eq(roundi(w.quiver().current), 4 * w.per_leaf() + 1)


func test_reload_is_refused_without_ap_or_off_turn() -> void:
	var w: World = await _build_world(0.0)
	w.player.stat_board.action_points.set_current(0.0)
	w.applier.submit(_reload(w))
	assert_eq(w.quiver().stock_of(&"arrow"), 0, "no AP, no reload")
	w.player.stat_board.action_points.restore_to_full()
	w.tm.end_turn()
	w.applier.submit(_reload(w))
	assert_eq(w.quiver().stock_of(&"arrow"), 0, "not the actor's turn, no reload")


func test_reload_replays_identically_on_a_mirror() -> void:
	var host: World = await _build_world(1.0)
	var mirror: World = await _build_world(1.0)
	var cmd := _reload(host)
	var wire := cmd.to_dict()
	host.applier.submit(cmd)
	mirror.applier.submit(CommandCodec.from_dict(wire))
	assert_eq(mirror.quiver().to_dict(), host.quiver().to_dict(),
			"the same dict yields the same quiver on both peers")
	assert_eq(mirror.ap(), host.ap())

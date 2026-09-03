extends GutTest

## #715 — the three seams the join path now leans on, each of which had nothing
## holding it before.
##
## 1. [b]The world decodes onto an EMPTY graph as well as a populated one[/b]
##    (acceptance 7). Both shapes are live: empty is the JOIN, which since #715
##    is the primary path, and populated is a mid-run desync repair
##    (#521/#560/#561). They exercise different halves of
##    [method EntitySnapshot.resolve_graph_refs] — on an empty graph
##    [CommandLink] parks pass 2 and drains it when the nodes land; on a
##    populated one it runs straight through — so a change that fixes one and
##    breaks the other is exactly what this pins.
## 2. [b]A snapshot may rebuild an entity the roster never named[/b] — the
##    blockers procgen spawns, which a client that runs no procgen has no other
##    way to get. Without them their nodes decode as UNOWNED and the ownership
##    fold disagrees on the first compare.
## 3. [b][Wire] admits exactly one bound facade[/b]. Since #714 both the lobby and
##    the level mount one over the same socket, and two bound at once re-emit
##    every packet twice — a command applied twice, silently.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _BLOCKER_SCENE_PATH := "res://entity/blocker/blocker_entity.tscn"


func after_each() -> void:
	Wire.stop()


func _new_graph() -> Graph:
	var g: Graph = preload("res://graph/graph.tscn").instantiate()
	add_child_autofree(g)
	await wait_physics_frames(1)
	return g


## A small real world with a hero owning a core — enough for `core_location` and
## `owner_id` to mean something in both directions.
func _authority_world() -> Graph:
	var g := await _new_graph()
	var gcfg: GraphProcgenConfig = _PRESET.duplicate(true)
	gcfg.topology = gcfg.topology.duplicate(true)
	gcfg.topology.node_count = 24
	gcfg.camp_sizes = [2]
	gcfg.seed = 90210715
	var result: Dictionary = await GraphProcgen.generate(gcfg, g)
	var starts: Array = result.get("starting_nodes", [])
	assert_gt(starts.size(), 0, "sanity: procgen produced a starter")
	var hero: Entity = autofree(Entity.new())
	hero.display_name = "Red"
	hero.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	g.entities_container.add_child(hero)
	var core: SkillNode = starts[0]
	core.owned_by = hero
	hero.core_location = core
	return g


## The receiving half: the entities the roster spawns, and nothing else. This is
## exactly what `ProcgenPlaySandbox._setup_level` leaves behind on a client.
func _seated_peer(entity_ids: int) -> Graph:
	var g := await _new_graph()
	for i in entity_ids:
		var e: Entity = autofree(Entity.new())
		e.display_name = "Seat_%d" % i
		e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
		g.entities_container.add_child(e)
	return g


## Acceptance 7, shape one — the new PRIMARY path. The graph is empty when the
## world arrives, so [method EntitySnapshot.decode]'s pass 1 has no nodes to
## resolve against and pass 2 must run after [method GraphSnapshot.decode].
func test_the_world_decodes_onto_an_empty_graph_with_refs_resolved() -> void:
	var source := await _authority_world()
	var target := await _seated_peer(1)
	assert_true(target.get_skill_nodes().is_empty(), "sanity: the peer built no map")

	var entity_bytes := EntitySnapshot.encode(source)
	var graph_bytes := GraphSnapshot.encode(source)
	# The resync's own order, and the order that serves BOTH shapes.
	EntitySnapshot.decode(entity_bytes, target)
	GraphSnapshot.decode(graph_bytes, target)
	EntitySnapshot.resolve_graph_refs(entity_bytes, target)

	assert_eq(WorldFingerprint.compute(target), WorldFingerprint.compute(source),
			"a world decoded into nothing must equal the one it came from: %s vs %s"
			% [WorldFingerprint.describe(target), WorldFingerprint.describe(source)])
	var hero := target.get_by_entity_id(1)
	assert_not_null(hero, "the roster's seat was decorated, not replaced")
	assert_not_null(hero.core_location, "entity->node refs resolved against the new nodes")
	assert_eq(hero.core_location.owned_by, hero, "and node->entity resolved back")


## Acceptance 7, shape two — mid-run repair, which must keep working. The peer
## has a full (and WRONG) world; the same three calls in the same order
## reconcile it rather than doubling it.
func test_the_world_decodes_onto_a_populated_graph_with_refs_resolved() -> void:
	var source := await _authority_world()
	var target := await _authority_world()
	# Two independently generated worlds at the same seed are identical, so make
	# the receiving one genuinely wrong first.
	var doomed := target.get_skill_nodes()[3] as SkillNode
	doomed.owned_by = target.get_by_entity_id(1)
	assert_ne(WorldFingerprint.compute(target), WorldFingerprint.compute(source),
			"sanity: the peer's world really did drift")

	var entity_bytes := EntitySnapshot.encode(source)
	var graph_bytes := GraphSnapshot.encode(source)
	EntitySnapshot.decode(entity_bytes, target)
	GraphSnapshot.decode(graph_bytes, target)
	EntitySnapshot.resolve_graph_refs(entity_bytes, target)

	assert_eq(WorldFingerprint.compute(target), WorldFingerprint.compute(source),
			"the repair converged: %s vs %s"
			% [WorldFingerprint.describe(target), WorldFingerprint.describe(source)])
	var hero := target.get_by_entity_id(1)
	assert_not_null(hero.core_location, "core_location survived a reconcile onto a live world")
	assert_eq(target.get_skill_nodes().size(), source.get_skill_nodes().size())


## An entity the payload names and this peer does not have is REBUILT, at the
## authority's id, when a spawner is supplied — the blockers a client that runs
## no procgen never made.
func test_a_missing_entity_is_rebuilt_at_the_authoritys_id() -> void:
	var source := await _authority_world()
	# A real blocker: what procgen spawns and no roster names. It must come from
	# its SCENE — `scene_file_path` is what the row interns and what tells the
	# spawner which thing to rebuild, so a `.new()` stand-in would (correctly)
	# be refused as unbuildable.
	var extra := preload("res://entity/blocker/blocker_entity.tscn").instantiate() as Entity
	autofree(extra)
	extra.display_name = "Dormant Core (Small)"
	extra.entity_tier = 1
	extra.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	source.entities_container.add_child(extra)
	var extra_id := extra.entity_id
	assert_gt(extra_id, 0, "sanity: the graph minted it")

	var target := await _seated_peer(1)
	var asked: Array = []
	var spawner := func(id: int, scene_path: String, tier: int, _n: String) -> Entity:
		asked.append([id, scene_path, tier])
		var e: Entity = autofree(Entity.new())
		e.entity_id = id
		e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
		target.entities_container.add_child(e)
		return e

	var bytes := EntitySnapshot.encode(source)
	EntitySnapshot.decode(bytes, target, spawner)

	assert_eq(asked.size(), 1, "asked once, for the one entity this peer lacked")
	assert_eq((asked[0] as Array)[0], extra_id, "and at the AUTHORITY's id, not a fresh mint")
	assert_eq((asked[0] as Array)[1], _BLOCKER_SCENE_PATH,
			"the row carries the scene to rebuild it from")
	assert_eq((asked[0] as Array)[2], 1, "the tier rides the row, which is what names the size")
	assert_not_null(target.get_by_entity_id(extra_id), "it is reachable by that id afterwards")


## Without a spawner nothing changes: every existing caller, and every test
## written before #715, gets the pre-#715 skip-with-a-warning behaviour.
func test_no_spawner_means_no_spawn() -> void:
	var source := await _authority_world()
	var target := await _seated_peer(0)

	EntitySnapshot.decode(EntitySnapshot.encode(source), target)

	assert_eq(EntitySnapshot.entities_of(target).size(), 0,
			"a snapshot with no spawner still only DECORATES (#560 D7)")


## The level's facade refuses to bind while the lobby's still holds the wire —
## the #714 hand-off gap. Two bound facades re-emit `message_received`
## independently, so every packet is handled twice and nothing errors.
func test_wire_admits_exactly_one_bound_facade() -> void:
	Wire.start_host(0)
	var lobby_side := EnetTransport.new()
	add_child_autofree(lobby_side)
	var level_side := EnetTransport.new()
	add_child_autofree(level_side)

	assert_eq(lobby_side.start_host(0), OK, "the first facade adopts the live link")
	assert_true(Wire.has_binder(), "and holds it")
	assert_eq(level_side.start_host(0), ERR_ALREADY_IN_USE,
			"the second is REFUSED rather than left to double-handle every packet")

	var seen_by_level: Array = []
	level_side.message_received.connect(func(_p: Dictionary): seen_by_level.append(1))
	Wire.message_received.emit({"kind": "hello"})
	assert_eq(seen_by_level.size(), 0, "a refused facade re-emits nothing")


## And releasing hands it back, which is what makes the route out of the lobby
## work at all: the lobby releases, then the level adopts.
func test_releasing_the_wire_lets_the_next_facade_bind() -> void:
	Wire.start_host(0)
	var lobby_side := EnetTransport.new()
	add_child_autofree(lobby_side)
	assert_eq(lobby_side.start_host(0), OK)

	# What `LobbyScreen.release_link` does: free the node, whose `_exit_tree`
	# unbinds. The SOCKET is untouched.
	lobby_side.get_parent().remove_child(lobby_side)
	assert_false(Wire.has_binder(), "the wire is free again")
	assert_true(Wire.is_open(), "and the socket the level is about to adopt is still up")

	var level_side := EnetTransport.new()
	add_child_autofree(level_side)
	assert_eq(level_side.start_host(0), OK, "the level adopts what the lobby handed back")
	lobby_side.free()

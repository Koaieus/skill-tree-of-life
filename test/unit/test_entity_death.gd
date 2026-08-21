extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## Entity death (#18). When an entity's core HP reaches 0 it dies: emits `died`
## + `Events.entity_died`, and every node it owns is force-deallocated off the
## bus by AllocationSystem. "Core HP" is the entity's `health` PoolStat — the
## core SkillNode never depletes; combat-HP overflow on it (and the battle
## cascade's chip damage) eats `health` instead (see SkillNode.take_damage).
##
## Death is triggered via the REALISTIC paths (core overflow + cascade chip
## damage), not by calling die() directly — death fires synchronously mid-cascade
## and a direct-die() test would hide that re-entrancy. GameRoot's player-vs-NPC
## branch (game-over vs despawn) is covered separately on a bare GameRoot.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _entity: Entity
var _nodes: Array[SkillNode]
var _died_count: int = 0


func before_each() -> void:
	_died_count = 0

	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	# Line core(N0) – N1 – N2.
	_add_edge(_nodes[0], _nodes[1])
	_add_edge(_nodes[1], _nodes[2])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_battle = BattleSystem.new()
	_battle.allocation_system = _alloc
	_battle.graph = _graph
	add_child_autofree(_battle)

	_entity = autofree(Entity.new())
	_entity.display_name = "Victim"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)

	await get_tree().process_frame  # entity._ready: navigator + health.depleted wiring

	for n in _nodes:
		_alloc.force_allocate(_entity, n)  # populates the navigator mirror + SP
	_entity.core_location = _nodes[0]

	Events.entity_died.connect(_count_death)


func after_each() -> void:
	if Events.entity_died.is_connected(_count_death):
		Events.entity_died.disconnect(_count_death)


func _count_death(_e: Entity) -> void:
	_died_count += 1


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


func _owned_count() -> int:
	var c := 0
	for n in _graph.get_skill_nodes():
		if n.owned_by == _entity:
			c += 1
	return c


# ── Core-overflow death path ─────────────────────────────────────────────────

func test_core_overflow_to_zero_health_kills_entity() -> void:
	_entity.stat_board.health.set_current(1.0)
	# Hit the core hard enough that overflow past its combat HP drains the 1 HP
	# left on the `health` pool — the canonical "core destroyed" path.
	_nodes[0].take_damage(10000.0, null)
	assert_true(_entity.is_dead, "entity should latch is_dead when health hits 0")
	assert_eq(_died_count, 1, "Events.entity_died should fire exactly once")


func test_death_force_deallocates_all_owned_nodes() -> void:
	assert_eq(_owned_count(), 3, "precondition: entity owns all 3 nodes")
	_entity.stat_board.health.set_current(1.0)
	_nodes[0].take_damage(10000.0, null)
	assert_eq(_owned_count(), 0, "every owned node (incl. core) should be deallocated")


# ── Cascade-triggered death (re-entrancy) ────────────────────────────────────

func test_cascade_chip_damage_can_kill_mid_cascade() -> void:
	# Depleting N1 islands N2 from the core → a 2-node forced-dealloc cascade.
	# With health at 1 and dealloc_damage 1, the first cascaded node's chip
	# damage drops health to 0 → die() fires WHILE BattleSystem still iterates
	# the rest of the cascade. The synchronous cleanup deallocates the remaining
	# cascade nodes; BattleSystem's `owned_by != defender` guard then skips them.
	# Must not crash or double-fire.
	_entity.stat_board.health.set_current(1.0)
	_nodes[1].take_damage(10000.0, null)  # deplete N1 → Events.skill_node_depleted
	assert_true(_entity.is_dead, "cascade chip damage should kill the entity")
	assert_eq(_died_count, 1, "death must fire exactly once even mid-cascade")
	assert_eq(_owned_count(), 0, "cleanup strips every owned node")


# ── Real-bus race: deallocate before free ────────────────────────────────────

func test_npc_death_via_bus_deallocates_before_free() -> void:
	# Both real consequences live at once, as in gameplay: AllocationSystem
	# deallocates the corpse's nodes SYNCHRONOUSLY off the `entity_died` emit,
	# then a GameRoot stand-in queue_frees it. Because the deallocate completes
	# before the free is even queued, the nodes can't be orphaned on a freed
	# owner — this is why the cleanup is synchronous, not deferred.
	var despawn := func(e: Entity) -> void: e.queue_free()
	Events.entity_died.connect(despawn)
	_entity.stat_board.health.set_current(1.0)
	_nodes[0].take_damage(10000.0, null)
	assert_eq(_owned_count(), 0, "nodes deallocated synchronously, before the free")
	await get_tree().process_frame  # let queue_free flush
	assert_false(is_instance_valid(_entity), "entity is freed after cleanup ran")
	Events.entity_died.disconnect(despawn)


# ── Idempotency ──────────────────────────────────────────────────────────────

func test_die_is_idempotent() -> void:
	_entity.stat_board.health.set_current(1.0)
	_nodes[0].take_damage(10000.0, null)
	assert_eq(_died_count, 1)
	# A second trigger (e.g. another hit landing the same frame) must no-op.
	_entity.die()
	_entity.stat_board.health.deplete(5.0)
	assert_eq(_died_count, 1, "is_dead guard blocks repeat death emission")


# ── GameRoot player-vs-NPC branch ────────────────────────────────────────────

func test_gameroot_player_death_shows_game_over_overlay() -> void:
	# HudRoot listens to the Events.game_over signal and toggles the
	# pre-composed GameOverOverlay visible — verify the wiring end-to-end.
	var hud := preload("res://ui/hud/hud_root.tscn").instantiate()
	autofree(hud)
	add_child(hud)
	Events.game_over.emit()
	assert_true(hud.game_over_overlay.visible,
			"game_over signal should make the overlay visible")


func test_gameroot_npc_death_despawns_and_leaves_turn_groups() -> void:
	var gr := GameRoot.new()
	autofree(gr)
	var npc := Entity.new()
	npc.display_name = "NPC"
	_graph.add_child(npc)  # joins Entity.GROUP via _enter_tree
	npc.add_to_group(Entity.READY_GROUP)
	gr.player = _entity  # someone else is the player
	gr._on_entity_died(npc)
	assert_false(npc.is_in_group(Entity.GROUP),
			"dead NPC must leave the entities group so TurnManager skips it")
	assert_false(npc.is_in_group(Entity.READY_GROUP), "and the ready group")
	assert_false(npc.is_queued_for_deletion(),
			"`entity_died` alone does not despawn — that rides `entity_death_shown`")
	# This test drives `_on_entity_died` directly rather than through a real
	# death, so nothing has emitted `entity_death_shown` yet. Drive it.
	gr._on_entity_death_shown(npc)
	assert_true(npc.is_queued_for_deletion(), "NPC corpse should be freed")
	await get_tree().process_frame  # let the deferred free run before teardown


## #460: the player corpse gets the same turn-loop pull as an NPC. It used to be
## skipped, which was safe only while player death ended play on the spot —
## VictorySystem decides that now, and in hot-seat coop a dead player can leave a
## living ally, so the loop keeps running. Left in the groups, TurnManager would
## go on replenishing a dead entity's initiative and eventually hand it the turn,
## where PlayerController waits forever for input that cannot come.
func test_gameroot_player_death_leaves_turn_groups_but_keeps_the_corpse() -> void:
	var gr := GameRoot.new()
	autofree(gr)
	var human := Entity.new()
	human.display_name = "Player"
	_graph.add_child(human)  # joins Entity.GROUP via _enter_tree
	human.add_to_group(Entity.READY_GROUP)
	gr.player = human

	gr._on_entity_died(human)

	assert_false(human.is_in_group(Entity.GROUP),
			"a dead player must leave the entities group — the loop would stall on it")
	assert_false(human.is_in_group(Entity.READY_GROUP), "and the ready group")

	gr._on_entity_death_shown(human)
	assert_false(human.is_queued_for_deletion(),
			"the player corpse stays in the tree — camera/HUD still point at it")


## #504: the despawn seam is about ORDER, not delay.
##
## Design A held the corpse on screen until a recorded ENTITY_DEATH reveal
## played, so the despawn lagged model mutation by the killing blow's flight
## time. Under design B the entity dies at the moment it is drawn dying, so
## there is nothing to wait for — but `entity_death_shown` still exists, and
## still matters, because GameRoot despawns on it while AllocationSystem strips
## the corpse's nodes on `entity_died`. `Entity.die()` emits the two in that
## order, and this pins it: a despawn that raced ahead of the strip would leave
## nodes owned by a freed entity (see `.claude/rules/entity-death.md`).
func test_death_strips_nodes_before_the_despawn_signal_fires() -> void:
	var owned_at_despawn: Array[int] = []
	var on_shown := func(e: Entity) -> void:
		if e != _entity:
			return
		var still_owned := 0
		for sn in _nodes:
			if sn.owned_by == _entity:
				still_owned += 1
		owned_at_despawn.append(still_owned)
	Events.entity_death_shown.connect(on_shown)

	_entity.stat_board.health.deplete(_entity.stat_board.health.current)

	Events.entity_death_shown.disconnect(on_shown)
	assert_true(_entity.is_dead, "health reaching 0 should kill the entity")
	assert_eq(owned_at_despawn.size(), 1,
			"entity_death_shown must fire exactly once for the death")
	assert_eq(owned_at_despawn[0], 0,
			"the corpse's nodes must already be stripped when the despawn signal fires")


## The despawn consequence itself still rides `entity_death_shown` — GameRoot
## frees an NPC corpse on it, and nothing else.
func test_gameroot_npc_despawn_fires_on_the_death_shown_signal() -> void:
	var gr := GameRoot.new()
	autofree(gr)
	gr.player = autofree(Entity.new())  # someone else is the player
	# GameRoot.new() is never added to the tree here (its _ready expects a full
	# level scene's %UniqueName children), so wire the one signal this test
	# needs by hand instead of going through _ready.
	Events.entity_death_shown.connect(gr._on_entity_death_shown)
	_entity.stat_board.health.deplete(_entity.stat_board.health.current)
	assert_true(_entity.is_dead, "health reaching 0 should kill the entity")
	assert_true(_entity.is_queued_for_deletion(),
			"the NPC corpse should be freed once the death is shown")
	Events.entity_death_shown.disconnect(gr._on_entity_death_shown)
	await get_tree().process_frame

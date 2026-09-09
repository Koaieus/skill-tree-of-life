extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## Removable node blockers (#300): a blocker is a real Entity owning its
## blocked node. Its tiered board gives the node its HP (`10 + node_health_scaling
## × CON`) and the entity a 1 HP pool, no initiative, and no vision — so the
## damage path, allocation gate, death cleanup, and loot flow are all existing
## mechanics. The node dies with the blocker, returns to the graph unallocated,
## and blocks allocation from everyone while it lives.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SMALL_BOARD := preload("res://entity/blocker/blocker_small_board.tres")
const _MEDIUM_BOARD := preload("res://entity/blocker/blocker_medium_board.tres")
const _LARGE_BOARD := preload("res://entity/blocker/blocker_large_board.tres")
const _MEDIUM_SPELLBOOK := preload("res://entity/blocker/blocker_spellbook_medium.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _player: Entity
var _nodes: Array[SkillNode] = []


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	_add_edge(_nodes[0], _nodes[1])
	_add_edge(_nodes[1], _nodes[2])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_tm = TurnManager.new()
	add_child_autofree(_tm)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.faction = _PLAYER_FACTION
	_player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_player)

	await get_tree().process_frame  # _ready: navigators + health wiring

	_alloc.force_allocate(_player, _nodes[0])
	_player.core_location = _nodes[0]


## Build a blocker owning `_nodes[1]` directly (not via GameRoot) — the
## mechanics-under-test, isolated from the composition root.
func _spawn_blocker(board: EntityStatBoard, tier: int) -> Entity:
	var blocker := Entity.new()
	blocker.display_name = "Blocker"
	blocker.stat_board = board.duplicate(true) as EntityStatBoard
	blocker.entity_tier = tier
	_graph.add_child(blocker)
	await get_tree().process_frame  # _ready: board dup + intrinsics + health wiring
	_alloc.force_allocate(blocker, _nodes[1])
	blocker.core_location = _nodes[1]
	return blocker


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


# ── Tiered board ─────────────────────────────────────────────────────────────

func test_tier_2_blocker_node_hp_armor_health() -> void:
	var blocker := await _spawn_blocker(_MEDIUM_BOARD, 2)
	assert_eq(_nodes[1].get_max_hp(), 40.0, "node HP = 10 + 1×CON 30")
	assert_eq(float(blocker.stat_board.armor.value), 3.0, "armor 3")
	assert_eq(float(blocker.stat_board.health.value), 1.0, "entity health pool 1")
	assert_eq(float(blocker.stat_board.health.current), 1.0, "health starts full")


func test_blocker_board_has_no_initiative() -> void:
	var blocker := await _spawn_blocker(_MEDIUM_BOARD, 2)
	assert_null(blocker.stat_board.initiative, "no initiative clock")
	assert_null(blocker.stat_board.initiative_speed, "no initiative speed")


func test_vision_and_sensor_are_zero() -> void:
	var blocker := await _spawn_blocker(_MEDIUM_BOARD, 2)
	assert_eq(float(blocker.stat_board.vision_range.value), 0.0, "blind blocker")
	assert_eq(float(blocker.stat_board.sensor_range.value), 0.0, "no sensing")


# ── No-turn is free ──────────────────────────────────────────────────────────

func test_blocker_never_readies_and_never_regens() -> void:
	var blocker := await _spawn_blocker(_MEDIUM_BOARD, 2)
	assert_false(blocker.is_in_group(Entity.READY_GROUP), "not ready at spawn")
	for _i in 5:
		_tm.tick()
	assert_false(blocker.is_in_group(Entity.READY_GROUP), "no initiative → never ready")
	# No turn → no turn-start regen sweep → node HP stays put.
	_nodes[1].take_damage(10.0, null)
	var after_damage := _nodes[1].get_current_hp()
	for _i in 5:
		_tm.tick()
	assert_eq(_nodes[1].get_current_hp(), after_damage, "no owner turn → no node HP regen")


# ── Damage-to-clear / death cleanup ───────────────────────────────────────────

func test_blocker_dies_on_node_hp_empty_and_node_returns_unallocated() -> void:
	# A marker on the node proves its original modifiers survive the strip.
	var marker := StatModifier.new()
	marker.stat_id = &"armor"
	marker.operation = StatModifier.Operation.ADD_BASE
	marker.value = 2.0
	_nodes[1].modifiers.append(marker)

	var blocker := await _spawn_blocker(_MEDIUM_BOARD, 2)
	assert_false(blocker.is_dead, "precondition")
	_nodes[1].take_damage(10000.0, null)  # node HP empties → overflow ≥ min_damage → health 1 → die()
	assert_true(blocker.is_dead, "dies on the hit that empties the node")
	assert_eq(_nodes[1].owned_by, null, "after entity_died the node is unallocated")
	assert_true(_nodes[1].modifiers.has(marker), "original node modifiers intact")


# ── Faction + gating ─────────────────────────────────────────────────────────

func test_blocker_faction_hostile_to_player_allied_to_npc() -> void:
	var blocker := await _spawn_blocker(_MEDIUM_BOARD, 2)
	assert_eq(_player.attitude_to(blocker), Entity.Attitude.HOSTILE, "npc faction ≠ player faction")
	var npc := Entity.new()
	autofree(npc)
	npc.faction = _NPC_FACTION
	assert_eq(npc.attitude_to(blocker), Entity.Attitude.ALLIED, "NPC AI is allied to blockers")


func test_blocked_node_cannot_be_allocated() -> void:
	await _spawn_blocker(_MEDIUM_BOARD, 2)
	assert_false(_alloc.can_allocate(_nodes[1], _player), "foreign-owned node rejects the player")
	var other: Entity = Entity.new()
	autofree(other)
	other.display_name = "Other"
	other.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(other)
	await get_tree().process_frame
	assert_false(_alloc.can_allocate(_nodes[1], other), "blocker blocks everyone")


# ── spawn_blocker (GameRoot path) ────────────────────────────────────────────

func test_spawn_blocker_spawns_with_tiered_board_and_spellbook() -> void:
	var gr := GameRoot.new()
	autofree(gr)
	gr.graph = _graph
	gr.allocation_system = _alloc

	var blocker := gr.spawn_blocker(GameRoot.BlockerSize.MEDIUM, _nodes[2])
	assert_not_null(blocker)
	assert_eq(blocker.get_parent(), _graph.entities_container, "parented under entities_container")
	assert_eq(blocker.entity_tier, 2, "tier = size + 1")
	assert_eq(blocker.core_location, _nodes[2], "core force-allocated")
	assert_eq(_nodes[2].owned_by, blocker, "blocked node owned by the blocker")
	assert_eq(_nodes[2].get_max_hp(), 40.0, "tier-2 board → node HP 40")
	assert_null(blocker.core_class, "no CoreClass")
	assert_not_null(blocker.spellbook, "spellbook is a non-null resource")
	assert_eq(blocker.spellbook.spells.size(), 3, "medium spellbook carries its authored tier (#586 re-tier)")


func test_spawn_blocker_size_to_tier_and_board_mapping() -> void:
	var gr := GameRoot.new()
	autofree(gr)
	gr.graph = _graph
	gr.allocation_system = _alloc

	var small := gr.spawn_blocker(GameRoot.BlockerSize.SMALL, null)
	var large := gr.spawn_blocker(GameRoot.BlockerSize.LARGE, null)
	assert_eq(small.entity_tier, 1, "SMALL → tier 1")
	assert_eq(large.entity_tier, 3, "LARGE → tier 3")
	assert_eq(small.spellbook.spells.size(), 2, "small blocker carries its own loot tier since #586")
	assert_gt(large.spellbook.spells.size(), 0, "large blocker carries spells")


# ── #586: loot-book prune at spawn ───────────────────────────────────────────

func test_spawn_blocker_without_prune_keeps_the_tier_book_whole() -> void:
	# The default (`spell_prune_m == 0.0`) is the pre-#586 behaviour a
	# hand-authored level still gets: the tier's authored contents, entire.
	var gr := GameRoot.new()
	autofree(gr)
	gr.graph = _graph
	gr.allocation_system = _alloc

	var a := gr.spawn_blocker(GameRoot.BlockerSize.MEDIUM, null)
	assert_eq(a.spellbook.spells, _MEDIUM_SPELLBOOK.spells, "un-pruned = the whole authored tier")


func test_prune_leaves_the_authored_resource_untouched() -> void:
	# The prune runs on the `preload`ed tier book, which every blocker of a
	# size shares — it must copy before popping, or one spawn would strip the
	# resource for the whole run. (Entity._ready separately duplicates the
	# book it is handed, so per-entity isolation is not what this guards.)
	var gr := GameRoot.new()
	autofree(gr)
	gr.graph = _graph
	gr.allocation_system = _alloc

	for seed_value in [11, 22, 33, 44]:
		gr.spawn_blocker(GameRoot.BlockerSize.MEDIUM, null, [], seed_value, 1.0)
	assert_eq(_MEDIUM_SPELLBOOK.spells.size(), 3, "the authored resource is left whole")


func test_prune_actually_varies_what_a_tier_offers() -> void:
	var gr := GameRoot.new()
	autofree(gr)
	gr.graph = _graph
	gr.allocation_system = _alloc

	var sizes := {}
	for seed_value in 40:
		var b := gr.spawn_blocker(GameRoot.BlockerSize.MEDIUM, null, [], seed_value, 1.0)
		sizes[b.spellbook.spells.size()] = true
	assert_true(sizes.has(0), "some medium blockers offer nothing at all")
	assert_true(sizes.has(3), "some keep the whole book")


func test_same_prune_seed_spawns_the_same_book_on_every_peer() -> void:
	# Every peer re-runs the level scene, so this roll is reproduced rather
	# than received — procgen hands out the seed for exactly this reason.
	var gr := GameRoot.new()
	autofree(gr)
	gr.graph = _graph
	gr.allocation_system = _alloc

	var a := gr.spawn_blocker(GameRoot.BlockerSize.MEDIUM, null, [], 4242, 1.0)
	var b := gr.spawn_blocker(GameRoot.BlockerSize.MEDIUM, null, [], 4242, 1.0)
	assert_eq(a.spellbook.spells, b.spellbook.spells, "same seed → same book")


# ── #777: the bonus-node footprint and its falloff ───────────────────────────

## A straight chain hanging off `_nodes[2]`, so a blocker cored at `_nodes[2]`
## has somewhere to grow. Returns the new nodes in hop order (hop 1 first).
func _extend_chain(count: int) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	var prev: SkillNode = _nodes[2]
	for i in count:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "F%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_add_edge(prev, sn)
		prev = sn
		out.append(sn)
		_nodes.append(sn)
	await get_tree().process_frame
	return out


func _game_root() -> GameRoot:
	var gr := GameRoot.new()
	autofree(gr)
	gr.graph = _graph
	gr.allocation_system = _alloc
	return gr


func test_spawn_blocker_force_allocates_every_footprint_node() -> void:
	var chain := await _extend_chain(3)
	var blocker := _game_root().spawn_blocker(GameRoot.BlockerSize.MEDIUM, _nodes[2], chain)
	assert_eq(_nodes[2].owned_by, blocker, "the core is still the core")
	assert_eq(blocker.core_location, _nodes[2], "core_location is the CORE, not a footprint node")
	for node in chain:
		assert_eq(node.owned_by, blocker, "footprint node %s is owned" % node.name)


## The acceptance formula, read through the live `node_health` path (#660)
## rather than any stored value: cap = the owner's CON-derived baseline minus
## 5 per hop from the core, over the owned subgraph. The core is at hop 0 and
## keeps its full authored HP — [ProportionalScale] puts the source at scale 0.
func test_footprint_node_health_falls_off_five_per_hop() -> void:
	var chain := await _extend_chain(3)
	_game_root().spawn_blocker(GameRoot.BlockerSize.MEDIUM, _nodes[2], chain)
	await get_tree().process_frame
	var base := _nodes[2].get_max_hp()
	assert_eq(base, 40.0, "tier-2 board → an unmodified node caps at 40")
	for hop in range(1, chain.size() + 1):
		assert_eq(chain[hop - 1].get_max_hp(), base - 5.0 * hop,
				"hop %d caps at base − 5×%d" % [hop, hop])


## The clamp is the footprint bound, not a stat floor (#777 decision 5): a
## small tops out at hop 2 (20 − 10 = 10), so nothing ever reaches zero.
func test_a_small_blockers_deepest_footprint_node_still_has_health() -> void:
	var chain := await _extend_chain(2)
	_game_root().spawn_blocker(GameRoot.BlockerSize.SMALL, _nodes[2], chain)
	await get_tree().process_frame
	assert_eq(_nodes[2].get_max_hp(), 20.0, "tier-1 board → 20 at the core")
	assert_eq(chain[0].get_max_hp(), 15.0, "hop 1")
	assert_eq(chain[1].get_max_hp(), 10.0, "hop 2 — half, never zero")


## An explicit empty footprint is the default, and the aura is granted anyway:
## the grant is what makes a peer rebuild idempotent, and on a lone core it is
## inert because the only node in scope is the source itself.
func test_a_footprintless_blocker_is_todays_blocker_with_an_inert_aura() -> void:
	var blocker := _game_root().spawn_blocker(GameRoot.BlockerSize.MEDIUM, _nodes[2])
	await get_tree().process_frame
	assert_eq(_nodes[2].get_max_hp(), 40.0, "the lone core keeps its full HP")
	var owned := 0
	for sn in _nodes:
		if sn.owned_by == blocker:
			owned += 1
	assert_eq(owned, 1, "one node, exactly as before #777")
	var falloff := 0
	for inst in blocker.get_effects():
		if inst.effect is AuraEffect and inst.effect.display_name == "Dormant Reach":
			falloff += 1
			assert_eq(inst.node_targets().size(), 0, "inert: the source is at scale 0")
	assert_eq(falloff, 1, "granted exactly once")


## Deallocating a footprint node re-derives the aura rather than leaving a
## stale cap behind — the kill-strip cascade is the normal way a Dormant Core
## loses territory, so this is the path players actually take.
func test_losing_a_footprint_node_re_derives_the_remaining_caps() -> void:
	var chain := await _extend_chain(3)
	var blocker := _game_root().spawn_blocker(GameRoot.BlockerSize.MEDIUM, _nodes[2], chain)
	await get_tree().process_frame
	assert_eq(chain[2].get_max_hp(), 25.0, "hop 3 before the cut")
	_alloc.force_deallocate(chain[0])
	await get_tree().process_frame
	# hop 1 is gone, so the outer two are no longer reachable over owned nodes.
	assert_eq(chain[0].owned_by, null, "the cut node is unowned")
	assert_eq(_nodes[2].get_max_hp(), 40.0, "the core is untouched by the cut")

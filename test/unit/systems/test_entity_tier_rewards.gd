extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## #774 retired the tier-scaled XP bonus entirely: `tier_xp_base ×
## entity_tier²` and the `entity_kill_bonus` multiplier are both gone, replaced
## by a per-board `core_kill_xp` ScalarStat (owner, 2026-09-13: "so we could
## author any formula for an innate or core specific stat modifier"). This file
## used to pin tier→XP scaling; it now pins the two facts that replaced it:
## `entity_tier` has NO effect on the kill-XP payout any more (its remaining
## job, the SkillDust loot fraction, is `test_loot_system.gd`'s — #775), and
## `core_kill_xp` is what actually drives the bonus, read live off the STAT so
## a modifier can move it. Per `owner_tunes_agents_test`: `core_kill_xp` is set
## on the hand-built victim board here, never asserted at a shipped `.tres` value.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _loot: LootSystem
var _killer: Entity
var _victim: Entity
var _nodes: Array[SkillNode] = []
var _xp_gained: float = 0.0


func before_each() -> void:
	_xp_gained = 0.0

	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = []

	_tm = TurnManager.new()
	add_child_autofree(_tm)

	_loot = LootSystem.new()
	_loot.turn_manager = _tm
	_loot.xp_per_node_killed = 5.0
	add_child_autofree(_loot)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_killer = autofree(Entity.new())
	_killer.display_name = "Killer"
	_killer.faction = _PLAYER_FACTION
	_killer.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_killer)

	_victim = autofree(Entity.new())
	_victim.display_name = "Victim"
	_victim.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_victim)

	await get_tree().process_frame  # _ready: navigators + health wiring
	_victim.stat_board.core_kill_xp.base_value = 8.0

	_add_node("K0")
	_add_node("V0")
	_add_edge(_nodes[0], _nodes[1])

	_alloc.force_allocate(_killer, _nodes[0])
	_killer.core_location = _nodes[0]
	_alloc.force_allocate(_victim, _nodes[1])
	_victim.core_location = _nodes[1]

	Events.entity_xp_gained.connect(_on_xp_gained)


func after_each() -> void:
	if Events.entity_xp_gained.is_connected(_on_xp_gained):
		Events.entity_xp_gained.disconnect(_on_xp_gained)


func _on_xp_gained(entity: Entity, amount: float) -> void:
	if entity == _killer:
		_xp_gained += amount


func _kill_victim() -> void:
	_tm.current_entity = _killer
	_victim.stat_board.health.set_current(1.0)
	_victim.core_location.take_damage(10000.0, null)


func _add_node(node_name: String) -> void:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = node_name
	_graph.skill_nodes_container.add_child(sn)
	_nodes.append(sn)


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


# ── entity_tier no longer affects the XP payout (#774) ───────────────────────

func test_entity_tier_does_not_change_the_kill_payout() -> void:
	# Footprintless victim (core only): 1 node * 5 + 8 core bonus = 13,
	# regardless of what entity_tier reads.
	_victim.entity_tier = 1
	_kill_victim()
	assert_eq(_xp_gained, 13.0, "1 node * xp_per_node_killed + core_kill_xp")


func test_a_higher_tier_victim_pays_the_same_as_a_lower_one() -> void:
	_victim.entity_tier = 1
	_kill_victim()
	var tier1_gained := _xp_gained

	# Fresh fixture, same board values, tier 3 this time.
	_xp_gained = 0.0
	var victim2: Entity = autofree(Entity.new())
	victim2.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(victim2)
	await get_tree().process_frame
	victim2.stat_board.core_kill_xp.base_value = 8.0
	victim2.entity_tier = 3
	_add_node("V1")
	_add_edge(_nodes[0], _nodes[2])
	_alloc.force_allocate(victim2, _nodes[2])
	victim2.core_location = _nodes[2]

	_tm.current_entity = _killer
	victim2.stat_board.health.set_current(1.0)
	_nodes[2].take_damage(10000.0, null)

	assert_eq(_xp_gained, tier1_gained, "tier no longer sizes the XP bonus — only core_kill_xp does")


# ── core_kill_xp drives the bonus, read live off the stat ───────────────────

func test_core_kill_xp_stat_sizes_the_bonus() -> void:
	_victim.stat_board.core_kill_xp.base_value = 40.0
	_kill_victim()
	assert_eq(_xp_gained, 45.0, "1 node * 5 + 40")


func test_a_modifier_on_core_kill_xp_changes_the_bonus() -> void:
	# The stat is read, not the def — a modifier granted onto it moves the
	# payout through the normal pipeline, no bespoke mechanism.
	var mod := StatModifier.new()
	mod.stat_id = &"core_kill_xp"
	mod.operation = StatModifier.Operation.ADD_BASE
	mod.value = 10.0
	_victim.stat_board.add_modifier(mod)
	_kill_victim()
	assert_eq(_xp_gained, 5.0 + 8.0 + 10.0, "core_kill_xp moved by the modifier, not just its base_value")


func test_ally_kill_pays_no_xp_at_all() -> void:
	# The core bonus rides the same HOSTILE gate as the territory term.
	_killer.faction = _NPC_FACTION
	_kill_victim()
	assert_eq(_xp_gained, 0.0, "an ally kill pays no XP at all, core bonus included")

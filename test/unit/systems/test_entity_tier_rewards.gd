extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## Entity tier rewards (#300): the kill-XP bonus is `tier_xp_base × entity_tier²`
## on top of the territory term, and it rides the same HOSTILE gate. A 1-node
## (core-only) victim pays exactly `territory(10) + tier bonus`; a grown victim
## scales its territory term the same as any NPC and layers the flat tier bonus
## on top. Tracked via `Events.entity_xp_gained` (the amount ASKED FOR, not the
## amount that fit under the pool cap — a fill carries its excess into the next
## level, so the honest number is the grant).

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


## Grows the victim from its 1 core to `total` nodes (core included) by
## chaining fresh nodes off its existing territory and force-allocating them.
func _grow_victim(total: int) -> void:
	var victim_nodes := 1  # the V0 core already owned
	while victim_nodes < total:
		var prev: SkillNode = _nodes.back()
		_add_node("V%d" % _nodes.size())
		_add_edge(prev, _nodes.back())
		_alloc.force_allocate(_victim, _nodes.back())
		victim_nodes += 1


func _add_node(name: String) -> void:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = name
	_graph.skill_nodes_container.add_child(sn)
	_nodes.append(sn)


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


# ── Tier bonus ────────────────────────────────────────────────────────────────

func test_tier_1_victim_pays_20_xp() -> void:
	_victim.entity_tier = 1
	_kill_victim()
	assert_eq(_xp_gained, 20.0, "10 territory (core only) + 10 tier bonus")


func test_tier_2_victim_pays_50_xp() -> void:
	_victim.entity_tier = 2
	_kill_victim()
	assert_eq(_xp_gained, 50.0, "10 territory + 40 tier bonus")


func test_tier_3_victim_pays_100_xp() -> void:
	_victim.entity_tier = 3
	_kill_victim()
	assert_eq(_xp_gained, 100.0, "10 territory + 90 tier bonus")


func test_grown_tier_3_victim_pays_300_xp() -> void:
	# 20 territory nodes + the core = 21 counted → 5 × 21 × 2 = 210 territory,
	# + 90 tier bonus = 300.
	_grow_victim(21)
	_victim.entity_tier = 3
	_kill_victim()
	assert_eq(_xp_gained, 300.0, "210 territory + 90 tier bonus")


func test_tier_bonus_is_paid_once_not_per_node() -> void:
	# A grown tier-1 victim pays the SAME +10 bonus as a core-only tier-1 —
	# the bonus is a flat per-kill term, not a per-node multiplier.
	_grow_victim(5)
	_victim.entity_tier = 1
	_kill_victim()
	# 4 territory + core = 5 counted → 5 × 5 × 2 = 50 territory + 10 = 60.
	assert_eq(_xp_gained, 60.0, "tier bonus stays flat regardless of territory")


func test_tier_xp_base_is_respected_when_overridden() -> void:
	_loot.tier_xp_base = 100.0
	_victim.entity_tier = 1
	_kill_victim()
	assert_eq(_xp_gained, 110.0, "10 territory + 100 × 1²")


func test_ally_kill_pays_no_tier_bonus() -> void:
	# The tier bonus rides the same HOSTILE gate as the territory term.
	_killer.faction = _NPC_FACTION
	_victim.entity_tier = 2
	_kill_victim()
	assert_eq(_xp_gained, 0.0, "an ally kill pays no XP at all, bonus included")

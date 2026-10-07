extends GutTest

## Hoard (Greed × kill XP): every Greed stack still on a node when an attack
## removes it raises what that node pays its killer by the def's
## `hoard_increase_per_stack` percent. The payout reads the `bounty` stat with
## LootSystem's per-node rate as an overlay `base_add`; Greed plants an
## `INCREASE` on `bounty`. Greed on the entity host folds under every node's
## read, so it scales the whole kill — the core bonus included.
##
## Rates are set on the test's own LootSystem and boards, never read from a
## shipped `.tres`; the per-stack percent is read off the def it tests.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _DUST_SCENE := preload("res://skill_node/addons/defs/skill_dust_addon.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _GREED := preload("res://effects/status/greed.tres")

const _PER_NODE := 5.0
const _CORE_BONUS := 7.0

var _graph: Graph
var _loot: LootSystem
var _alloc: AllocationSystem
var _battle: BattleSystem
var _tm: TurnManager
var _victim: Entity
var _killer: Entity
## [0] killer core, [1] victim core, [2..4] victim nodes A, B, C.
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = []
	for i in 5:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)

	_tm = TurnManager.new()
	add_child_autofree(_tm)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_battle = BattleSystem.new()
	_battle.allocation_system = _alloc
	_battle.graph = _graph
	add_child_autofree(_battle)
	_loot = LootSystem.new()
	_loot.skill_dust_scene = _DUST_SCENE
	_loot.turn_manager = _tm
	_loot.battle_system = _battle
	_loot.xp_per_node_killed = _PER_NODE
	add_child_autofree(_loot)

	_killer = autofree(Entity.new())
	_killer.faction = _PLAYER_FACTION  # HOSTILE to the victim's npc faction
	_killer.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_killer)
	_victim = autofree(Entity.new())
	_victim.faction = _NPC_FACTION
	_victim.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_victim)
	await get_tree().process_frame
	_victim.stat_board.core_kill_xp.base_value = _CORE_BONUS

	_alloc.force_allocate(_killer, _nodes[0])
	_killer.core_location = _nodes[0]
	for i in range(1, 5):
		_alloc.force_allocate(_victim, _nodes[i])
	_victim.core_location = _nodes[1]
	_tm.start_turn(_killer)


## The percent one stack plants, as a factor step (10% → 0.1).
func _step() -> float:
	return float(_GREED.get(&"hoard_increase_per_stack")) / 100.0


func _greed(n: SkillNode, stacks: float) -> void:
	n.get_combat().apply_status(_GREED, stacks)


## XP is a growing pool: reconstruct the total across level-ups (each level
## consumed its cap — 5, 10, 15, … per the xp def's growth_flat).
func _gained(run: Callable) -> float:
	var before := _killer.stat_board.xp.current
	var lvl_before := _killer.level
	run.call()
	var consumed := 0.0
	for l in range(lvl_before, _killer.level):
		consumed += 5.0 * float(l)
	return consumed + _killer.stat_board.xp.current - before


func _kill() -> float:
	return _gained(func() -> void: _victim.die())


# --- 1 ------------------------------------------------------------------------

func test_a_node_with_two_greed_pays_its_hoard_on_the_kill() -> void:
	_greed(_nodes[2], 2.0)
	var plain := (_PER_NODE + _CORE_BONUS) + 2.0 * _PER_NODE
	assert_almost_eq(_kill(), plain + _PER_NODE * (1.0 + 2.0 * _step()), 0.001,
			"A pays ×(1 + 2·step); core, B and C pay the plain rate")


# --- 2 ------------------------------------------------------------------------

func test_each_node_pays_its_own_stacks() -> void:
	_greed(_nodes[2], 1.0)
	_greed(_nodes[3], 3.0)
	var expected := (_PER_NODE + _CORE_BONUS) \
			+ _PER_NODE * (1.0 + 1.0 * _step()) \
			+ _PER_NODE * (1.0 + 3.0 * _step()) \
			+ _PER_NODE
	assert_almost_eq(_kill(), expected, 0.001, "×1.1, ×1.3, and C at the plain rate")


# --- 3 ------------------------------------------------------------------------

func test_entity_greed_scales_the_whole_kill_and_the_core_bonus() -> void:
	_victim.get_combat().apply_status(_GREED, 2.0)
	var f := 1.0 + 2.0 * _step()
	assert_almost_eq(_kill(), ((_PER_NODE + _CORE_BONUS) + 3.0 * _PER_NODE) * f, 0.001,
			"every removed node and the core bonus pay ×(1 + 2·step)")


# --- 4 ------------------------------------------------------------------------

func test_a_trickle_removal_pays_its_hoard() -> void:
	_greed(_nodes[2], 1.0)
	var got := _gained(func() -> void: _battle.cascade_started.emit([[_nodes[2]]], _victim))
	assert_false(_victim.is_dead, "a trickle, not a kill")
	assert_almost_eq(got, _PER_NODE * (1.0 + _step()), 0.001, "one node at ×(1 + step)")


# --- 5 ------------------------------------------------------------------------

func test_an_ally_kill_pays_nothing_even_with_greed() -> void:
	_killer.faction = _NPC_FACTION
	_greed(_nodes[2], 2.0)
	assert_almost_eq(_kill(), 0.0, 0.001, "no XP for an ally kill")


func test_without_greed_the_kill_pays_the_plain_rate() -> void:
	assert_almost_eq(_kill(), (_PER_NODE + _CORE_BONUS) + 3.0 * _PER_NODE, 0.001,
			"characterization: the pre-Hoard arithmetic at zero Greed")


# --- 6 ------------------------------------------------------------------------

func test_greed_spent_to_zero_leaves_no_bounty_behind() -> void:
	_greed(_nodes[2], 2.0)
	var o := ModifierBins.new()
	o.base_add = _PER_NODE
	var overlays: Array[ModifierBins] = [o]
	assert_almost_eq(float(_nodes[2].get_local_value_with(&"bounty", overlays)),
			_PER_NODE * (1.0 + 2.0 * _step()), 0.001, "two stacks raise the bounty")
	var combat := _nodes[2].get_combat()
	combat.adjust_power(_GREED, -1.0)
	assert_almost_eq(float(_nodes[2].get_local_value_with(&"bounty", overlays)),
			_PER_NODE * (1.0 + _step()), 0.001, "a spend follows the stack count")
	combat.adjust_power(_GREED, -1.0)
	assert_eq(combat.get_status_power(&"greed"), 0.0, "greed spent")
	assert_almost_eq(float(_nodes[2].get_local_value_with(&"bounty", overlays)),
			_PER_NODE, 0.001, "no bounty modifier left behind")

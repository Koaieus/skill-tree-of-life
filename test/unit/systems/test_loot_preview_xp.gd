extends GutTest

## LootSystem.preview_kill_xp (#538). A read-only, non-mutating preview of what
## `_award_kill_xp` would pay a killer for a given removal — used by the AI
## scorer to rank candidate attacks by XP without actually committing them.
##
## Pinned signature (ORCHESTRATOR PIN on #538 — the issue's premise assumed
## `AttackOutcome` already carries a deallocation/killed-entity set; it does
## not, so the preview takes explicit parameters instead):
##
##   preview_kill_xp(killer, victim, removed_node_count, kills_entity) -> float
##
## `_award_kill_xp` and `preview_kill_xp` share one extracted formula
## (`_kill_xp_total`) — this file pins the two against each other rather than
## re-deriving a second copy of the arithmetic (`.claude/rules/no-parallel-mirrors`).

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

const _PER_NODE := 5.0
const _BONUS := 2.0
const _TIER_BASE := 10.0

var _graph: Graph
var _loot: LootSystem
var _alloc: AllocationSystem
var _battle: BattleSystem
var _tm: TurnManager
var _victim: Entity
var _killer: Entity
var _nodes: Array[SkillNode]

# Scratch state for test_calling_it_mid_cascade_matches_calling_it_before.
# Instance members, not lambda-captured locals: GDScript lambdas capture
# outer locals BY VALUE at creation, so a `var mid_value := 0.0` mutated
# inside a connected lambda never reaches the assertion below it.
var _mid_cascade_value: float = 0.0
var _saw_cascade: bool = false


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = []
	# Chain: K (killer core) – V (victim core) – A – B – C – D. Depleting A (a
	# cut vertex) islands B/C/D — same fixture shape as test_kill_xp_ledger.gd,
	# reused here so the cascade-sum pin (test 1 below) exercises a real
	# multi-node cascade, not a synthetic single-node kill.
	for i in 6:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	for i in 5:
		var e := _EDGE_SCENE.instantiate() as Edge
		e.from = _nodes[i]
		e.to = _nodes[i + 1]
		_graph.edges_container.add_child(e)

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
	_loot.turn_manager = _tm
	_loot.battle_system = _battle
	_loot.xp_per_node_killed = _PER_NODE
	_loot.entity_kill_bonus = _BONUS
	_loot.tier_xp_base = _TIER_BASE
	add_child_autofree(_loot)

	_killer = autofree(Entity.new())
	_killer.faction = _PLAYER_FACTION
	_killer.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_killer)

	_victim = autofree(Entity.new())
	_victim.faction = _NPC_FACTION
	_victim.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_victim.core_class = _BALANCED
	_victim.entity_tier = 2  # tier bonus = 10 * 2^2 = 40
	_graph.add_child(_victim)
	await get_tree().process_frame

	_alloc.force_allocate(_killer, _nodes[0])
	_killer.core_location = _nodes[0]
	for i in range(1, 6):
		_alloc.force_allocate(_victim, _nodes[i])
	_victim.core_location = _nodes[1]
	_tm.current_entity = _killer


func _xp_gained(before: float, lvl_before: int) -> float:
	var consumed := 0.0
	for l in range(lvl_before, _killer.level):
		consumed += 5.0 * float(l)
	return consumed + _killer.stat_board.xp.current - before


# ── 1: pinned against a real cascade (trickle + kill bonus + tier bonus) ──────

func test_preview_matches_a_whole_cascades_real_payout() -> void:
	# Whole territory (4 non-core nodes) + core = 5 nodes counted → kill-total
	# 5 * 5 * 2 = 50, + tier bonus 40 = 90.
	var expected_preview := _loot.preview_kill_xp(_killer, _victim, 4, true)
	assert_eq(expected_preview, 90.0, "5*(4+1)*2 + 10*2^2")

	var before := _killer.stat_board.xp.current
	var lvl_before := _killer.level
	_victim.stat_board.health.set_current(2.0)  # dies mid-cascade
	_nodes[2].take_damage(10000.0, null)  # deplete A, the cut vertex
	assert_true(_victim.is_dead, "chip damage kills the core mid-cascade")

	var real_payout := _xp_gained(before, lvl_before)
	assert_eq(real_payout, expected_preview,
			"preview equals trickle + kill bonus + tier bonus summed across the whole cascade")


func _capture_mid_cascade_preview(_layers: Array, defender: Entity) -> void:
	if defender == _victim:
		_saw_cascade = true
		_mid_cascade_value = _loot.preview_kill_xp(_killer, _victim, 4, true)


func test_calling_it_mid_cascade_matches_calling_it_before() -> void:
	var before_value := _loot.preview_kill_xp(_killer, _victim, 4, true)
	_battle.cascade_started.connect(_capture_mid_cascade_preview)

	_victim.stat_board.health.set_current(2.0)
	_nodes[2].take_damage(10000.0, null)

	_battle.cascade_started.disconnect(_capture_mid_cascade_preview)
	assert_true(_saw_cascade, "the cascade actually ran mid-test")
	assert_eq(_mid_cascade_value, before_value, "same number whenever in the cascade it's asked")


func test_calling_it_twice_returns_the_same_number() -> void:
	var a := _loot.preview_kill_xp(_killer, _victim, 3, true)
	var b := _loot.preview_kill_xp(_killer, _victim, 3, true)
	assert_eq(a, b)


# ── 2/3: trickle-only vs. a kill ───────────────────────────────────────────────

func test_removals_with_no_kill_preview_trickle_only() -> void:
	var preview := _loot.preview_kill_xp(_killer, _victim, 3, false)
	assert_eq(preview, 3.0 * _PER_NODE, "trickle only, no core/bonus/tier")


func test_a_kill_previews_trickle_plus_core_plus_bonus_plus_tier() -> void:
	var preview := _loot.preview_kill_xp(_killer, _victim, 2, true)
	# (2 territory + 1 core) * PER_NODE * BONUS + tier
	assert_eq(preview, (2.0 + 1.0) * _PER_NODE * _BONUS + _TIER_BASE * 4.0)


# ── 4: gates ─────────────────────────────────────────────────────────────────

func test_ally_kill_previews_zero() -> void:
	_victim.faction = _PLAYER_FACTION  # same faction as killer now
	var preview := _loot.preview_kill_xp(_killer, _victim, 4, true)
	assert_eq(preview, 0.0)


func test_self_kill_previews_zero() -> void:
	var preview := _loot.preview_kill_xp(_killer, _killer, 4, true)
	assert_eq(preview, 0.0)


func test_award_xp_on_kill_false_previews_zero() -> void:
	_loot.award_xp_on_kill = false
	var preview := _loot.preview_kill_xp(_killer, _victim, 4, true)
	assert_eq(preview, 0.0)


func test_null_killer_previews_zero() -> void:
	assert_eq(_loot.preview_kill_xp(null, _victim, 4, true), 0.0)


func test_dead_killer_previews_zero() -> void:
	_killer.is_dead = true
	assert_eq(_loot.preview_kill_xp(_killer, _victim, 4, true), 0.0)


# ── 5: non-mutating ──────────────────────────────────────────────────────────

var _xp_events_seen: int = 0


func _count_xp_event(_e: Entity, _amount: float) -> void:
	_xp_events_seen += 1


func test_leaves_world_fingerprint_unchanged_and_emits_nothing() -> void:
	Events.entity_xp_gained.connect(_count_xp_event)

	var before := WorldFingerprint.compute(_graph)
	_loot.preview_kill_xp(_killer, _victim, 4, true)
	_loot.preview_kill_xp(_killer, _victim, 0, false)
	var after := WorldFingerprint.compute(_graph)

	Events.entity_xp_gained.disconnect(_count_xp_event)
	assert_eq(after, before, "no world mutation from a preview call")
	assert_eq(_xp_events_seen, 0, "no XP grant signal — preview never touches the pool")

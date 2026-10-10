@tool
extends GutTest

## Staking economy on the channel model: raise a node's cap with a stake
## channel, fill it with allocate, lower it with an extract channel.
## Headless-only (no UI). The channel mechanics themselves (ticks, leash,
## cancel, signals) live in test_stake_channel.gd; this file pins the economy.
##
## Model: `stake_level` is the cap N, `allocation_level` the fill M — a node
## reads M/N. stake: SP current→staked at initiation, cap+1 after K owner
## turns. allocate (refill): 1 SP, fill+1 — with NO first-allocation side
## effects. extract: 1 DP at initiation; after K turns cap-1, staked SP →
## wounded (+ the displaced fill's SP → current when the node was full).
## Wounds and dealloc damage scale with the fill (economy preservation). The
## ceiling is the node-local `stake_ceiling` stat. Reach is Euclidean px:
## nodes sit 0.6 × reach apart along the chain.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")

const REACH := 250.0

var _graph: Graph
var _alloc: AllocationSystem
var _player: Entity
var _nodes: Array[SkillNode]


## Implements nothing — a hook-free effect grants only its (empty) modifier
## set, so "no re-grant" is observable purely through the instance count.
class InertEffect extends Effect:
	pass


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = []
	for i in 4:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.add_skill_node(sn)  # emits node_added — the Navigator mirrors it (.claude/rules/graph.md)
		_nodes.append(sn)
	for i in 3:
		_add_edge(_nodes[i], _nodes[i + 1])

	for i in _nodes.size():
		_nodes[i].position = Vector2(0.6 * REACH * i, 0)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	_alloc.stake_reach_px = REACH
	add_child_autofree(_alloc)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	# Flat board: formula test arranges its own stat inputs, tuned CON must not ride in.
	_player.stat_board = TestBoards.flat_entity_board()
	_graph.add_child(_player)
	await get_tree().process_frame

	for n in _nodes:
		_alloc.force_allocate(_player, n)
	_player.core_location = _nodes[0]


func after_each() -> void:
	_graph = null
	_alloc = null
	_player = null
	_nodes = []


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	_graph.add_edge(a, b)  # emits edge_added — the Navigator mirrors it (.claude/rules/graph.md)


## Stake [param n] and let the channel land: cap +1.
func _stake_landed(n: SkillNode) -> void:
	assert_true(_alloc.stake(n, _player), "stake %s" % n.name)
	for i in _alloc.stake_channel_turns:
		_alloc.advance_channels(_player)


## Extract [param n] and let the channel land: cap -1.
func _extract_landed(n: SkillNode) -> void:
	assert_true(_alloc.extract(n, _player), "extract %s" % n.name)
	for i in _alloc.extract_channel_turns:
		_alloc.advance_channels(_player)


func _sp() -> SkillPointStat:
	return _player.stat_board.skill_points


func _ap() -> PoolStat:
	return _player.stat_board.action_points


func _dp() -> PoolStat:
	return _player.stat_board.deallocation_points


func _move_core_to(i: int) -> void:
	_player.stat_board.movement_points.base_value = 9.0
	_player.stat_board.movement_points.restore_to_full()
	var cur := _nodes.find(_player.core_location)
	while cur >= 0 and cur < i:
		assert_true(_alloc.move_core(_player, _nodes[cur + 1]), "hop %d -> %d" % [cur, cur + 1])
		cur += 1


func _battle_system() -> BattleSystem:
	var bs := BattleSystem.new()
	bs.allocation_system = _alloc
	bs.graph = _graph
	add_child_autofree(bs)
	return bs


# --- 1/2/3. allocate as the fill verb -----------------------------------------

func test_refill_increments_fill_and_spends_sp() -> void:
	var b := _nodes[1]
	assert_eq(b.allocation_level, 1, "force_allocated nodes start 1/1")
	var used_before: int = _sp().used
	_stake_landed(b)
	assert_eq(b.allocation_level, 1, "1/2 after stake")
	assert_true(_alloc.allocate(b, _player), "refill from 1/2 succeeds")
	assert_eq(b.allocation_level, 2, "fill incremented to 2/2")
	assert_eq(_sp().used, used_before + 1, "the refill spends exactly 1 SP")


func test_refill_skips_first_allocation_side_effects() -> void:
	var b := _nodes[1]
	# A node-local-to-entity modifier + a granted effect, both live before the
	# refill. A refill that re-ran the first-allocation path would double them.
	var m := StatModifier.new()
	m.stat_id = &"strength"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = 5.0
	b.add_entity_modifier(m)
	_player.grant_effect(InertEffect.new(), b)
	assert_eq(int(_player.stat_board.get_stat(&"strength").get_value()), 15, "modifier live")
	assert_eq(_player.get_effects().size(), 1, "effect granted")

	watch_signals(_alloc)
	var mirrored_before := _player.navigator.get_mirrored_nodes().size()
	_stake_landed(b)
	assert_true(_alloc.allocate(b, _player), "refill succeeds")

	assert_signal_not_emitted(_alloc, "allocated", "refill must not re-emit allocated")
	assert_eq(_player.navigator.get_mirrored_nodes().size(), mirrored_before,
			"refill must not mirror_add (ownership unchanged)")
	# #376's local-scale mutator runs on every allocation_level change — a
	# refill is one, so the +5 STR mod scales ×ladder(2)/ladder(1) = ×2 → +10.
	# The single-grant invariant this test guards (no re-apply, no re-grant)
	# is still intact: the modifier is applied once (its value changed, it
	# wasn't re-added) and the effect is granted once. Pre-#376 the value stayed
	# +5 because the mutator was a stub; the new contract scales it.
	assert_eq(int(_player.stat_board.get_stat(&"strength").get_value()), 20,
			"refill does not re-apply the node's entity modifiers (the +5 scales to +10 per #376)")
	assert_eq(_player.get_effects().size(), 1, "refill must not re-grant the node's effects")


func test_allocate_at_full_fill_fails() -> void:
	var b := _nodes[1]
	_stake_landed(b)
	_alloc.allocate(b, _player)
	assert_eq(b.allocation_level, b.stake_level, "2/2")
	assert_false(_alloc.can_allocate(b, _player), "full node is not allocatable")
	assert_false(_alloc.allocate(b, _player), "allocate at fill == cap fails")


# --- 4/5/6. stake -------------------------------------------------------------

func test_stake_raises_cap_and_moves_sp_without_ap() -> void:
	var a := _nodes[0]
	var ap := int(_ap().current)
	_stake_landed(a)
	assert_eq(a.stake_level, 2, "cap raised by 1")
	assert_eq(_sp().current, 2.0, "1 SP current -> staked")
	assert_eq(_sp().staked, 1, "the SP lands in the staked bucket")
	assert_eq(int(_ap().current), ap, "no AP")


func test_stake_gated_by_euclidean_reach() -> void:
	var d := _nodes[3]
	assert_false(_alloc.can_stake(d, _player), "core at A, D is 1.8 reach away")
	_move_core_to(1)
	assert_false(_alloc.can_stake(d, _player), "core at B, D is 1.2 reach away")
	_move_core_to(2)
	assert_true(_alloc.can_stake(d, _player), "core at C, D is 0.6 reach away")
	assert_true(_alloc.stake(d, _player), "stake succeeds within reach")
	_move_core_to(3)
	assert_true(_alloc.can_stake(d, _player), "the core itself is distance 0")
	assert_true(_alloc.stake(d, _player), "stake succeeds at distance 0")


func test_stake_fails_on_budget_shortfall_and_ceiling() -> void:
	var a := _nodes[0]
	_sp().set_current(0.0)
	assert_false(_alloc.can_stake(a, _player), "0 SP blocks stake")
	assert_false(_alloc.stake(a, _player))
	_sp().set_current(3.0)
	a.stake_level = a.stake_ceiling
	assert_false(_alloc.can_stake(a, _player), "at the ceiling blocks stake")
	assert_false(_alloc.stake(a, _player))
	assert_eq(a.stake_level, a.stake_ceiling, "cap unchanged")


# --- 7/8/9. extract -----------------------------------------------------------

func test_extract_from_partial_refunds_staked_sp() -> void:
	var b := _nodes[1]
	_stake_landed(b)
	assert_eq(b.stake_level, 2)
	assert_eq(b.allocation_level, 1, "1/2 before extract")
	_extract_landed(b)
	assert_eq(b.stake_level, 1, "cap drops to 1/1")
	assert_eq(b.allocation_level, 1, "fill is untouched when not full")
	assert_eq(int(_dp().current), 2, "1 DP deducted")
	assert_eq(_sp().staked, 0, "staked SP leaves the reservation")
	assert_eq(_sp().wounded, 1, "staked -> wounded: extract is an exchange, not a refund")
	assert_eq(_sp().current, 2.0, "current keeps the stake's spend")


func test_extract_from_full_refunds_staked_and_displaced_fill() -> void:
	var b := _nodes[1]
	_stake_landed(b)
	_alloc.allocate(b, _player)
	assert_eq(b.allocation_level, 2, "2/2 before extract")
	_extract_landed(b)
	assert_eq(b.stake_level, 1, "cap drops to 1/1")
	assert_eq(b.allocation_level, 1, "the fill steps down with the cap")
	assert_eq(_sp().staked, 0)
	assert_eq(_sp().wounded, 1, "the staked SP is wounded")
	# current: 3 (baseline) - 1 (stake) - 1 (refill) + 1 (displaced fill refund)
	assert_eq(_sp().current, 2.0, "only the displaced fill SP is refunded")
	assert_eq(_sp().used, 4, "only the surviving fill's SP stays used")


func test_extract_with_no_staked_sp_is_a_noop() -> void:
	# A cap-2 node authored directly (no SP ever staked) — extract has nothing
	# to reclaim, so it must fail without touching anything.
	var b := _nodes[1]
	b.stake_level = 2
	assert_eq(_sp().staked, 0)
	assert_false(_alloc.can_extract(b, _player), "staked == 0 blocks extract")
	assert_false(_alloc.extract(b, _player))
	assert_eq(b.stake_level, 2, "cap untouched")
	assert_eq(b.allocation_level, 1, "fill untouched")
	assert_eq(int(_dp().current), 3, "no DP spent")
	assert_eq(_sp().current, 3.0, "no SP moved")


func test_extract_from_cap_one_is_a_deallocate_not_an_extract() -> void:
	var a := _nodes[0]
	assert_false(_alloc.can_extract(a, _player), "a 1/1 node has no cap tier to drop")
	assert_false(_alloc.extract(a, _player))


# --- 10. voluntary deallocate of a staked node --------------------------------

func test_voluntary_deallocate_of_2_2_refunds_full_fill_keeps_cap() -> void:
	var d := _nodes[3]
	_move_core_to(2)
	_stake_landed(d)
	assert_true(_alloc.allocate(d, _player))
	assert_eq(d.allocation_level, 2)
	assert_true(_alloc.deallocate(d, _player), "leaf 2/2 deallocates without islanding")
	assert_null(d.owned_by, "node unowned")
	assert_eq(d.allocation_level, 0, "fill emptied")
	assert_eq(d.stake_level, 2, "cap survives the loss — the staked reservation stays")
	# current: 3 - 1 (stake) - 1 (refill) + 2 (refund)
	assert_eq(_sp().current, 3.0, "both filled SP refunded to current")
	assert_eq(_sp().staked, 1, "the staked SP stays in its reservation")
	assert_eq(_sp().used, 3, "used drops by the refunded fill")


# --- 11/12. battle cascade scales with the fill -------------------------------

func test_cascade_on_2_2_emits_two_wounds_and_double_dealloc_damage() -> void:
	var d := _nodes[3]
	_move_core_to(2)
	_stake_landed(d)
	_alloc.allocate(d, _player)
	var bs := _battle_system()
	bs._on_node_depleted(d)
	assert_eq(_sp().wounded, 2, "a 2/2 node costs 2 wounds")
	assert_eq(_sp().used, 3, "the two filled SP moved used -> wounded")
	assert_almost_eq(float(_player.stat_board.health.current), 8.0, 0.001,
			"2x dealloc_damage (2 x 1.0) off entity HP")


func test_cascade_on_never_staked_node_pays_todays_costs() -> void:
	var d := _nodes[3]
	assert_eq(d.stake_level, 1, "never staked")
	var bs := _battle_system()
	bs._on_node_depleted(d)
	assert_eq(_sp().wounded, 1, "1/1 still costs exactly 1 wound")
	assert_almost_eq(float(_player.stat_board.health.current), 9.0, 0.001,
			"1x dealloc_damage — nothing regressed for the baseline case")

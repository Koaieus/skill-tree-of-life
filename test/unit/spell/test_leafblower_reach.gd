extends GutTest

## Leafblower's downhill walk, on a contested board shaped like the real thing:
## a red 5-hub with chains hanging off it, blue interpenetrating.
##
## Pins the two properties that make the spell legible:
##   1. degree is measured inside each node's OWN territory, so an enemy node
##      adjacent to the walk doesn't disguise a leaf as a hub;
##   2. a self-loop counts +2, so fortifying a node above the incoming node's
##      degree turns the flow away — and takes everything behind it off the
##      table with it.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const LEAFBLOWER := preload("res://attack/spell/defs/leafblower.tres")

# Red 0..10, blue 11 (the caster's node) + 12,13 (wedged against red's leaf 6).
#
#            12  13                  (blue)
#              \ /
#       1 ————— 6                    A: deg 2 → leaf 6
#      /
#  11-0 ——— 2 ——— 7                  B: deg 2 → leaf 7   ← "4th of top row"
#     |\
#     | 3 ——— 8, 9, 10               C: deg 4 → leaves   ← "2nd skillnode"
#     |
#     4, 5                           bare leaves off the hub
const ADJ := [
	[0, 1], [0, 2], [0, 3], [0, 4], [0, 5],
	[11, 0],
	[1, 6], [6, 12], [6, 13],
	[2, 7],
	[3, 8], [3, 9], [3, 10],
]

const HUB := 0
const A := 1
const B := 2       # "4th of the top row" — baseline territory degree 2
const C := 3       # "2nd skillnode" — baseline territory degree 4
const CASTER := 11
const RED := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
const BLUE := [11, 12, 13]
const ALL_LEAVES := [4, 5, 6, 7, 8, 9, 10]

var _h: SpellTestHelper
var _graph: Graph
var _red: Entity
var _blue: Entity
var _n: Array[SkillNode]


func before_each() -> void:
	_h = H.new()
	_graph = _h.make_graph(ADJ, self)
	_blue = _h.make_entity(_graph, "Blue", Color.BLUE)
	_red = _h.make_entity(_graph, "Red", Color.RED)
	_h.give_big_hp(_red)
	_h.assign_owner(_graph, _red, RED)
	_h.assign_owner(_graph, _blue, BLUE)
	_n = _graph.get_skill_nodes()


## Adds `count` self-loops to node `idx`. Goes through `Graph.add_edge` so the
## edge lands in `edges_container` and the adjacency index sees it.
func _fortify(idx: int, count: int) -> void:
	for _i in count:
		_graph.add_edge(_n[idx], _n[idx])


func _cast() -> Dictionary:
	var outcome := SpellResolver.resolve(
			LEAFBLOWER, _n[HUB], _n[CASTER], _blue, _graph)
	var hit := {}
	for ev in outcome.timeline:
		hit[ev.target] = true
	return hit


func _assert_hit(hit: Dictionary, idx: int, why: String) -> void:
	assert_true(hit.has(_n[idx]), "N%d should be hit — %s" % [idx, why])


func _assert_missed(hit: Dictionary, idx: int, why: String) -> void:
	assert_false(hit.has(_n[idx]), "N%d should NOT be hit — %s" % [idx, why])


# ── Baseline ───────────────────────────────────────────────────────────────

func test_hub_territory_degree_is_5_though_graph_degree_is_6() -> void:
	assert_eq(_n[HUB].get_entity_degree(_graph), 5, "5 red neighbours")
	assert_eq(_n[HUB].get_graph_degree(_graph), 6, "…plus the blue caster's edge")


func test_reaches_every_leaf_of_the_defender() -> void:
	var hit := _cast()
	for idx in ALL_LEAVES:
		_assert_hit(hit, idx, "downhill from the hub, nothing fortified")


func test_leaf_wedged_between_enemies_is_still_a_leaf() -> void:
	# N6 touches two blue nodes, so its graph degree is 3 — a downhill walk on
	# graph degree would refuse to step into it from N1 (degree 2).
	assert_eq(_n[6].get_graph_degree(_graph), 3)
	assert_eq(_n[6].get_entity_degree(_graph), 1, "only N1 is red's")
	_assert_hit(_cast(), 6, "territory degree 1 ≤ N1's 2")


func test_blue_nodes_are_never_hit() -> void:
	var hit := _cast()
	for idx in [12, 13]:
		_assert_missed(hit, idx, "caster's own ally — OwnerFilter(ENEMY)")


# ── Self-loops raise degree and turn the flow away ─────────────────────────

func test_two_self_loops_on_a_degree_2_node_block_it() -> void:
	# "its baseline degree is 2, 2 loops would increase to 6, main target has 5"
	assert_eq(_n[B].get_entity_degree(_graph), 2, "baseline")
	_fortify(B, 2)
	assert_eq(_n[B].get_entity_degree(_graph), 6, "2 loops → +4")

	var hit := _cast()
	_assert_missed(hit, B, "6 > the hub's 5, so the walk won't step in")
	_assert_missed(hit, 7, "its leaf sits behind the blocked node")
	_assert_hit(hit, 6, "a sibling branch is unaffected")
	_assert_hit(hit, 8, "a sibling branch is unaffected")


func test_one_self_loop_mid_chain_shields_the_leaf_behind_it() -> void:
	assert_eq(_n[C].get_entity_degree(_graph), 4, "baseline")
	_fortify(C, 1)
	assert_eq(_n[C].get_entity_degree(_graph), 6, "1 loop → +2")

	var hit := _cast()
	_assert_missed(hit, C, "6 > the hub's 5")
	for idx in [8, 9, 10]:
		_assert_missed(hit, idx, "reachable only through the fortified node")
	_assert_hit(hit, 6, "a sibling branch is unaffected")
	_assert_hit(hit, 7, "a sibling branch is unaffected")


func test_a_self_loop_that_stays_under_the_threshold_does_not_block() -> void:
	# One loop on B: 2 → 4, still ≤ the hub's 5. The knob has to have a
	# threshold, not just "any fortification stops it".
	_fortify(B, 1)
	assert_eq(_n[B].get_entity_degree(_graph), 4)
	var hit := _cast()
	_assert_hit(hit, B, "4 ≤ 5")
	_assert_hit(hit, 7, "so its leaf is still reachable")

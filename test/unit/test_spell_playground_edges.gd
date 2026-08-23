extends GutTest

## The spell playground's world is SCENE-AUTHORED — topology, ownership and
## shape. These assertions are what stops it being quietly lost in a future
## scene edit, and what pins the STRUCTURE the board is authored for.
##
## It used to be a 4×4 cardinal grid built at `_ready` by `_build_grid_edges()`,
## which bailed on `if not graph.get_edges().is_empty(): return` — so authoring
## any single Edge into the scene silently suppressed all 27 generated ones. The
## generator is gone. The grid went with it: every interior node was degree-4, so
## nothing that reads topology (min_degree gating, degree-2 chain walks,
## convergence at a junction) had anything to discriminate.

const _PANEL := preload("res://addons/spell_playground/playground_panel.tscn")

var _panel: Node
var _graph: Graph


func before_each() -> void:
	_panel = _PANEL.instantiate()
	add_child_autofree(_panel)
	await get_tree().process_frame
	await get_tree().process_frame
	_graph = _panel.find_child("Graph", true, false) as Graph
	assert_not_null(_graph, "fixture: the panel must carry a Graph")


func test_scene_authors_the_full_topology() -> void:
	assert_eq(_graph.get_edges().size(), 22, "authored edge count drifted from the scene")
	assert_eq(_graph.get_node("Nodes").get_child_count(), 20,
			"4 caster nodes + 16 defender nodes")


func test_every_authored_edge_resolves_both_endpoints() -> void:
	for e in _graph.get_edges():
		assert_not_null(e.from, "%s has an unresolved `from` NodePath" % e.name)
		assert_not_null(e.to, "%s has an unresolved `to` NodePath" % e.name)


## `self_loops` is a DERIVED runtime index that the editor serializes anyway
## (audit finding C7). A save had once baked `[null, NodePath(...)]` onto the
## carrier — one real entry plus a null — which makes `self_loop_count` report 2
## for a single loop, and `GraphMirror.get_degree` adds `2 * self_loop_count`, so
## the node's degree came out +2 too high while `Graph._ensure_topology` counted
## it right. Two disagreeing degree answers feed spell `min_degree` gating.
func test_the_one_self_loop_counts_once() -> void:
	var hub := _graph.get_node("Nodes/d_hub") as SkillNode
	assert_eq(hub.self_loop_count, 1,
		"a null entry baked into the exported `self_loops` array inflates this")
	for sl in hub.self_loops:
		assert_not_null(sl, "no null may sit in the self_loops index")


## The degree the gameplay rules read must agree with the topology the scene
## authors — this is the assertion that would have caught the baked null.
func test_degree_agrees_with_the_authored_topology() -> void:
	var hub := _graph.get_node("Nodes/d_hub") as SkillNode
	# d_entry, d_gate, d_loop_a, d_loop_c, d_chain1 = 5 real edges. A self-loop
	# counts +2 (see .claude/rules/degree.md), so 5 + 2 = 7.
	assert_eq(hub.get_graph_degree(_graph), 7,
		"5 real edges (+1 each) plus one self-loop (+2)")


## The four-in-a-row of degree-2 nodes the old grid could not express — Trail
## Blazer accumulates through exactly this and detonates at the first junction.
func test_the_chain_is_four_degree_two_nodes_ending_in_a_leaf() -> void:
	for name_ in ["d_chain1", "d_chain2", "d_chain3", "d_chain4"]:
		var sn := _graph.get_node("Nodes/%s" % name_) as SkillNode
		assert_eq(sn.get_graph_degree(_graph), 2, "%s must be a link, not a junction" % name_)
	assert_eq((_graph.get_node("Nodes/d_tip") as SkillNode).get_graph_degree(_graph), 1,
			"the chain ends in a leaf")


## Two disjoint 3-hop paths out of the hub that re-converge on one node. Wave
## reduction ([IncidentReducer], Resonator) needs simultaneous arrival to exist
## at all, and a cardinal mesh converges everywhere, which isolates nothing.
func test_the_loop_reconverges_on_one_node() -> void:
	var join := _graph.get_node("Nodes/d_join") as SkillNode
	var names: Array[String] = []
	for nb in _graph.get_neighbours(join):
		names.append(nb.name)
	names.sort()
	assert_eq(names, ["d_core", "d_loop_b", "d_loop_d"] as Array[String],
			"both loop arms meet here, and the core hangs off it")


## Killing `d_gate` must island `d_limb1` + `d_limb2` — a cut vertex is what
## makes the forced-dealloc cascade observable in this panel at all.
func test_the_gate_is_a_cut_vertex_of_the_defender_territory() -> void:
	var defender := _panel.find_child("DefenderEntity", true, false) as Entity
	var gate := _graph.get_node("Nodes/d_gate") as SkillNode
	var names: Array[String] = []
	for slice in defender.get_combat().cascade_set(gate.get_combat()):
		names.append(slice.real().name)
	names.sort()
	assert_eq(names, ["d_gate", "d_limb1", "d_limb2"] as Array[String],
			"the gate itself, plus the limb that hangs off it and off nothing else")

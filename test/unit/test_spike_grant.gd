extends GutTest

## SpikeRingAddon's spikes / spike_regen / blunting grant (#778). Only
## SpikeRingAddon ever contributes to spikes / spike_regen, and the grant
## scales 1:2:3 with the carrier's own stake_level (the N in the M/N dial,
## SkillNode.stake_level) -- so only ORDERING is asserted here, never the
## literal numbers: those are the owner's to tune (issue #778, acceptance 6).

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SPIKE_SCENE := preload("res://skill_node/addons/defs/spike_ring_addon.tscn")


## [param alloc] < 0 fills the node to its cap. Set AFTER [code]stake_level[/code]:
## the pool clamps fill to the cap.
func _spawn_node(graph: Node, nm: String, stake: int, alloc: int = -1) -> SkillNode:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = nm
	graph.skill_nodes_container.add_child(node)
	node.stake_level = stake
	node.allocation_level = stake if alloc < 0 else alloc
	return node


func _spiked_node(graph: Node, nm: String, stake: int, alloc: int = -1) -> SkillNode:
	var node := _spawn_node(graph, nm, stake, alloc)
	node.add_child(_SPIKE_SCENE.instantiate())
	return node


func _setup_graph() -> Node:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	return graph


func test_spikes_scale_with_allocation_not_stake() -> void:
	var graph := _setup_graph()
	var node := _spiked_node(graph, "S", 3, 1)
	var full := _spiked_node(graph, "Full", 3, 3)
	await get_tree().process_frame
	var spikes_a1 := float(node.get_local_value(&"spikes"))
	var regen_a1 := float(node.get_local_value(&"spike_regen"))
	assert_gt(spikes_a1, 0.0, "allocation 1 grants a nonzero spikes cap")
	assert_almost_eq(float(full.get_local_value(&"spikes")) / spikes_a1, 3.0, 1e-6,
			"a 1/3 node holds a third of a 3/3 node's spikes -- the fill scales it, not the stake")
	node.allocation_level = 2
	await get_tree().process_frame
	assert_almost_eq(float(node.get_local_value(&"spikes")) / spikes_a1, 2.0, 1e-6,
			"raising allocation 1 -> 2 at stake 3 doubles spikes")
	assert_almost_eq(float(node.get_local_value(&"spike_regen")) / regen_a1, 2.0, 1e-6,
			"raising allocation 1 -> 2 at stake 3 doubles spike_regen")


func test_spikes_cap_orders_strictly_with_stake() -> void:
	var graph := _setup_graph()
	var n1 := _spiked_node(graph, "S1", 1)
	var n2 := _spiked_node(graph, "S2", 2)
	var n3 := _spiked_node(graph, "S3", 3)
	await get_tree().process_frame
	var spikes1 := float(n1.get_local_value(&"spikes"))
	var spikes2 := float(n2.get_local_value(&"spikes"))
	var spikes3 := float(n3.get_local_value(&"spikes"))
	assert_gt(spikes3, spikes2, "stake 3 must grant more spikes cap than stake 2")
	assert_gt(spikes2, spikes1, "stake 2 must grant more spikes cap than stake 1")
	assert_gt(spikes1, 0.0, "even stake 1 must grant a nonzero spikes cap")


func test_spike_regen_orders_strictly_with_stake() -> void:
	var graph := _setup_graph()
	var n1 := _spiked_node(graph, "S1", 1)
	var n2 := _spiked_node(graph, "S2", 2)
	var n3 := _spiked_node(graph, "S3", 3)
	await get_tree().process_frame
	var regen1 := float(n1.get_local_value(&"spike_regen"))
	var regen2 := float(n2.get_local_value(&"spike_regen"))
	var regen3 := float(n3.get_local_value(&"spike_regen"))
	assert_gt(regen3, regen2, "stake 3 must grant more spike_regen than stake 2")
	assert_gt(regen2, regen1, "stake 2 must grant more spike_regen than stake 1")
	assert_gt(regen1, 0.0, "even stake 1 must grant a nonzero spike_regen")


func test_unspiked_node_has_zero_spikes_at_any_stake() -> void:
	var graph := _setup_graph()
	var plain := _spawn_node(graph, "Plain", 3)
	await get_tree().process_frame
	assert_eq(float(plain.get_local_value(&"spikes")), 0.0,
			"only SpikeRingAddon grants spikes -- an unspiked node holds 0 at any stake")


func test_spiked_nodes_blunting_beats_the_unspiked_default() -> void:
	var graph := _setup_graph()
	var spiked := _spiked_node(graph, "Spiked", 1)
	var plain := _spawn_node(graph, "Plain", 1)
	await get_tree().process_frame
	var spiked_blunting := float(spiked.get_local_value(&"blunting"))
	var plain_blunting := float(plain.get_local_value(&"blunting"))
	assert_gt(spiked_blunting, plain_blunting,
			"a spiked node's own blade vertex must blunt harder than a plain one")


func test_removing_spike_addon_reverts_spikes_to_zero() -> void:
	var graph := _setup_graph()
	var node := _spiked_node(graph, "Spiked", 2)
	await get_tree().process_frame
	assert_gt(float(node.get_local_value(&"spikes")), 0.0, "spiked node grants spikes")
	var addon := node.get_addons()[0]
	addon.free()
	await get_tree().process_frame
	assert_eq(float(node.get_local_value(&"spikes")), 0.0,
			"removing the only spike addon must revert spikes to 0")

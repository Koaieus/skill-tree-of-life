extends GutTest

## A staking channel ([member SkillNode.channel_target] /
## [member SkillNode.channel_progress]) and a procgen `stake_ceiling` lift are
## accumulated node state: they cross a [GraphSnapshot] by value, the channel
## folds into [WorldFingerprint], and a pre-channel (v7) row still decodes.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _V7_ROW_SIZE := 17


func _new_graph(node_count: int = 3) -> Graph:
	var graph: Graph = autofree(_GRAPH_SCENE.instantiate())
	add_child(graph)
	await get_tree().process_frame
	for i in node_count:
		var n := _NODE_SCENE.instantiate() as SkillNode
		n.position = Vector2(200 * i, 0)
		graph.add_skill_node(n)
	return graph


func _twin(source: Graph, graph: Graph, node: SkillNode) -> SkillNode:
	return graph.get_by_stable_id(source.get_stable_id(node))


func test_round_trip_preserves_a_channel() -> void:
	var source := await _new_graph()
	var target := await _new_graph(0)
	var node: SkillNode = source.get_skill_nodes()[1]
	node.channel_target = 3
	node.channel_progress = 2

	GraphSnapshot.decode(GraphSnapshot.encode(source), target)

	var got := _twin(source, target, node)
	assert_eq(got.channel_target, 3, "channel_target crosses")
	assert_eq(got.channel_progress, 2, "channel_progress crosses")
	assert_eq(WorldFingerprint.compute(target), WorldFingerprint.compute(source))


func test_resync_clears_a_channel_the_authority_does_not_hold() -> void:
	var source := await _new_graph()
	var target := await _new_graph(0)
	GraphSnapshot.decode(GraphSnapshot.encode(source), target)
	var node: SkillNode = source.get_skill_nodes()[0]
	var drifted := _twin(source, target, node)
	drifted.channel_target = 2
	drifted.channel_progress = 1

	GraphSnapshot.decode(GraphSnapshot.encode(source), target)

	assert_eq(drifted.channel_target, 0)
	assert_eq(drifted.channel_progress, 0)


func test_fingerprint_differs_by_channel_ints() -> void:
	var a := await _new_graph()
	var b := await _new_graph()
	var fp := WorldFingerprint.compute(b)
	b.get_skill_nodes()[2].channel_target = 2
	assert_ne(WorldFingerprint.compute(b), fp, "channel_target folds")
	fp = WorldFingerprint.compute(b)
	b.get_skill_nodes()[2].channel_progress = 1
	assert_ne(WorldFingerprint.compute(b), fp, "channel_progress folds")
	assert_ne(WorldFingerprint.compute(a), WorldFingerprint.compute(b))


func test_round_trip_preserves_a_stake_ceiling_lift() -> void:
	var source := await _new_graph()
	var target := await _new_graph(0)
	var node: SkillNode = source.get_skill_nodes()[1]
	EntityFactory.set_procgen_stake(node, 5)
	assert_eq(node.stake_ceiling, 5, "precondition: lifted")

	GraphSnapshot.decode(GraphSnapshot.encode(source), target)
	var got := _twin(source, target, node)
	assert_eq(got.stake_ceiling, 5, "the lift crosses")
	assert_eq(got.stake_level, 5)

	# A second decode reconciles rather than stacking the lifts again.
	GraphSnapshot.decode(GraphSnapshot.encode(source), target)
	assert_eq(got.stake_ceiling, 5, "a resync does not double-apply the lift")


func test_a_lift_outlives_the_stake_that_raised_it() -> void:
	var source := await _new_graph()
	var target := await _new_graph(0)
	var node: SkillNode = source.get_skill_nodes()[1]
	EntityFactory.set_procgen_stake(node, 5)
	node.stake_level = 2

	GraphSnapshot.decode(GraphSnapshot.encode(source), target)

	assert_eq(_twin(source, target, node).stake_ceiling, 5,
			"the lift count crosses, not a ceiling re-derived from the stake")


## A v7 body (rows end at `_R_LAST_OWNED_VISION`): no channel, and the lift
## re-derives so the ceiling never sits below the row's stake.
func test_a_pre_channel_row_decodes_with_defaults() -> void:
	var source := await _new_graph()
	var target := await _new_graph(0)
	var node: SkillNode = source.get_skill_nodes()[1]
	EntityFactory.set_procgen_stake(node, 4)
	node.channel_target = 3
	var payload := GraphSnapshot._unpack(GraphSnapshot.encode(source))
	var rows: Array = payload["nodes"]
	for i in rows.size():
		rows[i] = (rows[i] as Array).slice(0, _V7_ROW_SIZE)

	GraphSnapshot.decode(GraphSnapshot._pack(payload), target)

	var got := _twin(source, target, node)
	assert_eq(got.channel_target, 0)
	assert_eq(got.channel_progress, 0)
	assert_eq(got.stake_level, 4)
	assert_eq(got.stake_ceiling, 4, "the lift re-derives from the stake")

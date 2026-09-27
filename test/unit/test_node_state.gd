extends GutTest

## NodeState — the silent storage bag a SkillNode composes and forwards into.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func _node() -> SkillNode:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	return node


func test_clone_is_detached_at_combat_depth() -> void:
	var s := NodeState.new()
	var owner: Entity = autofree(Entity.new())
	s.owned_by = owner
	s.ensure_board(SkillNode.DEFAULT_NODE_BOARD)
	s.board.stake_level.base_value = 3.0
	s.tags[&"poisoned"] = 1
	s.modifiers.append(StatModifier.new())
	s.regen_stacks = 2
	s.damaged_since_upkeep = true

	var c := s.clone()
	assert_not_null(c, "clone returns a NodeState")
	assert_true(c.board_ready, "a clone of a minted state is minted")
	assert_ne(c.board, s.board, "the clone's board is its own instance")
	assert_eq(c.board.stake_level.value, 3.0, "and carries the live values")
	c.board.stake_level.base_value = 1.0
	assert_eq(s.board.stake_level.value, 3.0, "writing the clone's board leaves the original alone")
	c.tags[&"lifeline"] = 1
	assert_false(s.tags.has(&"lifeline"), "tags are a separate dictionary")
	assert_eq(c.tags.get(&"poisoned"), 1, "carrying the original's entries")
	assert_same(c.owned_by, owner, "owned_by is copied by identity")
	assert_same(c.modifiers, s.modifiers, "modifiers is the same array (reference)")
	assert_eq(c.regen_stacks, 2, "scalars by value")
	assert_true(c.damaged_since_upkeep, "scalars by value")
	c.regen_stacks = 0
	assert_eq(s.regen_stacks, 2, "a scalar write on the clone stays there")


func test_skill_node_forwards_owned_by_into_state_and_emits() -> void:
	var node := _node()
	var owner: Entity = autofree(Entity.new())
	watch_signals(node)
	node.owned_by = owner
	assert_same(node.state.owned_by, owner, "the node's write lands in its state")
	assert_signal_emit_count(node, "owner_changed", 1, "the node's setter emits once")
	node.state.owned_by = null
	assert_null(node.owned_by, "the node reads its state back")
	assert_signal_emit_count(node, "owner_changed", 1, "a state write is silent")


func test_board_identity_survives_the_move() -> void:
	var node := _node()
	var m := StatModifier.new()
	m.stat_id = &"armor"
	node.add_local_modifier(m)
	var board := node.node_board
	assert_true(node.state.board_ready, "a local modifier mints the board")
	assert_same(board, node.state.board, "node_board IS the state's board")
	node._ensure_local_stat(&"node_healing")
	assert_not_null(board.get_stat(&"node_healing"), "the mint landed on that board")
	assert_same(node.node_board, board, "same instance after a stat mint")
	assert_same(node.state.board, board, "and the state still holds it")

extends GutTest

## #812 — [signal StatBoard.stat_created] must fire from EVERY [member
## StatBoard._extra_stats] writer, not just the default [method
## StatBoard._mint_stat]. [method NodeStatBoard._mint_pool] (the
## `node_health` / `spikes` redirect to a [PoolStat] def, #778) used to write
## `_extra_stats` directly and never emit — a listener subscribing to one of
## those ids at node-ready time got no callback and no error. Both mint paths
## now route through [method StatBoard._register_minted].


func test_minting_node_health_on_a_node_stat_board_fires_stat_created() -> void:
	var board := NodeStatBoard.new()
	var seen: Array = []
	board.stat_created.connect(func(id: StringName, s: Stat) -> void: seen.append([id, s]))

	var minted := board._ensure_stat(&"node_health")

	assert_eq(seen.size(), 1, "stat_created fires exactly once for the mint")
	assert_eq(seen[0][0], &"node_health")
	assert_same(seen[0][1], minted)
	assert_true(minted is PoolStat, "node_health mints as a PoolStat, not a ScalarStat (#778)")


func test_minting_spikes_on_a_node_stat_board_fires_stat_created() -> void:
	var board := NodeStatBoard.new()
	var seen: Array = []
	board.stat_created.connect(func(id: StringName, s: Stat) -> void: seen.append([id, s]))

	var minted := board._ensure_stat(&"spikes")

	assert_eq(seen.size(), 1, "stat_created fires exactly once for the mint")
	assert_eq(seen[0][0], &"spikes")
	assert_same(seen[0][1], minted)


func test_re_ensuring_an_already_minted_node_health_does_not_re_emit() -> void:
	var board := NodeStatBoard.new()
	board._ensure_stat(&"node_health")

	var seen: Array = []
	board.stat_created.connect(func(id: StringName, s: Stat) -> void: seen.append([id, s]))
	board._ensure_stat(&"node_health")

	assert_eq(seen.size(), 0, "an existing _extra_stats entry is never re-minted (#810)")

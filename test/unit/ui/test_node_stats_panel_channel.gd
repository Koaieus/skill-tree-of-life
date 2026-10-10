extends GutTest

## The node tooltip's channel row: a channelling node reads
## "M/N → T, k/K turns" under a direction label; an idle node gets no row.
## Pure functions of the node's channel state — no system, no scene.


func test_stake_channel_reads_fill_cap_target_and_turns() -> void:
	assert_eq(NodeStatsPanel.channel_text(1, 2, 3, 1, 2), "1/2 → 3, 1/2 turns")


func test_extract_channel_reads_the_lower_target() -> void:
	assert_eq(NodeStatsPanel.channel_text(2, 3, 2, 0, 3), "2/3 → 2, 0/3 turns")


func test_unknown_turn_count_drops_the_counter() -> void:
	assert_eq(NodeStatsPanel.channel_text(1, 2, 3, 1, 0), "1/2 → 3",
			"no AllocationSystem bound → no K to show, never a guessed one")


func test_idle_node_has_no_channel_text() -> void:
	assert_eq(NodeStatsPanel.channel_text(1, 2, 0, 0, 2), "")


func test_direction_names_the_row() -> void:
	assert_eq(NodeStatsPanel.channel_label(1), "Staking")
	assert_eq(NodeStatsPanel.channel_label(-1), "Extracting")
	assert_eq(NodeStatsPanel.channel_label(0), "")

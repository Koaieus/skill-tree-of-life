extends GutTest

## [method LobbyOption.display_label]: an authored label wins; an empty one is
## derived from the condition the first patch writes, so a number authored on
## that condition (the turn limit's round count) is authored once.

const _TURN_LIMIT_PATH := "res://session/victory/turn_limit.tres"
const _MAP_SIZES := preload("res://ui/frontmatter/lobby_options/map_size_options.tres")
const _VICTORY := preload("res://ui/frontmatter/lobby_options/victory_options.tres")


func _option(label: String, value: Variant) -> LobbyOption:
	var patch := ScenarioOverride.new()
	patch.target = "victory_condition"
	patch.value = value
	var o := LobbyOption.new()
	o.label = label
	o.patches = [patch] as Array[ScenarioOverride]
	return o


func test_an_empty_label_displays_the_patched_conditions_description() -> void:
	var described: String = (load(_TURN_LIMIT_PATH) as VictoryCondition).describe()
	assert_ne(described, "", "the shipped turn limit describes itself")
	assert_eq(_option("", _TURN_LIMIT_PATH).display_label(), described)


func test_an_authored_label_is_displayed_unchanged() -> void:
	assert_eq(_option("Sudden death", _TURN_LIMIT_PATH).display_label(), "Sudden death")
	for c in _MAP_SIZES.choices():
		assert_ne(c.label, "", "the map-size ladder authors its labels")
		assert_eq(c.display_label(), c.label)


func test_the_shipped_turn_limit_option_shows_the_authored_limit() -> void:
	var limit: TurnLimitCondition = (load(_TURN_LIMIT_PATH) as CombinedVictoryCondition).bonus_conditions[0]
	var labels: Array[String] = []
	for c in _VICTORY.choices():
		labels.append(c.display_label())
	assert_eq(labels.size(), 2)
	assert_eq(labels[0], "Last camp standing")
	assert_string_contains(labels[1], "Turn limit")
	assert_string_contains(labels[1], str(limit.limit))

extends GutTest

## A laid-out [BadgeLabel]: the amount, the badge and the noun of a concept
## token are one hover target (`concept:<id>`), and the plain runs around it
## carry no concept key. Swept in 1 px steps over the first row, so it pins the
## structure without assuming glyph widths.


func test_the_whole_token_is_one_hover_target() -> void:
	var label := BadgeLabel.new()
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size = Vector2(400, 0)
	add_child_autofree(label)
	label.badge_text = "applies {poison:4} stacks"
	await wait_process_frames(2)
	var width := label.get_line_width(0)
	var y := label.get_line_height(0) * 0.5
	assert_gt(width, 0, "guard: the row is laid out")
	var key := BadgeText.HINT_PREFIX + "poison"
	var runs: Array[String] = []
	for x in range(0, width):
		var tip := label.get_tooltip(Vector2(x, y))
		var at := key if tip == key else ("concept" if tip.begins_with(BadgeText.HINT_PREFIX) else "")
		if runs.is_empty() or runs[-1] != at:
			runs.append(at)
	assert_eq(runs, ["", key, ""] as Array[String], "plain, then one token target, then plain")

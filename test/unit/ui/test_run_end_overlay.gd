extends GutTest

## The run-end surface on its own (#526) — copy per reading, and the delayed
## action row. How a [RunOutcome] becomes a reading in the first place is
## [HudRoot]'s half, pinned by `test/unit/scenes/test_run_end_presentation.gd`.

const _OVERLAY := preload("res://ui/run_end_overlay/run_end_overlay.tscn")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")

## Long enough to observe "absent, then present" on both sides without paying
## the authored 2.5s in a suite that already costs ~110s.
const _ROW_DELAY: float = 0.15

var _overlay: RunEndOverlay


func before_each() -> void:
	_overlay = _OVERLAY.instantiate()
	add_child_autofree(_overlay)
	_overlay.action_row_delay = 0.0
	await wait_physics_frames(1)


func test_it_starts_hidden() -> void:
	assert_false(_overlay.visible, "nothing has ended yet")


# --- Copy reads correctly for all four readings ----------------------------

func test_a_seated_winner_reads_victory() -> void:
	_overlay.present(RunEndOverlay.Reading.VICTORY, _CAMP_1)

	assert_eq(_overlay.title_label.text, "VICTORY")
	assert_eq(_overlay.subtitle_label.text, "%s holds the tree" % _CAMP_1.display_name)


func test_a_seated_loser_reads_defeat() -> void:
	_overlay.present(RunEndOverlay.Reading.DEFEAT, _CAMP_1)

	assert_eq(_overlay.title_label.text, "DEFEAT")
	assert_eq(_overlay.subtitle_label.text, "%s holds the tree" % _CAMP_1.display_name,
			"a loser still wants to know to whom")


## A couch has no camp to have lost from, so the surface is *run over*, not a
## defeat screen — the whole reason the old game-over stub could not serve it.
func test_a_couch_reads_as_run_over_and_names_the_winner() -> void:
	_overlay.present(RunEndOverlay.Reading.NEUTRAL, _CAMP_1)

	assert_eq(_overlay.title_label.text, "RUN OVER")
	assert_eq(_overlay.subtitle_label.text, "%s holds the tree" % _CAMP_1.display_name)


func test_a_draw_names_no_camp() -> void:
	_overlay.present(RunEndOverlay.Reading.DRAW, null)

	assert_eq(_overlay.title_label.text, "DRAW")
	assert_eq(_overlay.subtitle_label.text, "the tree stands unclaimed")


## The title is camp-tinted where a camp won it — except a defeat, which must
## not celebrate in the loser's face.
func test_a_defeat_is_not_tinted_with_the_winners_colour() -> void:
	_overlay.present(RunEndOverlay.Reading.VICTORY, _CAMP_1)
	var won := _overlay.title_label.get_theme_color("font_color")
	_overlay.present(RunEndOverlay.Reading.DEFEAT, _CAMP_1)

	assert_ne(_overlay.title_label.get_theme_color("font_color"), won)


# --- The delayed action row ------------------------------------------------

## The terminal banner owns the first beat; a button materialising under it
## pulls the eye off the announcement it is meant to follow.
func test_the_action_row_is_absent_at_first_and_present_after_the_delay() -> void:
	_overlay.action_row_delay = _ROW_DELAY

	_overlay.present(RunEndOverlay.Reading.DRAW, null)
	assert_true(_overlay.visible, "the surface itself is immediate")
	assert_false(_overlay.action_row.visible, "the row is not")

	await wait_seconds(_ROW_DELAY + 0.15)

	assert_true(_overlay.action_row.visible)


## A second run-end on the same overlay must not inherit the first's row —
## `present` re-hides it before re-arming the delay.
func test_presenting_again_hides_the_row_again() -> void:
	_overlay.action_row_delay = _ROW_DELAY
	_overlay.present(RunEndOverlay.Reading.DRAW, null)
	await wait_seconds(_ROW_DELAY + 0.15)
	assert_true(_overlay.action_row.visible, "precondition")

	_overlay.present(RunEndOverlay.Reading.VICTORY, _CAMP_1)

	assert_false(_overlay.action_row.visible)


# --- It asks; it does not route --------------------------------------------

## The overlay owns no route: [GameRoot] does, veto included. All the button
## does is say so.
func test_the_button_asks_to_leave() -> void:
	_overlay.present(RunEndOverlay.Reading.DRAW, null)
	var asked: Array[int] = []
	_overlay.main_menu_pressed.connect(func() -> void: asked.append(1))

	_overlay.main_menu_button.pressed.emit()

	assert_eq(asked.size(), 1, "one request, straight off the button")

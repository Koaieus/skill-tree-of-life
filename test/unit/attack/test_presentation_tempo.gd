extends GutTest
## [PresentationTempo] formula tests. The magic wind-up trio (#1043) copies the
## melee trio's shape: every term clamped at zero, all-zero is the escape hatch.


func _tempo(pivot: float, span: float, flare: float) -> PresentationTempo:
	var tempo := PresentationTempo.new()
	tempo.magic_windup_pivot_focus = pivot
	tempo.magic_windup_draw_span = span
	tempo.magic_windup_flare = flare
	return tempo


func test_magic_windup_seconds_is_pivot_plus_span_plus_flare() -> void:
	assert_almost_eq(_tempo(0.25, 0.6, 0.1).magic_windup_seconds(), 0.95, 0.0001,
			"pivot focus + draw span + flare")


func test_magic_windup_seconds_clamps_each_term_at_zero() -> void:
	assert_almost_eq(_tempo(-1.0, 0.6, -0.5).magic_windup_seconds(), 0.6, 0.0001,
			"a negative authored beat contributes nothing, never runs the sequence backwards")


func test_magic_windup_all_zero_is_zero() -> void:
	assert_eq(_tempo(0.0, 0.0, 0.0).magic_windup_seconds(), 0.0,
			"authoring every beat to 0.0 is the regression escape hatch")


func test_magic_windup_lead_is_the_pivot_focus() -> void:
	var tempo := _tempo(0.25, 0.6, 0.1)
	assert_almost_eq(tempo.windup_lead(BattleSystem.AttackMode.MAGIC),
			tempo.magic_windup_pivot_focus, 0.0001,
			"the camera's hold and the presenter's delay read the same number")


func test_shared_default_authors_the_magic_trio() -> void:
	var tempo := PresentationTempo.shared_default()
	assert_almost_eq(tempo.magic_windup_pivot_focus, 0.25, 0.0001, "pivot focus authored")
	assert_almost_eq(tempo.magic_windup_draw_span, 0.6, 0.0001, "draw span authored")
	assert_almost_eq(tempo.magic_windup_flare, 0.1, 0.0001, "flare authored")
	# The `.gd` defaults are the fallback for a missing `.tres` — same numbers.
	var fresh := PresentationTempo.new()
	assert_almost_eq(fresh.magic_windup_seconds(), tempo.magic_windup_seconds(), 0.0001,
			"the script defaults and the .tres agree")

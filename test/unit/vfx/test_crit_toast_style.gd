extends GutTest

## The crit register for damage toasts.
##
## Two things are pinned here and nothing else: that a crit is CLASSIFIED off
## the hit rather than guessed (and that a non-hit `source` — turn regen's null
## — can't crash or accidentally crit), and that the PUNCH variant's custom
## entry animation still grows its slot. The latter is the trap a subclass
## overriding `animate()` falls into: slot growth is what pushes the rest of the
## toaster's stack upward, so a crit toast that forgets it silently breaks every
## other toast sharing that toaster.
##
## What a crit LOOKS like is deliberately not asserted — that's an eyeball
## question, answered in the toast sandbox's gallery.

const FloaterStyles := preload("res://ui/floating_number_layer/floater_styles.gd")
const PUNCH_SCENE := preload(
		"res://ui/floating_number_layer/crit_punch_toast/crit_punch_toast.tscn")


func _hit(is_crit: bool, tier: int) -> DamageInstance:
	var h := DamageInstance.new()
	h.is_crit = is_crit
	h.crit_tier = tier
	return h


# --- Classification ---------------------------------------------------------

func test_normal_hit_is_not_a_crit() -> void:
	assert_eq(FloaterDirector._crit_tier(_hit(false, 0)), 0)


func test_crit_flag_without_a_tier_still_ranks_one() -> void:
	# `is_crit` is the decision, `crit_tier` the stacking count — a hit flagged
	# crit with an unset tier must not fall back to "normal".
	assert_eq(FloaterDirector._crit_tier(_hit(true, 0)), 1)


func test_stacked_crit_keeps_its_tier() -> void:
	assert_eq(FloaterDirector._crit_tier(_hit(true, 2)), 2)


func test_non_hit_sources_never_crit() -> void:
	# Turn regen passes null; other callers pass their own objects.
	assert_eq(FloaterDirector._crit_tier(null), 0, "turn regen's null source")
	assert_eq(FloaterDirector._crit_tier(RefCounted.new()), 0, "an unrelated source")


# --- Text -------------------------------------------------------------------

func test_damage_text_marks_crits() -> void:
	assert_eq(FloaterDirector._damage_text(7.4, 0), "7")
	assert_eq(FloaterDirector._damage_text(18.0, 1), "18!")
	assert_eq(FloaterDirector._damage_text(18.0, 2), "18!!")
	assert_eq(FloaterDirector._damage_text(18.0, 9), "18!!", "the bang count is capped")


# --- Style dispatch ---------------------------------------------------------

func test_damage_style_is_flat_red_without_a_crit() -> void:
	var s := FloaterStyles.damage()
	assert_eq(s.fill_color, FloaterStyles.COLOR_DAMAGE)
	assert_eq(s.font_size, 0, "a normal damage toast inherits the authored size")


func test_crit_style_is_emissive_and_larger() -> void:
	var s := FloaterStyles.damage(1)
	assert_gt(s.font_size, 32, "a crit outsizes the stock toast")
	assert_gt(s.fill_color.srgb_to_linear().r, 1.0,
		"a crit clears the bloom threshold — see .claude/rules/hdr-color.md")


func test_stacked_crit_escalates_over_a_single_one() -> void:
	var one := FloaterStyles.damage(1)
	var two := FloaterStyles.damage(2)
	assert_gt(two.font_size, one.font_size, "tier 2 outsizes tier 1")
	assert_gt(two.fill_color.srgb_to_linear().r, one.fill_color.srgb_to_linear().r,
		"tier 2 burns hotter")


func test_crit_stops_are_capped() -> void:
	# A long crit chain must not drive the bloom pass into a white blob.
	var high := FloaterStyles.crit(9)
	var alert := FloaterStyles.crit(3)
	assert_eq(high.fill_color, alert.fill_color, "the EV lift saturates at ALERT")


# --- The crit toast's entry animation ----------------------------------------

func test_crit_toast_still_grows_its_slot() -> void:
	var t: FloaterToast = PUNCH_SCENE.instantiate()
	add_child_autofree(t)
	t.set_content("18!", FloaterStyles.crit())
	var full_height := t.custom_minimum_size.y
	assert_gt(full_height, 0.0, "set_content sized the slot")

	t.animate()
	assert_almost_eq(t.custom_minimum_size.y, 0.0, 0.001, "the slot starts collapsed")
	await wait_seconds(t.fade_in_duration + 0.1)
	assert_almost_eq(t.custom_minimum_size.y, full_height, 0.5,
		"the slot grew back — this is what pushes the stack up")


func test_crit_toast_cools_back_to_the_style_colour() -> void:
	var t: FloaterToast = PUNCH_SCENE.instantiate()
	add_child_autofree(t)
	var style := FloaterStyles.crit()
	t.set_content("18!", style)
	t.animate()
	var ignition: Color = t.label.label_settings.font_color
	assert_gt(ignition.srgb_to_linear().r, style.fill_color.srgb_to_linear().r,
		"it lands white-hot, above its own resting colour")
	await wait_seconds(0.6)
	assert_almost_eq(t.label.label_settings.font_color.r, style.fill_color.r, 0.02,
		"and cools into the style's fill")

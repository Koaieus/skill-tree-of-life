extends GutTest

## The #81 PoC toaster only stamped fill_color + scene_override, silently dropping
## font_size / glow / float_time — so the mythic CORE-modifier style rendered
## wrong. This pins the grown-up contract: FloaterToast.set_content applies the
## WHOLE FloaterStyle, and the inherit sentinels (font_size/float_time == 0) leave
## the scene-authored values untouched.

const TOAST_SCENE := preload("res://ui/floating_number_layer/floater_toast.tscn")
const FloaterStyles := preload("res://ui/floating_number_layer/floater_styles.gd")

const STOCK_FONT_SIZE := 32  # authored in floater_toast.tscn's LabelSettings
const STOCK_VISIBLE := 1.75  # FloaterToast.visible_duration default


func _toast() -> FloaterToast:
	var t: FloaterToast = TOAST_SCENE.instantiate()
	add_child(t)
	autofree(t)
	return t


func test_basic_style_inherits_authored_size() -> void:
	var t := _toast()
	t.set_content("7", FloaterStyles.damage())
	assert_eq(t.label.label_settings.font_color, FloaterStyles.COLOR_DAMAGE)
	assert_eq(t.label.label_settings.font_size, STOCK_FONT_SIZE,
		"font_size 0 sentinel → keep the scene's 32")
	assert_almost_eq(t.visible_duration, STOCK_VISIBLE, 0.001,
		"float_time 0 sentinel → keep the scene's hold")


func test_mythic_style_applies_font_and_glow() -> void:
	var t := _toast()
	var style := FloaterStyles.modifier_core(Color(0.55, 0.75, 1.0))
	t.set_content("+10 Strength", style)
	assert_eq(t.label.label_settings.font_size, 46, "mythic font_size honoured")
	assert_gt(t.label.label_settings.shadow_size, 0, "glow renders as a shadow halo")
	assert_eq(t.label.label_settings.shadow_color, style.glow_color, "halo uses glow_color")
	assert_almost_eq(t.visible_duration, 3.6, 0.001, "mythic float_time overrides the hold")
	assert_gte(t.custom_minimum_size.y, 46.0, "slot grows to fit the enlarged font")


func test_null_style_is_safe() -> void:
	var t := _toast()
	t.set_content("debug", null)
	assert_eq(t.label.text, "debug")
	assert_eq(t.label.label_settings.font_color, Color.WHITE, "null style → white")


func test_style_duplication_does_not_bleed_across_toasts() -> void:
	# set_content duplicates label_settings; a big-font toast must not enlarge a
	# later basic one sharing the scene's sub-resource.
	var big := _toast()
	big.set_content("+10", FloaterStyles.modifier_core(Color.AQUA))
	var basic := _toast()
	basic.set_content("3", FloaterStyles.damage())
	assert_eq(basic.label.label_settings.font_size, STOCK_FONT_SIZE,
		"the mythic toast's font_size must not leak into the basic one")

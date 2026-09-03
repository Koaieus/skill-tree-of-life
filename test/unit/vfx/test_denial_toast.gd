extends GutTest

## The denial toast — [signal Events.node_action_denied] → [FloaterDirector].
## #89's shake (and #404's island blink) say a click was refused but not WHY;
## the director now floats the reason at the refused node. Pins: the intake,
## the reason→text mapping (every row non-empty), unmapped reasons staying
## silent, and the quiet register (muted deny red, short hold).

const _DIRECTOR_SCENE := preload("res://ui/floating_number_layer/floater_director.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const FloaterStyles := preload("res://ui/floating_number_layer/floater_styles.gd")

var _director: FloaterDirector
var _renderer: FloaterToasterManager


func before_each() -> void:
	_director = _DIRECTOR_SCENE.instantiate() as FloaterDirector
	_director.vision_system = null  # no fog gating in tests
	add_child_autofree(_director)
	_renderer = _director.renderer


func _toasts() -> Array[FloaterToast]:
	var out: Array[FloaterToast] = []
	for toaster in _renderer.get_children():
		if toaster is FloaterToaster:
			for child in (toaster as FloaterToaster).get_node("VBoxContainer").get_children():
				out.append(child as FloaterToast)
	return out


func test_denial_floats_the_reason_at_the_node() -> void:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	await get_tree().process_frame
	Events.node_action_denied.emit(node, "stake_denied_not_adjacent")
	var toasts := _toasts()
	assert_eq(toasts.size(), 1, "one denial toast")
	assert_eq(toasts[0].label.text, "TOO FAR FROM CORE",
			"the reason in player-facing words, not snake_case")


func test_denial_style_is_the_quiet_register() -> void:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	await get_tree().process_frame
	Events.node_action_denied.emit(node, "stake_denied_no_ap")
	var toasts := _toasts()
	assert_eq(toasts.size(), 1)
	var toast := toasts[0]
	assert_eq(toast.label.label_settings.font_color, FloaterStyles.COLOR_DENIED,
			"the deny-tint register, matching the shake")
	assert_almost_eq(toast.visible_duration, 1.2, 0.001,
			"short hold — instructive, not alarming")
	assert_eq(toast.label.label_settings.font_size, 32,
			"stock size — no glow, no shout")


func test_unknown_reason_stays_silent() -> void:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	await get_tree().process_frame
	Events.node_action_denied.emit(node, "no_such_reason")
	assert_eq(_toasts().size(), 0,
			"an unmapped reason toasts nothing rather than raw snake_case")


func test_null_node_makes_no_toast() -> void:
	await get_tree().process_frame
	Events.node_action_denied.emit(null, "stake_denied_no_ap")
	assert_eq(_toasts().size(), 0)


func test_every_mapped_reason_has_text() -> void:
	for reason in FloaterDirector._DENIAL_TEXTS:
		assert_false(FloaterDirector._denial_text(reason).is_empty(),
				"reason '%s' must map to visible text" % reason)


func test_denial_style_in_gallery() -> void:
	# The toast sandbox enumerates gallery() so preview and production cannot
	# drift — a new style that isn't in the gallery is never previewable.
	var names := FloaterStyles.gallery().map(func(row): return row["name"])
	assert_has(names, "Denied", "the Denied variant is previewable in the sandbox")

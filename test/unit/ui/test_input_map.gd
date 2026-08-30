extends GutTest

## `ui_accept` / `ui_cancel` carry a joypad binding (#585).
##
## [b]Config defect, pinned in config terms.[/b] Neither action carried a
## joypad event — the engine's own built-in default was keyboard-only for
## these two, unlike `ui_up`/`ui_down`/`ui_left`/`ui_right`, which already ship
## D-pad and stick bindings. A controller's A and B buttons did nothing
## anywhere in the game as a result. The fix lives in `project.godot`'s
## `[input]` section, not in any script — the same shape as #577's
## `test_boot_is_registered_as_a_real_global`, which asserts a registration
## rather than a behaviour because that is what a config-only fix leaves to
## test.
##
## [b]Re-stating an action in `project.godot` REPLACES the built-in.[/b] Adding
## the joypad event without re-stating the keyboard ones would have silently
## dropped Enter / Kp Enter / Space / Escape everywhere in the game — so the
## keyboard side is asserted here too, not just the new joypad side.


func _keycodes(action: StringName) -> Array:
	var codes := []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			codes.append((event as InputEventKey).keycode)
	return codes


func test_ui_accept_carries_a_joypad_button() -> void:
	var found := false
	for event in InputMap.action_get_events(&"ui_accept"):
		if event is InputEventJoypadButton:
			found = true
			assert_eq((event as InputEventJoypadButton).button_index, JOY_BUTTON_A)
	assert_true(found, "ui_accept binds a joypad button")


func test_ui_cancel_carries_a_joypad_button() -> void:
	var found := false
	for event in InputMap.action_get_events(&"ui_cancel"):
		if event is InputEventJoypadButton:
			found = true
			assert_eq((event as InputEventJoypadButton).button_index, JOY_BUTTON_B)
	assert_true(found, "ui_cancel binds a joypad button")


func test_ui_accept_keeps_its_keyboard_bindings() -> void:
	# Re-stating ui_accept in project.godot to add the joypad event would have
	# silently dropped these if they were not re-stated alongside it.
	var codes := _keycodes(&"ui_accept")
	assert_true(codes.has(KEY_ENTER), "Enter still accepts")
	assert_true(codes.has(KEY_KP_ENTER), "Kp Enter still accepts")
	assert_true(codes.has(KEY_SPACE), "Space still accepts")


func test_ui_cancel_keeps_its_keyboard_binding() -> void:
	var codes := _keycodes(&"ui_cancel")
	assert_true(codes.has(KEY_ESCAPE), "Escape still cancels")

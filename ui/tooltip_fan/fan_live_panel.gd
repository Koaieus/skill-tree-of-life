@tool
extends Control
## Sandbox-host panel for the tooltip fan (#309, epic #159).
##
## Frames the REAL fan bench ([FanLiveSandbox] — the same `fan.tscn` [TooltipFan]
## mounts, over a real SkillNode + Entity fixture) in a 2D [SubViewport] with a
## right-hand control column, so every configuration the gating can produce is
## one click away without booting a level: whole-situation presets, fixture
## knobs, per-unit participation overrides, the zoom/clock knobs, and the
## drive modes (manual / loop / hover / scrub / drag).
##
## Satisfies [SandboxLiveTab]'s loader contract with [method noop] — there is no
## inspected resource, same as node_visuals_panel / gimbal_3d_showcase.

const _SANDROB_SCRIPT := preload("res://ui/tooltip_fan/fan_live_sandbox.gd")
const _FAN_SCENE_PATH := "res://ui/tooltip_fan/fan.tscn"

@onready var _sandbox: Node2D = %Sandbox


func _ready() -> void:
	_wire_presets()
	_wire_fixture()
	_wire_participation()
	_wire_knobs()
	_wire_drive()
	_wire_editor()
	_sync_controls()


# --- wiring ---------------------------------------------------------------------

func _wire_presets() -> void:
	var buttons := {
		"%PresetUnallocated": _SANDROB_SCRIPT.PRESET_UNALLOCATED,
		"%PresetFriendly": _SANDROB_SCRIPT.PRESET_FRIENDLY,
		"%PresetEnemy": _SANDROB_SCRIPT.PRESET_ENEMY,
		"%PresetCore": _SANDROB_SCRIPT.PRESET_CORE,
	}
	for path in buttons:
		var button: Button = get_node_or_null(path)
		if button != null:
			button.pressed.connect(func() -> void:
				_sandbox.apply_preset(buttons[path])
				_sync_controls())


func _wire_fixture() -> void:
	%OwnedCheck.toggled.connect(func(on: bool) -> void:
		_sandbox.set_owned(on)
		_sync_controls())
	%CoreCheck.toggled.connect(func(on: bool) -> void:
		_sandbox.set_core(on)
		_sync_controls())
	%AddonsSpin.value_changed.connect(func(v: float) -> void:
		_sandbox.set_addon_count(int(v))
		_sync_controls())
	%EffectsSpin.value_changed.connect(func(v: float) -> void:
		_sandbox.set_effect_count(int(v))
		_sync_controls())
	%FootprintCheck.toggled.connect(func(on: bool) -> void:
		_sandbox.set_footprint(on)
		_sync_controls())


func _wire_participation() -> void:
	for m in _sandbox.get_participation():
		var check: CheckButton = get_node_or_null("%Part" + String(m))
		if check != null:
			check.toggled.connect(func(on: bool) -> void:
				_sandbox.set_participating(String(m), on)
				_sync_controls())


func _wire_knobs() -> void:
	%ZoomSlider.value_changed.connect(func(v: float) -> void: _sandbox.set_zoom(v))
	%PinStepSlider.value_changed.connect(func(v: float) -> void: _sandbox.set_pin_step_degrees(v))
	%MaxArcSlider.value_changed.connect(func(v: float) -> void: _sandbox.set_max_arc_degrees(v))
	%PinFactorSlider.value_changed.connect(func(v: float) -> void: _sandbox.set_pin_factor(v))
	%SlideRateSlider.value_changed.connect(func(v: float) -> void: _sandbox.set_pin_slide_rate(v))


func _wire_drive() -> void:
	%PlayButton.pressed.connect(_sandbox.play_draw_in)
	%EraseButton.pressed.connect(_sandbox.play_erase)
	%LoopButton.toggled.connect(_sandbox.set_looping)
	%HoverButton.toggled.connect(_sandbox.set_hover_driven)
	%ResetButton.pressed.connect(_sandbox.reset_settled)
	%ScrubSlider.value_changed.connect(func(v: float) -> void: _sandbox.set_scrub(v))
	%HoverRadiusSlider.value_changed.connect(func(v: float) -> void:
		_sandbox.hover_radius = v)


func _wire_editor() -> void:
	%OpenFanButton.pressed.connect(_open_fan_scene)


## The outbound half of the editor round-trip: open the benched fan scene in
## the 2D editor. The fan scene carries the inbound half — its own
## "◈ Open in Sandbox" inspector button (see FanAnchorDriver).
func _open_fan_scene() -> void:
	if not Engine.is_editor_hint():
		return
	Engine.get_singleton(&"EditorInterface").open_scene_from_path(_FAN_SCENE_PATH)
	Engine.get_singleton(&"EditorInterface").set_main_screen_editor("2D")


# --- control sync ----------------------------------------------------------------

## Re-mirrors every control widget from the driver's actual state after any
## mutation (preset / fixture knob / participation toggle). Signals are
## blocked while writing so the echo doesn't re-fire the handler.
func _sync_controls() -> void:
	if _sandbox == null:
		return
	var fx: Dictionary = _sandbox.get_fixture_state()
	_apply_blocked(%OwnedCheck, "button_pressed", fx["owned"])
	_apply_blocked(%CoreCheck, "button_pressed", fx["core"])
	_apply_blocked(%FootprintCheck, "button_pressed", fx["footprint"])
	%AddonsSpin.set_value_no_signal(float(fx["addons"]))
	%EffectsSpin.set_value_no_signal(float(fx["effects"]))
	var part: Dictionary = _sandbox.get_participation()
	for m in part:
		var check: CheckButton = get_node_or_null("%Part" + String(m))
		if check != null:
			_apply_blocked(check, "button_pressed", bool(part[m]))


func _apply_blocked(control: Control, property: String, value: Variant) -> void:
	if control == null:
		return
	control.set_block_signals(true)
	control.set(property, value)
	control.set_block_signals(false)


## [SandboxLiveTab] loader contract — this panel takes no inspected resource.
func noop(_obj: Object) -> void:
	pass

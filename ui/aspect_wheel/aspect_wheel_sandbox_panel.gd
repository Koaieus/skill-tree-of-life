@tool
extends PanelContainer

## AspectWheel sandbox: three wheels bound to 2, 5 and 12 entries (rostered
## aspects first, demo hues past them), each with a disabled and a checked
## wedge once it has room. Sliders drive every wheel's knobs live; the log
## echoes the signals.

const _COUNTS: Array[int] = [2, 5, 12]

@onready var _wheels: Array[AspectWheel] = [%Wheel2, %Wheel5, %Wheel12]
@onready var _knobs: VBoxContainer = %Knobs
@onready var _log: Label = %Log


## Sandbox-host loader hook; the wheels are always the fixed fake sets.
func load_object(_obj: Object) -> void:
	_bind_all()


func _ready() -> void:
	for wheel in _wheels:
		wheel.hovered.connect(func(id: StringName) -> void: _say("hovered %s" % (String(id) if id != &"" else "(none)")))
		wheel.picked.connect(func(id: StringName) -> void: _say("picked %s" % id))
		wheel.dismissed.connect(func() -> void: _say("dismissed"))
	_build_knobs()
	_bind_all()


func _bind_all() -> void:
	for i in _wheels.size():
		_wheels[i].bind(_fake_entries(_COUNTS[i]))


func _fake_entries(n: int) -> Array[AspectWheelEntry]:
	var aspects: Array[Identity] = []
	var roster := IdentityRoster.shared()
	if roster != null:
		for identity in roster.identities:
			if identity.kind == Identity.Kind.ASPECT:
				aspects.append(identity)
	var out: Array[AspectWheelEntry] = []
	for i in n:
		var identity: Identity
		if i < aspects.size():
			identity = aspects[i]
		else:
			identity = Identity.new()
			identity.kind = Identity.Kind.ASPECT
			identity.noun = "Aspect %d" % i
			identity.id = StringName("demo_aspect_%d" % i)
			identity.tint = Color.from_hsv(float(i) / n, 0.65, 0.95)
		var entry := AspectWheelEntry.new(identity.id, identity, 1 + (i * 7) % 13)
		entry.hub_text = "%s ×%d" % [identity.noun, entry.value]
		out.append(entry)
	if n >= 2:
		out[1].disabled_reason = "Too little"
	if n >= 3:
		out[2].checked = true
	elif n >= 1:
		out[0].checked = true
	return out


func _build_knobs() -> void:
	for child in _knobs.get_children():
		child.queue_free()
	var first := _wheels[0]
	_knobs.add_child(_slider("radius px", 48, 200, 1, first.radius_px, &"radius_px"))
	_knobs.add_child(_slider("inner radius px", 0, 80, 1, first.inner_radius_px, &"inner_radius_px"))
	_knobs.add_child(_slider("wedge gap deg", 0, 15, 0.5, first.wedge_gap_deg, &"wedge_gap_deg"))
	_knobs.add_child(_slider("min fill", 0, 1, 0.01, first.min_fill, &"min_fill"))
	_knobs.add_child(_slider("badge px", 8, 48, 1, first.badge_px, &"badge_px"))
	_knobs.add_child(_slider("fill alpha", 0, 1, 0.01, first.fill_alpha, &"fill_alpha"))


func _slider(text: String, low: float, high: float, step: float, value: float, property: StringName) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 120
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.x = 140
	row.add_child(slider)
	var readout := Label.new()
	readout.text = str(value)
	row.add_child(readout)
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = str(v)
		for wheel in _wheels:
			wheel.set(property, v))
	return row


func _say(text: String) -> void:
	if _log != null:
		_log.text = text

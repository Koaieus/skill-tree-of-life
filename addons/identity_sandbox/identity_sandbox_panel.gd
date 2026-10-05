@tool
extends PanelContainer

## Identity-badge sandbox: every rostered [Identity] × {12, 24, 48 px} ×
## {icon, letter}, as the live [IdentityBadge] and as its white
## [method IdentityBadge.composite] tinted the way a consumer would. The knobs
## write straight into `badge_frames.tres` (Save persists them). An empty
## roster falls back to one demo identity per kind.

const _BADGE_SCENE := preload("res://ui/identity_badge/identity_badge.tscn")
const _SIZES: Array[int] = [12, 24, 48]

var _tier: Emissive.Tier = Emissive.Tier.LABEL

@onready var _grid: GridContainer = %Grid
@onready var _knobs: VBoxContainer = %Knobs
@onready var _source: Label = %Source


## Sandbox-host loader hook; the grid always shows the whole roster.
func load_object(_obj: Object) -> void:
	_rebuild()


func _ready() -> void:
	_build_knobs()
	_rebuild()


func _identities() -> Array[Identity]:
	var roster := IdentityRoster.shared()
	if roster != null and not roster.identities.is_empty():
		_source.text = "%d rostered identities" % roster.identities.size()
		return roster.identities
	_source.text = "Roster empty — showing one demo identity per kind"
	var demo: Array[Identity] = []
	var tints := [Color(0.45, 0.85, 0.3), Color(0.95, 0.45, 0.4), Color(0.4, 0.9, 0.6), Color(0.5, 0.6, 1.0), Color(0.9, 0.75, 0.4)]
	for kind: Identity.Kind in Identity.Kind.values():
		var identity := Identity.new()
		identity.kind = kind
		identity.noun = String(Identity.Kind.keys()[kind]).capitalize()
		identity.id = StringName("demo_%s" % identity.noun.to_lower())
		identity.tint = tints[kind % tints.size()]
		demo.append(identity)
	return demo


func _rebuild() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		child.queue_free()
	_grid.columns = 1 + _SIZES.size() * 3
	_grid.add_child(_header(""))
	for size_px in _SIZES:
		for what in ["icon", "letter", "composite"]:
			_grid.add_child(_header("%s %d" % [what, size_px]))
	for identity in _identities():
		var letter_only: Identity = identity.duplicate()
		letter_only.icon = null
		letter_only.id = StringName("%s#letter" % identity.id)
		_grid.add_child(_header("%s (%s)" % [identity.noun, Identity.Kind.keys()[identity.kind]]))
		for size_px in _SIZES:
			_grid.add_child(_badge(identity, size_px))
			_grid.add_child(_badge(letter_only, size_px))
			_grid.add_child(_composite(identity, size_px))


func _header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _badge(identity: Identity, size_px: int) -> Control:
	var badge: IdentityBadge = _BADGE_SCENE.instantiate()
	badge.size_px = size_px
	badge.emissive_tier = _tier
	badge.identity = identity
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return badge


func _composite(identity: Identity, size_px: int) -> Control:
	var rect := TextureRect.new()
	rect.texture = IdentityBadge.composite(identity, size_px)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	rect.modulate = Emissive.at(identity.tint, Emissive.stops(_tier))
	return rect


func _build_knobs() -> void:
	for child in _knobs.get_children():
		child.queue_free()
	var frames := BadgeFrames.shared()
	var tier := OptionButton.new()
	for name: String in Emissive.Tier.keys():
		tier.add_item(name)
	tier.selected = _tier
	tier.item_selected.connect(func(index: int) -> void:
		_tier = index as Emissive.Tier
		_rebuild())
	_knobs.add_child(_row("tier", tier))
	for kind: Identity.Kind in Identity.Kind.values():
		var frame := frames.frame_for(kind)
		if not frames.frames.has(kind):
			frames.frames[kind] = frame
		_knobs.add_child(_slider("%s sides" % Identity.Kind.keys()[kind], 3, 32, 1, frame.sides,
				func(v: float) -> void: frame.sides = int(v)))
		_knobs.add_child(_slider("%s rotation" % Identity.Kind.keys()[kind], -180, 180, 5, frame.rotation_deg,
				func(v: float) -> void: frame.rotation_deg = v))
	_knobs.add_child(_slider("stroke px", 0.5, 8, 0.5, frames.stroke_px, func(v: float) -> void: frames.stroke_px = v))
	_knobs.add_child(_slider("icon inset", 0, 0.45, 0.01, frames.icon_inset, func(v: float) -> void: frames.icon_inset = v))
	_knobs.add_child(_slider("letter embolden", 0, 2, 0.05, frames.letter_embolden, func(v: float) -> void: frames.letter_embolden = v))
	var save := Button.new()
	save.text = "Save badge_frames.tres"
	save.pressed.connect(func() -> void: ResourceSaver.save(frames, BadgeFrames.PATH))
	_knobs.add_child(save)


func _slider(text: String, low: float, high: float, step: float, value: float, apply: Callable) -> Control:
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.x = 140
	var readout := Label.new()
	readout.text = str(value)
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = str(v)
		apply.call(v)
		BadgeFrames.shared().emit_changed()
		IdentityBadge.clear_cache()
		_rebuild())
	var row := _row(text, slider)
	row.add_child(readout)
	return row


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 120
	row.add_child(label)
	row.add_child(control)
	return row

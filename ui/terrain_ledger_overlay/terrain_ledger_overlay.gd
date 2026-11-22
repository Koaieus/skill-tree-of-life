## Runtime debug overlay: [member toggle_key] (F4) toggles a per-element
## readout of a [TerrainLedger] — one [LinePlot] per element over the ledger's
## closed samples, and the open sample's numbers beside it.
##
## Wired by the level scene: `game_root.tscn` authors [member ledger] onto this
## HudRoot child. Reads the ledger only through its public API, and rebuilds
## every series wholesale from [method TerrainLedger.samples] on each closed
## sample — never accumulates its own history, so a ledger that clears
## underneath it (a snapshot restore) simply plots shorter.
##
## Hidden means zero cost: no reads, no redraws, the refresh clock stopped.
extends Control
class_name TerrainLedgerOverlay

## The flows plotted per element, in legend order. `from_opposite` is the
## other element's `onto_opposite` and `total` is a level, not a flow: both are
## numbers only.
const _FLOWS: Array[StringName] = [&"produced", &"effect", &"voided", &"decayed", &"onto_opposite"]
const _NUMBERS: Array[StringName] = [
	&"produced", &"effect", &"voided", &"decayed",
	&"onto_opposite", &"from_opposite", &"total",
]
const _OPPOSITE := {&"heat": &"cold", &"cold": &"heat"}

## The ledger read. Settable at runtime; rebinds its signal.
@export var ledger: TerrainLedger = null: set = _set_ledger
## Key that shows / hides the overlay (tentative, easy to change).
@export var toggle_key: Key = KEY_F4
## Element defs whose identity tint colours each row (Heat, Cold, Charge).
@export var heat_element: Element = null
@export var cold_element: Element = null
@export var charge_element: Element = null
## Line colour of the `voided` series (tentative).
@export var voided_color: Color = Color(0.62, 0.62, 0.66)
## Line colour of the `decayed` series (tentative).
@export var decayed_color: Color = Color(0.38, 0.38, 0.46)
## How far the `effect` series is lightened from the element tint (tentative).
@export_range(0.0, 1.0, 0.05) var effect_lighten: float = 0.45

@onready var _refresh: Timer = %Refresh
@onready var _plots: Dictionary = {
	&"heat": %HeatPlot, &"cold": %ColdPlot, &"charge": %ChargePlot,
}
@onready var _numbers: Dictionary = {
	&"heat": %HeatNumbers, &"cold": %ColdNumbers, &"charge": %ChargeNumbers,
}


func _ready() -> void:
	_refresh.timeout.connect(_redraw_numbers)
	visibility_changed.connect(_on_visibility_changed)
	_bind(ledger)
	_on_visibility_changed()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.keycode == toggle_key and key.pressed and not key.echo:
		visible = not visible
		get_viewport().set_input_as_handled()


func _set_ledger(value: TerrainLedger) -> void:
	if value == ledger:
		return
	if is_node_ready():
		_unbind(ledger)
	ledger = value
	if is_node_ready():
		_bind(ledger)
		if is_visible_in_tree():
			_rebuild()


func _bind(l: TerrainLedger) -> void:
	if l != null and not l.sample_closed.is_connected(_on_sample_closed):
		l.sample_closed.connect(_on_sample_closed)


func _unbind(l: TerrainLedger) -> void:
	if is_instance_valid(l) and l.sample_closed.is_connected(_on_sample_closed):
		l.sample_closed.disconnect(_on_sample_closed)


func _on_sample_closed(_sample: Dictionary) -> void:
	if is_visible_in_tree():
		_rebuild()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_rebuild()
		_refresh.start()
	else:
		_refresh.stop()


## Every plot's series from the closed samples, then the open numbers.
func _rebuild() -> void:
	if ledger == null:
		return
	var history := ledger.samples()
	for element: StringName in TerrainLedger.ELEMENTS:
		var flows := _flows_of(element)
		var series: Array[PackedFloat32Array] = []
		var colors := PackedColorArray()
		for field: StringName in flows:
			var line := PackedFloat32Array()
			line.resize(history.size())
			for i in history.size():
				line[i] = float(history[i][element][field])
			series.append(line)
			colors.append(_color_of(element, field))
		(_plots[element] as LinePlot).set_series(series, colors)
	_redraw_numbers()


## The open sample's numbers, each tinted with its series colour as a legend.
func _redraw_numbers() -> void:
	if ledger == null:
		return
	var cur := ledger.current()
	for element: StringName in TerrainLedger.ELEMENTS:
		var row: Dictionary = cur.get(element, {})
		var lines: PackedStringArray = ["[b][color=#%s]%s[/color][/b]" % [
				_tint_of(element).to_html(false), _noun_of(element)]]
		for field: StringName in _NUMBERS:
			if not _OPPOSITE.has(element) and field in [&"onto_opposite", &"from_opposite"]:
				continue
			lines.append("[color=#%s]%s[/color] %d" % [
					_color_of(element, field).to_html(false), _label_of(element, field),
					int(row.get(field, 0))])
		(_numbers[element] as RichTextLabel).text = "\n".join(lines)


func _flows_of(element: StringName) -> Array[StringName]:
	if _OPPOSITE.has(element):
		return _FLOWS
	var out: Array[StringName] = []
	for f in _FLOWS:
		if f != &"onto_opposite":
			out.append(f)
	return out


func _color_of(element: StringName, field: StringName) -> Color:
	match field:
		&"produced":
			return _tint_of(element)
		&"effect":
			return _tint_of(element).lightened(effect_lighten)
		&"voided":
			return voided_color
		&"decayed":
			return decayed_color
		&"onto_opposite", &"from_opposite":
			return _tint_of(_OPPOSITE.get(element, element))
	return Color.WHITE


func _label_of(element: StringName, field: StringName) -> String:
	match field:
		&"onto_opposite":
			return "onto %s" % _noun_of(_OPPOSITE[element])
		&"from_opposite":
			return "from %s" % _noun_of(_OPPOSITE[element])
	return String(field)


func _element_of(element: StringName) -> Element:
	match element:
		&"heat":
			return heat_element
		&"cold":
			return cold_element
	return charge_element


func _tint_of(element: StringName) -> Color:
	var def := _element_of(element)
	return def.identity.tint if def != null and def.identity != null else Color.WHITE


func _noun_of(element: StringName) -> String:
	return String(element).capitalize()

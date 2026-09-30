@tool
class_name FuseScrubber
extends HBoxContainer
## The melee fuse scrubber: a track over the swing's hot window with one marker
## per [method MeleeAttackPlan.fusable_gates] entry.
##
## The plan is the ONLY store of fuse times — this control holds nothing but UI
## state (which markers are split off, which one was dragged last, which is
## hovered) and writes times solely through the plan's fuse setters. Markers
## are linked by default: one drag moves every linked marker. An alt-drag
## splits the grabbed marker off so it moves alone; [method relink] rejoins
## them, snapping every marker to the last one dragged.
##
## Every write is bracketed by [method is_editing] and followed by one
## [signal edited], so an owner resolving the prediction on refresh resolves
## once per gesture step, not once per gate written.

## One gesture step's writes have landed on the plan.
signal edited
## The cursor entered ([param hovering]) or left a marker.
signal marker_hovered(gate: Gate, hovering: bool)

## Pixels either side of a marker that still grab it.
@export_range(2.0, 24.0) var marker_grab_px := 8.0:
	set(v):
		marker_grab_px = v
		_redraw()
## Marker tick width, px.
@export_range(1.0, 8.0) var marker_width := 3.0:
	set(v):
		marker_width = v
		_redraw()
@export var track_color := Color(0.25, 0.28, 0.36, 0.8):
	set(v):
		track_color = v
		_redraw()
@export var linked_color := Color(0.95, 0.62, 0.3, 1.0):
	set(v):
		linked_color = v
		_redraw()
@export var split_color := Color(0.55, 0.8, 0.95, 1.0):
	set(v):
		split_color = v
		_redraw()
## An unfused marker sits greyed at the track's start.
@export var unarmed_color := Color(0.6, 0.62, 0.7, 0.45):
	set(v):
		unarmed_color = v
		_redraw()

@onready var _track: Control = %Track
@onready var _link_button: Button = %LinkButton
@onready var _clear_button: Button = %ClearButton
@onready var _chip: Label = %Chip

var plan: MeleeAttackPlan = null
var _gates: Array[Gate] = []
## Gates split off the linked group — moved alone.
var _split: Dictionary[Gate, bool] = {}
## The last marker dragged — what [method relink] snaps to.
var _anchor: Gate = null
var _hovered: Gate = null
var _dragging := false
var _drag_gate: Gate = null
var _editing := false
var _stranded_count := 0


func _ready() -> void:
	_track.draw.connect(_draw_track)
	_track.gui_input.connect(_on_track_input)
	_track.mouse_exited.connect(_set_hovered.bind(null))
	_link_button.pressed.connect(relink)
	_clear_button.pressed.connect(clear)
	visible = false


## Mirror [param p]'s fusable gates and times. Hidden when there is none.
func sync(p: MeleeAttackPlan) -> void:
	plan = p
	_gates = p.fusable_gates() if p != null else ([] as Array[Gate])
	for g in _split.keys():
		if not _gates.has(g):
			_split.erase(g)
	if _anchor != null and not _gates.has(_anchor):
		_anchor = null
	if _hovered != null and not _gates.has(_hovered):
		_set_hovered(null)
	visible = not _gates.is_empty()
	if not is_node_ready():
		return
	_link_button.disabled = _split.is_empty()
	_clear_button.disabled = p == null or p.gate_fuses().is_empty()
	_redraw()


## True while this control is mid-write on the plan.
func is_editing() -> bool:
	return _editing


## The marker the cursor is over, or null.
func hovered_gate() -> Gate:
	return _hovered


## Is [param gate]'s marker split off the linked group?
func is_split(gate: Gate) -> bool:
	return _split.has(gate)


## Move [param gate]'s marker to [param t] (0..1 of the hot window). A split
## marker moves alone; a linked one (or null, "the linked group") moves every
## linked marker. [param split] splits [param gate] off first.
func drag(gate: Gate, t: float, split := false) -> void:
	if plan == null:
		return
	if gate != null and split:
		_split[gate] = true
	if gate != null:
		_anchor = gate
	_editing = true
	if gate != null and _split.has(gate):
		plan.set_gate_fuse(gate, t)
	elif _split.is_empty():
		plan.set_all_gate_fuses(t)
	else:
		for g in _gates:
			if not _split.has(g):
				plan.set_gate_fuse(g, t)
	_editing = false
	edited.emit()


## Rejoin every marker, snapping them to the last one dragged.
func relink() -> void:
	if plan == null:
		return
	var t := plan.gate_fuse(_anchor) if _anchor != null else -1.0
	if t < 0.0:
		for g in _gates:
			t = maxf(t, plan.gate_fuse(g))
	_split.clear()
	_editing = true
	if t >= 0.0:
		plan.set_all_gate_fuses(t)
	_editing = false
	edited.emit()


## Fuse off: every gate unarmed, every marker relinked.
func clear() -> void:
	if plan == null:
		return
	_split.clear()
	_editing = true
	plan.clear_gate_fuses()
	_editing = false
	edited.emit()


## The warning chip: how many nodes the fused swing is predicted to strand.
func show_stranded(count: int) -> void:
	_stranded_count = count
	if not is_node_ready():
		return
	_chip.visible = count > 0
	_chip.text = "⚠ strands %d" % count
	_chip.tooltip_text = "Launching this swing deallocates the %d highlighted node(s)." % count


func stranded_count() -> int:
	return _stranded_count


# ── Track ────────────────────────────────────────────────────────────────────

func _redraw() -> void:
	if is_node_ready():
		_track.queue_redraw()


func _marker_x(gate: Gate) -> float:
	var t := plan.gate_fuse(gate) if plan != null else -1.0
	return clampf(t, 0.0, 1.0) * _track.size.x


func _t_at(x: float) -> float:
	return clampf(x / maxf(_track.size.x, 1.0), 0.0, 1.0)


## The marker nearest [param x] within [member marker_grab_px], or null.
## Split markers win a tie — they sit on top.
func _marker_at(x: float) -> Gate:
	var best: Gate = null
	var best_d := marker_grab_px
	for g in _gates:
		var d := absf(_marker_x(g) - x)
		if d < best_d or (d == best_d and _split.has(g)):
			best = g
			best_d = d
	return best


func _draw_track() -> void:
	var h := _track.size.y
	var w := _track.size.x
	_track.draw_rect(Rect2(0.0, h * 0.35, w, h * 0.3), track_color)
	# Linked first, split on top; the hovered marker last and widest.
	var order: Array[Gate] = []
	for g in _gates:
		if not _split.has(g):
			order.append(g)
	for g in _gates:
		if _split.has(g):
			order.append(g)
	if _hovered != null and order.has(_hovered):
		order.erase(_hovered)
		order.append(_hovered)
	for g in order:
		var armed := plan != null and plan.gate_fuse(g) >= 0.0
		var color := (split_color if _split.has(g) else linked_color) if armed else unarmed_color
		var mw := marker_width * (2.0 if g == _hovered else 1.0)
		_track.draw_rect(Rect2(_marker_x(g) - mw * 0.5, 0.0, mw, h), color)


func _on_track_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_dragging = true
			_drag_gate = _marker_at(mb.position.x)
			drag(_drag_gate, _t_at(mb.position.x), mb.alt_pressed and _drag_gate != null)
		else:
			_dragging = false
			_drag_gate = null
		_track.accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm == null:
		return
	if _dragging:
		drag(_drag_gate, _t_at(mm.position.x))
		_track.accept_event()
	else:
		_set_hovered(_marker_at(mm.position.x))


func _set_hovered(gate: Gate) -> void:
	if gate == _hovered:
		return
	var prev := _hovered
	_hovered = gate
	if prev != null:
		marker_hovered.emit(prev, false)
	if gate != null:
		marker_hovered.emit(gate, true)
	_redraw()

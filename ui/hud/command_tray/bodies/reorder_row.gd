@tool
class_name ReorderRow
extends Container
## A horizontal row whose children the player drags into a new order. The row
## owns each child's SLOT (left to right in child order, visible children only)
## and tweens children to their slots: neighbours slide aside live as the
## dragged child's centre crosses their slot midpoints, the dragged child
## follows the cursor 1:1 and is lifted, and a drop settles it into its slot.
##
## The order is committed at the drop event — [signal order_changed] fires
## synchronously there, never on settle completion — and only when it differs
## from the order at the press. A child's key is its `reorder_key` meta, else
## its name. No `_process` ever: motion is tweens plus the dragged child's own
## mouse events, so nothing runs at rest.
##
## Godot's `_get_drag_data` is not used: its preview cannot animate neighbours.
## Drag input arrives through each child's `gui_input` (the pressed child keeps
## the mouse until release); [method begin_drag] / [method drag_to] /
## [method end_drag] / [method cancel_drag] are the public seam that handler
## drives, and what tests drive.

signal order_changed(ids: Array[StringName])

## Seconds a child takes to slide to its slot (ease-out cubic).
@export_range(0.0, 1.0, 0.01) var settle_secs := 0.18
## Scale of the dragged child while held.
@export_range(1.0, 1.5, 0.01) var lift_scale := 1.05
## Seconds the lift (scale up) takes.
@export_range(0.0, 0.5, 0.01) var lift_secs := 0.08
## Cursor travel, in px, before a press becomes a drag (a shorter press is a click).
@export_range(0.0, 32.0, 1.0) var drag_threshold_px := 6.0
## Gap between slots.
@export_range(0, 64, 1) var separation := 8:
	set = _set_separation

var _tween_of: Dictionary = {}  # Control -> Tween
var _target_of: Dictionary = {}  # Control -> Vector2
var _dragged: Control = null
var _grab_offset := 0.0
var _press_order: Array[Control] = []
var _pressed: Control = null
var _press_x := 0.0


func _init() -> void:
	child_entered_tree.connect(_on_child_entered)
	child_exiting_tree.connect(_on_child_exiting)


func _ready() -> void:
	set_process_unhandled_key_input(false)
	for c in get_children():
		_on_child_entered(c)


func _set_separation(v: int) -> void:
	separation = v
	update_minimum_size()
	queue_sort()


# --- slots -------------------------------------------------------------------

## The visible Control children in slot (child) order.
func items() -> Array[Control]:
	var out: Array[Control] = []
	for c in get_children():
		if c is Control and (c as Control).visible and not (c as Control).top_level:
			out.append(c)
	return out


## The children's keys in slot order.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for c in items():
		out.append(key_of(c))
	return out


static func key_of(c: Node) -> StringName:
	if c.has_meta(&"reorder_key"):
		return StringName(c.get_meta(&"reorder_key"))
	return StringName(c.name)


## Every visible child's slot position, by child.
func _slots() -> Dictionary:
	var out := {}
	var x := 0.0
	for c in items():
		out[c] = Vector2(x, 0.0)
		x += c.get_combined_minimum_size().x + separation
	return out


func _get_minimum_size() -> Vector2:
	var w := 0.0
	var h := 0.0
	var list := items()
	for c in list:
		var m := c.get_combined_minimum_size()
		w += m.x
		h = maxf(h, m.y)
	if list.size() > 1:
		w += separation * (list.size() - 1)
	return Vector2(w, h)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_SORT_CHILDREN:
			_relayout(false)
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			cancel_drag()


## Sizes every child and puts it on its slot. A child already gliding is
## retargeted from where it is (never snapped); with [param animate], a child
## whose slot moved glides there; the dragged child keeps the cursor's x.
func _relayout(animate: bool) -> void:
	var slots := _slots()
	for c: Control in slots:
		c.size = Vector2(c.get_combined_minimum_size().x, size.y)
		if c == _dragged:
			continue
		var to: Vector2 = slots[c]
		if _is_gliding(c):
			if _target_of.get(c, to) != to:
				_glide(c, to)
		elif animate and c.position != to:
			_glide(c, to)
		else:
			c.position = to
			_target_of[c] = to


func _is_gliding(c: Control) -> bool:
	var tw: Tween = _tween_of.get(c)
	return tw != null and tw.is_valid() and tw.is_running()


func _kill(c: Control) -> void:
	var tw: Tween = _tween_of.get(c)
	if tw != null and tw.is_valid():
		tw.kill()
	_tween_of.erase(c)


func _glide(c: Control, to: Vector2) -> Tween:
	_kill(c)
	_target_of[c] = to
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "position", to, settle_secs)
	tw.finished.connect(_on_glide_finished.bind(c, tw))
	_tween_of[c] = tw
	return tw


func _on_glide_finished(c: Control, tw: Tween) -> void:
	if _tween_of.get(c) == tw:
		_tween_of.erase(c)
		if c != _dragged:
			c.z_index = 0


## Whether any child is mid-glide.
func is_animating() -> bool:
	for c in _tween_of:
		if is_instance_valid(c) and _is_gliding(c):
			return true
	return false


func is_dragging() -> bool:
	return _dragged != null


# --- order -------------------------------------------------------------------

## Puts the children in [param order] (keys; children it misses keep their
## relative order after it). A no-op when already in that order — no tween,
## no sort — and ignored mid-drag (the drop re-emits the order). [param
## animate] glides the moved children; otherwise everything snaps.
func set_order(order: Array[StringName], animate: bool) -> void:
	if _dragged != null or order == ids():
		return
	var by_key := {}
	for c in items():
		by_key[key_of(c)] = c
	var ordered: Array[Control] = []
	for id in order:
		if by_key.has(id):
			ordered.append(by_key[id])
			by_key.erase(id)
	for c in items():
		if not ordered.has(c):
			ordered.append(c)
	for c in ordered:
		move_child(c, -1)
	if not animate:
		for c in _tween_of.keys():
			_kill(c)
	_relayout(animate)


# --- drag ---------------------------------------------------------------------

## Lifts [param card], grabbed at row-local [param local_x].
func begin_drag(card: Control, local_x: float) -> void:
	if _dragged != null:
		cancel_drag()
	if not items().has(card):
		return
	_press_order = items()
	_dragged = card
	_kill(card)
	_grab_offset = local_x - card.position.x
	card.z_index = 1
	card.pivot_offset = card.size * 0.5
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale", Vector2.ONE * lift_scale, lift_secs)
	_tween_of[card] = tw
	set_process_unhandled_key_input(true)


## Moves the held card with the cursor (1:1) and slides neighbours aside as its
## centre crosses their slot midpoints.
func drag_to(local_x: float) -> void:
	if _dragged == null:
		return
	_dragged.position.x = local_x - _grab_offset
	var centre := _dragged.position.x + _dragged.size.x * 0.5
	var moved := false
	# Slot midpoints in the CURRENT order: a swap moves the neighbour's slot by
	# the held card's width, so the two thresholds never meet — no flicker.
	while true:
		var list := items()
		var i := list.find(_dragged)
		var slots := _slots()
		if i + 1 < list.size() and centre > _slot_mid(list[i + 1], slots):
			move_child(_dragged, list[i + 1].get_index())
		elif i > 0 and centre < _slot_mid(list[i - 1], slots):
			move_child(_dragged, list[i - 1].get_index())
		else:
			break
		moved = true
	if moved:
		_relayout(true)


func _slot_mid(c: Control, slots: Dictionary) -> float:
	return (slots[c] as Vector2).x + c.get_combined_minimum_size().x * 0.5


## Drops the held card: the order is committed now, then it settles.
func end_drag() -> void:
	if _dragged == null:
		return
	var card := _dragged
	var changed := items() != _press_order
	_release(card)
	if changed:
		order_changed.emit(ids())


## Puts every child back where the press found it; nothing is emitted.
func cancel_drag() -> void:
	if _dragged == null:
		return
	var card := _dragged
	for c in _press_order:
		if is_instance_valid(c) and c.get_parent() == self:
			move_child(c, -1)
	_release(card)


func _release(card: Control) -> void:
	_dragged = null
	_pressed = null
	_press_order.clear()
	set_process_unhandled_key_input(false)
	_relayout(true)
	var to: Vector2 = _slots().get(card, card.position)
	_kill(card)
	_target_of[card] = to
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "position", to, settle_secs)
	tw.tween_property(card, "scale", Vector2.ONE, settle_secs)
	tw.finished.connect(_on_glide_finished.bind(card, tw))
	_tween_of[card] = tw


func _unhandled_key_input(event: InputEvent) -> void:
	if _dragged != null and event.is_action_pressed(&"ui_cancel"):
		cancel_drag()
		get_viewport().set_input_as_handled()


# --- child input ----------------------------------------------------------------

func _on_child_entered(n: Node) -> void:
	if _dragged != null:
		cancel_drag()
	if n is Control:
		var cb := _on_child_input.bind(n)
		if not (n as Control).gui_input.is_connected(cb):
			(n as Control).gui_input.connect(cb)


func _on_child_exiting(n: Node) -> void:
	if n == _dragged or _press_order.has(n):
		cancel_drag()
	if n is Control:
		var cb := _on_child_input.bind(n)
		if (n as Control).gui_input.is_connected(cb):
			(n as Control).gui_input.disconnect(cb)
		_kill(n as Control)
		_target_of.erase(n)
	if n == _pressed:
		_pressed = null


func _on_child_input(event: InputEvent, child: Control) -> void:
	if Engine.is_editor_hint():
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_pressed = child
			_press_x = get_local_mouse_position().x
		else:
			if _dragged == child:
				end_drag()
				child.accept_event()
			_pressed = null
		return
	if event is InputEventMouseMotion and _pressed == child:
		var x := get_local_mouse_position().x
		if _dragged == null and absf(x - _press_x) >= drag_threshold_px:
			begin_drag(child, _press_x)
		if _dragged == child:
			drag_to(x)
			child.accept_event()

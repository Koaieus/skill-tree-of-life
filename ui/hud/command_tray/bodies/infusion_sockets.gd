@tool
class_name InfusionSockets
extends Control

## The cast's infusion sockets, fanned along an arc that hugs the vessel's
## bottom edge: one [InfusionSocket] per `infusion_slots` the caster owns, in
## the plan's socket order ([member Infusion.points]' insertion order, compact),
## plus one locked ghost for the next tier labelled with its INT threshold
## ([method EntityStatBoard.next_threshold]); none at the cap.
##
## Left-click on a socket is [method MagicMode.toggle_socket]; right-click on a
## filled one is `set_socket(i, &"")`. The [AspectWheel] (%Wheel) floats
## `top_level`, centred on the open socket, outside this control's rect and
## minimum size. The STACK decides its visibility — shown iff an
## [InfusionPickMode] is on the branch, repainted on [signal ArmedStack.changed]
## — so every close path (a pick, Esc, right-click, a launch, a graph click)
## hides it for free. Its `picked` is [method InfusionPickMode.pick] (an
## aspect pick closes it; an element pick keeps it open, its wedges rebound to
## the new counts); its `dismissed` pops the mode.
##
## Flanking the arc stand the forge's two element sockets — %ShapeSocket (the
## crystal) left of it, %RideSocket right of it, so the arc keeps its centre
## under the vessel. Neither is an aspect socket —
## not in [method socket_count], reached as [method socket] of
## [constant InfusionChoices.SHAPE_SOCKET] / [constant InfusionChoices.RIDE_SOCKET]
## — so both take a pick at 0 `infusion_slots` and with every aspect socket full.
## Each shows its field ([method Infusion.shape_of] / [method Infusion.ride_of]):
## the forged points over the element's count, or "innate" for the spell's
## authored default.
##
## Positioned children report no minimum size, so [method _get_minimum_size]
## is the arc's bounding box.

## A locked ghost was tapped; [param threshold_line] is its unlock label ("INT 100").
signal locked_tapped(threshold_line: String)

## Edge of each socket's ring. Tentative.
@export_range(16, 96, 1, "suffix:px") var socket_px: int = 44:
	set(v):
		socket_px = v
		_layout()
## The arc the sockets fan along, in degrees. Tentative.
@export_range(0.0, 180.0, 1.0, "suffix:°") var socket_arc_deg: float = 100.0:
	set(v):
		socket_arc_deg = v
		_layout()
## Radius of that arc. Tentative.
@export_range(40.0, 400.0, 1.0, "suffix:px") var arc_radius_px: float = 90.0:
	set(v):
		arc_radius_px = v
		_layout()
## Width each socket's slot reserves, so neighbouring exchange lines don't
## collide. Tentative.
@export_range(16, 160, 1, "suffix:px") var slot_width_px: int = 76:
	set(v):
		slot_width_px = v
		_layout()
## Socket 0 at the arc's right end, the ghost at its left. The crucible's
## readout lists socket 0's line topmost and its traces run down then right,
## so the rightmost socket must feed the top line or the traces cross.
@export var right_to_left := true:
	set(v):
		right_to_left = v
		_layout()

## Edge of the shape and the ride sockets' rings (one size for both). Tentative.
@export_range(16, 96, 1, "suffix:px") var element_socket_px: int = 44:
	set(v):
		element_socket_px = v
		_layout()
## Width each element socket's slot reserves — its line is short ("2/3",
## "innate"), so narrower than [member slot_width_px]. Tentative.
@export_range(16, 160, 1, "suffix:px") var element_slot_px: int = 48:
	set(v):
		element_slot_px = v
		_layout()
## Gap between the arc's end and the element sockets. Tentative.
@export_range(0, 64, 1, "suffix:px") var element_gap_px: int = 8:
	set(v):
		element_gap_px = v
		_layout()

const _SOCKET_SCENE := preload("res://ui/hud/command_tray/bodies/infusion_socket.tscn")
const _NO_ASPECTS_HINT := "no aspects held"
const _SLOTS_STAT := &"infusion_slots"

@onready var _wheel: AspectWheel = %Wheel
@onready var _shape_socket: InfusionSocket = %ShapeSocket
@onready var _ride_socket: InfusionSocket = %RideSocket

var _plan: MagicAttackPlan = null
var _stack: ArmedStack = null
var _sockets: Array[InfusionSocket] = []
var _owned: int = 0
var _ghost: String = ""


func _ready() -> void:
	_wheel.visible = false
	_wheel.picked.connect(_on_wheel_picked)
	_wheel.dismissed.connect(_on_wheel_dismissed)
	_shape_socket.index = InfusionChoices.SHAPE_SOCKET
	_ride_socket.index = InfusionChoices.RIDE_SOCKET
	for s in [_shape_socket, _ride_socket]:
		s.toggled.connect(_on_socket_toggled)
		s.cleared.connect(_on_socket_cleared)
	_refresh()


## Show and drive [param plan]'s sockets; the choosers open on [param stack]
## (none: the sockets show, but clicks open nothing). Null unbinds. Re-binding
## the bound pair is free — the tray re-binds on every hover.
func bind(plan: MagicAttackPlan, stack: ArmedStack = null) -> void:
	if plan == _plan and stack == _stack:
		return
	if plan != _plan:
		if _plan != null and _plan.state_changed.is_connected(_refresh):
			_plan.state_changed.disconnect(_refresh)
		_plan = plan
		if _plan != null:
			_plan.state_changed.connect(_refresh)
	if stack != _stack:
		if _stack != null and _stack.changed.is_connected(_repaint_wheel):
			_stack.changed.disconnect(_repaint_wheel)
		_stack = stack
		if _stack != null:
			_stack.changed.connect(_repaint_wheel)
	_refresh()
	_repaint_wheel()


## Owned sockets (the ghost excluded).
func socket_count() -> int:
	return _owned


## The ghost's label, "" when there is none.
func ghost_text() -> String:
	return _ghost


## Socket [param i]; the ghost, when shown, is index [method socket_count];
## [constant InfusionChoices.SHAPE_SOCKET] / [constant InfusionChoices.RIDE_SOCKET]
## are the element sockets.
func socket(i: int) -> InfusionSocket:
	match i:
		InfusionChoices.SHAPE_SOCKET:
			return _shape_socket
		InfusionChoices.RIDE_SOCKET:
			return _ride_socket
	return _sockets[i] if i >= 0 and i < _sockets.size() else null


func wheel() -> AspectWheel:
	return _wheel


func _caster() -> Entity:
	return _plan.attacker if _plan != null else null


func _refresh() -> void:
	if not is_node_ready():
		return
	var caster := _caster()
	visible = _plan != null and _plan.spell != null and caster != null
	_owned = AspectCurrency.cap_of(caster, _SLOTS_STAT) if visible else 0
	_ghost = ""
	if visible and caster.stat_board != null:
		var next := caster.stat_board.next_threshold(_SLOTS_STAT)
		if not is_inf(next):
			_ghost = "INT %d" % int(next)
	var count := _owned + (0 if _ghost.is_empty() else 1)
	if count != _sockets.size():
		_rebuild(count)
	if not visible:
		return
	_show_field(_shape_socket, _plan.infusion.shape_of(_plan.spell), _plan.infusion.shape_element,
			_plan.infusion.shape_points)
	_show_field(_ride_socket, _plan.infusion.ride_of(_plan.spell), _plan.infusion.ride_element,
			_plan.infusion.ride_points)
	var order := _plan.infusion.points.keys()
	for i in _owned:
		var s := _sockets[i]
		if i < order.size():
			var id: StringName = order[i]
			var pts: int = _plan.infusion.points[id]
			var aspect := AspectRoster.shared().by_id(id)
			s.show_filled(aspect.identity if aspect != null else null, pts,
					AspectCurrency.cap_of(caster, AspectCurrency.stat_of(id)),
					InfusionExchange.line(_plan.spell, id, pts))
		else:
			s.show_empty()
	if not _ghost.is_empty():
		_sockets[_owned].show_locked(_ghost)
	_mark_open()


## Paint element socket [param s] showing [param shown] — forged as
## [param forged_id] × [param points] when those name it, else the default.
func _show_field(s: InfusionSocket, shown: StringName, forged_id: StringName, points: int) -> void:
	var element := ElementRoster.shared().by_id(shown)
	if element == null:
		s.show_empty()
		return
	var held := AspectCurrency.cap_of(_caster(), element.stat.id)
	var forged := points > 0 and forged_id == shown
	s.show_filled(element.identity, points if forged else 0, held,
			"%d/%d" % [points, held] if forged else "innate")


func _rebuild(count: int) -> void:
	for s in _sockets:
		s.queue_free()
	_sockets.clear()
	for i in count:
		var s: InfusionSocket = _SOCKET_SCENE.instantiate()
		s.name = "Socket%d" % i
		s.index = i
		s.toggled.connect(_on_socket_toggled)
		s.cleared.connect(_on_socket_cleared)
		s.locked_tapped.connect(_on_socket_locked_tapped)
		add_child(s)
		_sockets.append(s)
	_layout()


## Socket i at angle θ_i across [member socket_arc_deg] (mirrored by
## [member right_to_left]), measured from straight down off a centre
## [member arc_radius_px] above; the box is the arc's extent. A lone socket
## hangs at the apex, where a fan's middle socket would, on the vessel's rim.
func _layout() -> void:
	if not is_node_ready():
		return
	var n := _sockets.size()
	var element_w := maxi(element_slot_px, element_socket_px)
	var left := element_w + (element_gap_px if n > 0 else 0)
	var half := deg_to_rad(socket_arc_deg) * 0.5
	var slot := Vector2(maxi(slot_width_px, socket_px), 0.0)
	for i in n:
		var s := _sockets[i]
		s.socket_px = socket_px
		slot.y = s.get_combined_minimum_size().y
		var t := float(i) / (n - 1) if n > 1 else 0.5
		var theta := lerpf(-half, half, 1.0 - t if right_to_left else t) if n > 1 else 0.0
		var x := arc_radius_px * (sin(theta) + sin(half)) if n > 1 else 0.0
		var y := arc_radius_px * (cos(theta) - cos(half))
		s.size = slot
		s.position = Vector2(left + x, y)
	for s in [_shape_socket, _ride_socket]:
		s.socket_px = element_socket_px
		s.size = Vector2(element_w, s.get_combined_minimum_size().y)
	_shape_socket.position = Vector2.ZERO
	_ride_socket.position = Vector2(left + _arc_width() + (element_gap_px if n > 0 else 0), 0.0)
	update_minimum_size()
	if _wheel.visible:
		_place_wheel()


## The aspect arc's width alone; 0 with no aspect socket.
func _arc_width() -> float:
	if _sockets.is_empty():
		return 0.0
	var half := deg_to_rad(socket_arc_deg) * 0.5
	var span := 2.0 * arc_radius_px * sin(half) if _sockets.size() > 1 else 0.0
	return span + maxi(slot_width_px, socket_px)


func _get_minimum_size() -> Vector2:
	if not is_node_ready():
		return Vector2.ZERO
	var element_w := 2 * maxi(element_slot_px, element_socket_px)
	var element_h := _ride_socket.get_combined_minimum_size().y
	if _sockets.is_empty():
		return Vector2(element_w, element_h)
	var half := deg_to_rad(socket_arc_deg) * 0.5
	var slot_h := _sockets[0].get_combined_minimum_size().y
	return Vector2(_arc_width() + 2 * element_gap_px + element_w,
			maxf(arc_radius_px * (1.0 - cos(half)) + slot_h, element_h))


func _open() -> InfusionPickMode:
	return _stack.find(InfusionPickMode) as InfusionPickMode if _stack != null else null


## Shown iff the stack holds an [InfusionPickMode] for one of these sockets. On
## [signal ArmedStack.changed] only — never on every plan hover.
func _repaint_wheel() -> void:
	if not is_node_ready():
		return
	var open := _open()
	var shown := open != null and _plan != null and socket(open.socket) != null
	_wheel.visible = shown
	if shown:
		_wheel.bind(InfusionChoices.entries(_plan, open.socket))
		_wheel.size = _wheel.get_combined_minimum_size()
		_place_wheel()
	_mark_open()


## Centred on the open socket, then slid to stay inside the viewport: the tray
## is bottom-anchored, so a centred wheel would lose its lower wedges off-screen.
func _place_wheel() -> void:
	var open := _open()
	var s := socket(open.socket) if open != null else null
	if s == null:
		return
	var centre := s.global_position + Vector2(s.size.x * 0.5, s.socket_px * 0.5)
	var at := centre - _wheel.size * 0.5
	var limit := get_viewport().get_visible_rect()
	at.x = clampf(at.x, limit.position.x, limit.end.x - _wheel.size.x)
	at.y = clampf(at.y, limit.position.y, limit.end.y - _wheel.size.y)
	_wheel.global_position = at


func _mark_open() -> void:
	var open := _open()
	for s in _sockets + [_shape_socket, _ride_socket]:
		s.is_open = open != null and open.socket == s.index


## A socket with nothing to offer opens no chooser: it says so instead.
func _on_socket_toggled(index: int) -> void:
	if index >= 0 and _plan != null and not InfusionChoices.entries(_plan, index).any(
			func(e: AspectWheelEntry) -> bool: return ElementRoster.shared().by_id(e.id) == null):
		_sockets[index].flash_hint(_NO_ASPECTS_HINT)
		return
	var magic := _stack.find(MagicMode) as MagicMode if _stack != null else null
	if magic != null:
		magic.toggle_socket(index)


func _on_socket_locked_tapped(index: int) -> void:
	locked_tapped.emit(_sockets[index].line_text())


func _on_socket_cleared(index: int) -> void:
	if _plan == null:
		return
	match index:
		InfusionChoices.SHAPE_SOCKET:
			_plan.set_shape(&"", 0)
			_rebind_open_field()
		InfusionChoices.RIDE_SOCKET:
			_plan.set_ride(&"", 0)
			_rebind_open_field()
		_:
			_plan.set_socket(index, &"")


func _on_wheel_picked(id: StringName) -> void:
	var open := _open()
	if open != null:
		open.pick(id)
	_rebind_open_field()


## An element chooser stays open across its picks and clears: rebind its
## wedges to the counts the write left.
func _rebind_open_field() -> void:
	var open := _open()
	if open != null and open.socket < 0 and _wheel.visible and _plan != null:
		_wheel.bind(InfusionChoices.entries(_plan, open.socket))


func _on_wheel_dismissed() -> void:
	var open := _open()
	if open != null:
		open.pop_self()

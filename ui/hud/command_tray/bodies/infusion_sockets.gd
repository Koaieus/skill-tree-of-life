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
## hides it for free. Its `picked` is [method InfusionPickMode.pick]; its
## `dismissed` pops the mode.
##
## Positioned children report no minimum size, so [method _get_minimum_size]
## is the arc's bounding box.

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

const _SOCKET_SCENE := preload("res://ui/hud/command_tray/bodies/infusion_socket.tscn")
const _SLOTS_STAT := &"infusion_slots"

@onready var _wheel: AspectWheel = %Wheel

var _plan: MagicAttackPlan = null
var _stack: ArmedStack = null
var _sockets: Array[InfusionSocket] = []
var _owned: int = 0
var _ghost: String = ""


func _ready() -> void:
	_wheel.visible = false
	_wheel.picked.connect(_on_wheel_picked)
	_wheel.dismissed.connect(_on_wheel_dismissed)
	_refresh()


## Show and drive [param plan]'s sockets; the choosers open on [param stack]
## (none: the sockets show, but clicks open nothing). Null unbinds.
func bind(plan: MagicAttackPlan, stack: ArmedStack = null) -> void:
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


## Socket [param i]; the ghost, when shown, is index [method socket_count].
func socket(i: int) -> InfusionSocket:
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
		add_child(s)
		_sockets.append(s)
	_layout()


## Socket i at angle θ_i across [member socket_arc_deg], measured from straight
## down off a centre [member arc_radius_px] above; the box is the arc's extent.
func _layout() -> void:
	if not is_node_ready():
		return
	var n := _sockets.size()
	var half := deg_to_rad(socket_arc_deg) * 0.5 if n > 1 else 0.0
	var slot := Vector2(maxi(slot_width_px, socket_px), 0.0)
	for i in n:
		var s := _sockets[i]
		s.socket_px = socket_px
		slot.y = s.get_combined_minimum_size().y
		var theta := lerpf(-half, half, float(i) / (n - 1)) if n > 1 else 0.0
		var x := arc_radius_px * (sin(theta) + sin(half))
		var y := arc_radius_px * (cos(theta) - cos(half))
		s.size = slot
		s.position = Vector2(x, y)
	update_minimum_size()
	if _wheel.visible:
		_place_wheel()


func _get_minimum_size() -> Vector2:
	if _sockets.is_empty():
		return Vector2.ZERO
	var half := deg_to_rad(socket_arc_deg) * 0.5 if _sockets.size() > 1 else 0.0
	var slot_h := _sockets[0].get_combined_minimum_size().y
	return Vector2(2.0 * arc_radius_px * sin(half) + maxi(slot_width_px, socket_px),
			arc_radius_px * (1.0 - cos(half)) + slot_h)


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


func _place_wheel() -> void:
	var open := _open()
	var s := socket(open.socket) if open != null else null
	if s == null:
		return
	var centre := s.global_position + Vector2(s.size.x * 0.5, socket_px * 0.5)
	_wheel.global_position = centre - _wheel.size * 0.5


func _mark_open() -> void:
	var open := _open()
	for s in _sockets:
		s.is_open = open != null and open.socket == s.index


func _on_socket_toggled(index: int) -> void:
	var magic := _stack.find(MagicMode) as MagicMode if _stack != null else null
	if magic != null:
		magic.toggle_socket(index)


func _on_socket_cleared(index: int) -> void:
	if _plan != null:
		_plan.set_socket(index, &"")


func _on_wheel_picked(id: StringName) -> void:
	var open := _open()
	if open != null:
		open.pick(id)


func _on_wheel_dismissed() -> void:
	var open := _open()
	if open != null:
		open.pop_self()

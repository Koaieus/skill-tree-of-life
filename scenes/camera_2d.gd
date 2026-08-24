class_name GraphCamera
extends Camera2D


@export_range(0, 1500, 1.0, 'or_greater') var pan_speed: float = 800.0

## How long one scroll step takes to settle. Short enough to stay responsive,
## long enough that anything tracking a canvas position (the tooltip fan, the
## floater toaster) glides instead of teleporting.
@export_range(0.0, 1.0, 0.01) var zoom_duration: float = 0.15
@export var zoom_step: float = 0.25

const MIN_ZOOM := 0.25
const MAX_ZOOM := 2.00

## The authoritative zoom the wheel accumulates into. `zoom` itself is only the
## tween's output and is fractional mid-flight — accumulating on it would read a
## half-applied value and silently drop steps during fast scrolling.
var _target_zoom: float = 1.0
var _zoom_tween: Tween = null

## Last-known zoom TARGET, mirrored via [signal Events.camera_zoom_changed]
## (#399). Static so a consumer with no live camera in its scene (bloom
## sandbox SubViewport, headless GUT fixtures) still reads a sane default
## instead of needing a tree lookup, and so an Edge spawned between zoom
## steps (procgen/`Graph.add_edge` at level load) sees the current value
## immediately rather than waiting for the next scroll tick.
static var current_zoom: float = 1.0

## Coalesces same-frame `_zoom_by` calls into one broadcast — a fast scroll
## burst (trackpad inertial scroll, a high-poll-rate wheel) can fire several
## wheel ticks inside a single rendered frame, and each broadcast is O(live
## Edge count) downstream. Same debounce shape as
## `VisionSystem._request_recompute` (`systems/vision_system.gd`).
var _zoom_broadcast_pending: bool = false

## Wheel-zoom floor, tighter than [constant MIN_ZOOM] when the level's own
## `limit_*` rect (GameRoot._apply_graph_bounds) is smaller than the viewport
## at [constant MIN_ZOOM] — e.g. a small hand-authored sandbox. Without this,
## Camera2D's limit clamp degenerates once the view rect exceeds the limit
## rect (the camera can't center inside a box smaller than what it's showing),
## so the fix is to stop the zoom-out before that point rather than grow the
## limit rect past the graph's actual footprint.
var _min_zoom_floor: float = MIN_ZOOM

## Raw world-space AABB of the level's SkillNodes (GameRoot._apply_graph_bounds,
## no margin) — [method set_graph_bounds] stores it and [method _update_limits]
## grows `limit_*` around it fresh every frame.
var _graph_bounds: Rect2 = Rect2()

## Pan slack in world units at zoom == 1.0, pushed by [method set_graph_bounds].
## [method _update_limits] divides this by the current zoom so the slack stays
## roughly constant in SCREEN space at any zoom, instead of a fixed world-space
## margin shrinking to nothing once the view is wide enough to swallow it —
## which was capping how far you could pan past the graph edge much sooner
## when zoomed out than when zoomed in.
var _pan_margin_base: float = 400.0

## Fires whenever [method _update_limits] recomputes a DIFFERENT effective
## bounds rect (not every frame — most frames are idle, and this exists so
## downstream consumers stay push-driven instead of polling). GameRoot
## forwards it onto the fog/aura overlays so they always paint the same
## zoom-scaled rect the pan limit uses, instead of a separately-computed one
## that drifts out of sync whenever the margin math here changes.
signal bounds_changed(bounds: Rect2)

## Fired the instant the player touches the camera — a middle-drag, a wheel
## tick, or a non-zero arrow-key vector — and always BEFORE the input is
## acted on (#523). [CameraDirector] listens and cancels any focus in flight
## synchronously, which is what makes the ordering load-bearing rather than
## stylistic: emitting after [method _zoom_by] would let the wheel accumulate
## onto the DIRECTOR's zoomed-out value, losing the player's own
## [member _target_zoom] and with it the 0.25 lattice.
##
## The camera implements no policy of its own here — grace windows and
## skip-if-on-screen live in the director.
signal manual_input_received

var _last_effective_bounds: Rect2 = Rect2()

## True between [method begin_directed_focus] and [method end_directed_focus].
## While set, [method _process] does not apply the arrow-key pan — a director
## Tween on `global_position` and a per-frame `+=` on the same property fight
## and jitter. The clamp still runs; it is never optional.
var _directed: bool = false
## The player's own zoom target, stashed when a focus takes the camera and
## restored exactly on release, so their next scroll tick is not offset and
## the 0.25 wheel lattice is never broken (#515 decision 6).
var _stored_target_zoom: float = 1.0
var _pan_tween: Tween = null


func _ready() -> void:
	_target_zoom = zoom.x
	current_zoom = _target_zoom
	Events.camera_zoom_changed.emit(current_zoom)
	RenderingServer.global_shader_parameter_set(&"edge_camera_zoom", current_zoom)


func _unhandled_input(event: InputEvent) -> void:
	# Panning: middle mouse button drag
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			# Announce FIRST: the director's cancel is synchronous, so by the
			# line below the camera is the player's again and the pan lands
			# this same event rather than a frame later.
			manual_input_received.emit()
			global_position -= event.relative / zoom
			_clamp_position()
	# Zooming: scroll wheel. Each physical tick is a pressed AND a released
	# InputEventMouseButton on the same button_index — gate on `event.pressed`
	# (not `Input.is_mouse_button_pressed`, global state that both events see)
	# so one tick is one `_zoom_by` call, not two.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			manual_input_received.emit()
			_zoom_by(zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			manual_input_received.emit()
			_zoom_by(-zoom_step)

func _process(delta: float) -> void:
	# Limits are re-derived from the zoom every frame (not just on pan/zoom-step
	# input) because the zoom tween moves `zoom.x` continuously between steps —
	# without this the margin would only update in discrete jumps at each step's
	# start/end instead of tracking the glide.
	_update_limits()
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir != Vector2.ZERO:
		# Read, announce, THEN apply-or-skip. Gating the whole branch on
		# `_directed` would mean the signal never fires while a focus holds the
		# camera, and arrow keys could never break in at all.
		manual_input_received.emit()
		if not _directed:
			global_position += input_dir * pan_speed * delta
	_clamp_position()


## Ease the camera toward [param target] at [param zoom_target], on behalf of
## [CameraDirector] (#523). The director DECIDES — where to look, whether the
## span fits, whether the player's hands are on the camera — and this executes,
## so `GraphCamera` stays the sole writer of `global_position` and `zoom`.
##
## Takes a resolved zoom rather than the span's `fit_size`: the fit policy (the
## 0.25 lattice, the floor, the centre-of-mass fallback) is the director's, and
## it must land as ONE discrete zoom target because
## [signal Events.camera_zoom_changed] is O(live Edge count) and is deliberately
## broadcast on the target rather than per tween frame.
##
## [param duration] of 0.0 is a hard cut. Re-calling while already directed
## RETARGETS rather than queueing — a multi-attack turn reads as one continuous
## follow instead of a stutter.
func begin_directed_focus(target: Vector2, zoom_target: float, duration: float) -> void:
	if not _directed:
		_resync_target_zoom_if_idle()
		_stored_target_zoom = _target_zoom
		_directed = true
	_apply_zoom_target(zoom_target)
	if _pan_tween != null and _pan_tween.is_valid():
		_pan_tween.kill()
	if duration <= 0.0:
		global_position = target
		_clamp_position()
		return
	_pan_tween = create_tween()
	_pan_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pan_tween.tween_property(self, ^"global_position", target, duration)


## Hand the camera back. POSITION stays exactly where the action ended — there
## is no return pan and no remembered anchor (#515 decision 5). ZOOM does
## return, to the player's own stored target, so their wheel lattice survives.
func end_directed_focus() -> void:
	if not _directed:
		return
	_directed = false
	if _pan_tween != null and _pan_tween.is_valid():
		_pan_tween.kill()
	_pan_tween = null
	_apply_zoom_target(_stored_target_zoom)


func is_directed() -> bool:
	return _directed


## The player's own zoom target — what [method end_directed_focus] restores.
## Reads through to [member _target_zoom] when nothing is directing, so a
## caller never has to know which of the two is live.
func player_zoom_target() -> float:
	return _stored_target_zoom if _directed else _target_zoom


## `limit_*` only clamps what Camera2D actually RENDERS — the screen-center it
## computes internally — not this node's own `global_position`. Left alone, a
## pan held past the limit keeps accumulating into `global_position` while the
## view sits pinned at the edge; the overshoot is invisible until the player
## reverses direction, and the camera doesn't visibly move until that hidden
## backlog is walked off first. Clamping `global_position` itself right after
## every pan write keeps the two in lockstep, so hitting a bound is immediate
## in both directions.
##
## Reproduces Camera2D's own half-viewport clamp math (`camera_2d.cpp`
## `_update_scroll`) rather than clamping to the bare `limit_*` rect — clamping
## to the raw rect would fight the engine's real clamp and could disagree with
## what's actually on screen. If the limit rect is smaller than the current
## view (shouldn't happen once GameRoot's `set_min_zoom_floor` is honoured,
## but this stays correct if it ever is), it centers instead of clamping
## against an inverted range.
## Grows `limit_*` around [member _graph_bounds] by [member _pan_margin_base]
## scaled by 1/zoom — see [member _pan_margin_base] for why the scaling exists.
func _update_limits() -> void:
	if _graph_bounds.size == Vector2.ZERO:
		return
	var margin: float = _pan_margin_base / zoom.x
	var effective := _graph_bounds.grow(margin)
	limit_left = int(effective.position.x)
	limit_top = int(effective.position.y)
	limit_right = int(effective.end.x)
	limit_bottom = int(effective.end.y)
	if effective != _last_effective_bounds:
		_last_effective_bounds = effective
		bounds_changed.emit(effective)


## Pushed by GameRoot after `_apply_graph_bounds` computes the level's raw
## SkillNode AABB. [param margin_at_zoom_1] is the fixed world-space margin
## GameRoot also grows the fog/aura bounds by — using it as the zoom == 1.0
## baseline here keeps the camera's pan limit matching the fog bound exactly
## at default zoom, while [method _update_limits] scales it at other zooms.
func set_graph_bounds(bounds: Rect2, margin_at_zoom_1: float) -> void:
	_graph_bounds = bounds
	_pan_margin_base = margin_at_zoom_1
	_update_limits()


func _clamp_position() -> void:
	var view_half_size: Vector2 = (get_viewport().get_visible_rect().size / zoom) * 0.5
	var min_x := limit_left + view_half_size.x
	var max_x := limit_right - view_half_size.x
	global_position.x = clampf(global_position.x, min_x, max_x) if min_x <= max_x \
			else (limit_left + limit_right) * 0.5
	var min_y := limit_top + view_half_size.y
	var max_y := limit_bottom - view_half_size.y
	global_position.y = clampf(global_position.y, min_y, max_y) if min_y <= max_y \
			else (limit_top + limit_bottom) * 0.5


## Advances the zoom target by one step and retargets the tween. Killing the
## previous tween first is what makes rapid scrolling accumulate instead of
## having two tweens fight over `zoom`; because the new tween starts from
## wherever the old one got to, the steps chain into one continuous glide.
##
## Takes a STEP, not an absolute target, so the caller never has to read
## `_target_zoom` before the resync below has had a chance to run.
func _zoom_by(step: float) -> void:
	_resync_target_zoom_if_idle()
	_apply_zoom_target(_target_zoom + step)


## Honour any external write to `zoom` since the last step, but only while
## nothing is in flight — mid-tween `zoom.x` is a fractional, half-applied
## value and accumulating on it silently drops steps during fast scrolling.
## A level scene assigns `zoom` directly from `_setup_level()`, which runs
## AFTER this node's `_ready`; without this resync `_target_zoom` would still
## hold the stale value and the first scroll tick would teleport.
func _resync_target_zoom_if_idle() -> void:
	if _zoom_tween != null and _zoom_tween.is_valid():
		return
	_target_zoom = zoom.x


## The one place [member _target_zoom] moves. Retargets the tween, killing the
## previous one first — that is what makes rapid scrolling accumulate instead
## of having two tweens fight over `zoom`, and because the new tween starts
## from wherever the old one got to, the steps chain into one continuous glide.
##
## No-ops on an unchanged target. [method _request_zoom_broadcast] fans out
## O(live Edge count), and a multi-attack turn retargets the director's focus
## repeatedly at the same zoom.
func _apply_zoom_target(value: float) -> void:
	var wanted := clampf(value, _min_zoom_floor, MAX_ZOOM)
	if is_equal_approx(wanted, _target_zoom):
		return
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_target_zoom = wanted
	current_zoom = _target_zoom
	_request_zoom_broadcast()
	if zoom_duration <= 0.0:
		zoom = Vector2(_target_zoom, _target_zoom)
		return
	_zoom_tween = create_tween()
	_zoom_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_property(self, ^"zoom", Vector2(_target_zoom, _target_zoom), zoom_duration)


## Pushed by GameRoot after `_apply_graph_bounds` sizes `limit_*` to the
## graph's own footprint — [param value] is the zoom at which the viewport
## exactly fills that rect. Snaps a currently-more-zoomed-out camera back up
## to the new floor immediately, killing any in-flight tween the same way
## [method _zoom_by] does, so a level swap can't leave the camera showing
## past its own limit rect for one frame.
func set_min_zoom_floor(value: float) -> void:
	_min_zoom_floor = clampf(value, MIN_ZOOM, MAX_ZOOM)
	if _target_zoom >= _min_zoom_floor:
		return
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_target_zoom = _min_zoom_floor
	current_zoom = _target_zoom
	zoom = Vector2(_target_zoom, _target_zoom)
	_update_limits()
	_request_zoom_broadcast()


## The three runtime facts [CameraContext] needs and that only GameRoot has
## pushed here: the level's zoom floor, its raw SkillNode AABB, and the pan
## slack the limits are grown by. Exposed as reads so the director builds its
## context from the camera without reaching into private state.
func min_zoom_floor() -> float:
	return _min_zoom_floor


func graph_bounds() -> Rect2:
	return _graph_bounds


func pan_margin_base() -> float:
	return _pan_margin_base


## The world-space rect the camera is CURRENTLY showing — what the minimap
## paints its viewport outline from (#453).
##
## Reads the live `zoom`, not [member _target_zoom], deliberately: the wheel
## tweens `zoom` over [member zoom_duration] and the outline should glide with
## the view rather than snap to the step's destination a frame after the
## player scrolls.
func view_rect() -> Rect2:
	var half: Vector2 = (get_viewport().get_visible_rect().size / zoom) * 0.5
	return Rect2(global_position - half, half * 2.0)


## Jump the view to [param world_pos], on behalf of a surface that names a
## place directly rather than nudging the camera — the minimap's click/drag
## (#453). No tween: a drag across the minimap is a stream of these, and each
## one retargeting a glide would lag the cursor by the tween's whole duration.
##
## Emits [signal manual_input_received] FIRST, for the same reason the
## middle-drag in [method _unhandled_input] does: [CameraDirector]'s cancel is
## synchronous, so by the assignment below the camera is the player's again and
## the jump lands on this event instead of being overwritten by a focus still
## in flight.
func pan_to(world_pos: Vector2) -> void:
	manual_input_received.emit()
	global_position = world_pos
	_clamp_position()


func _request_zoom_broadcast() -> void:
	if _zoom_broadcast_pending:
		return
	_zoom_broadcast_pending = true
	_broadcast_zoom_deferred.call_deferred()


func _broadcast_zoom_deferred() -> void:
	_zoom_broadcast_pending = false
	Events.camera_zoom_changed.emit(current_zoom)
	RenderingServer.global_shader_parameter_set(&"edge_camera_zoom", current_zoom)

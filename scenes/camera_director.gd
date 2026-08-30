class_name CameraDirector
extends Node

## The one thing that decides where the camera looks (#515/#523), arbitrating
## between the local player's own pan/zoom and whatever the game wants to show
## them.
##
## [b]The director decides; [GraphCamera] executes.[/b] `GraphCamera._process`
## writes `global_position` and clamps it every frame unconditionally, so a
## second writer running its own Tween on the same property produces jitter.
## Every decision here lands through [method GraphCamera.begin_directed_focus].
##
## [b]The decision is a pure function.[/b] [method decide] takes a
## [FocusRequest] and a [CameraContext] of plain values and returns a
## [FocusDecision] — no live camera, no tree, no frames. GUT is headless and
## easing is not assertable in pixels, so every policy assertion (grace window,
## skip-if-on-screen, fit-or-step-out, centre-of-mass fallback, and the pan
## clamp) is written against `decide`. In particular the returned
## [member FocusDecision.target] is ALREADY CLAMPED, because a test that
## asserts what the director *requested* passes while the feature is broken.
##
## [b]Presentation only.[/b] Camera motion observes the reveal clock, it never
## drives it — nothing here is ever awaited by a mutation path. See
## `.claude/rules/presentation-clock.md`.

## The camera this director drives. Wired as an `@export` NodePath by
## `game_root.tscn` per `.claude/rules/scene-composition.md`.
@export var camera: GraphCamera
## The fog gate: only what the local player can SEE may be framed.
@export var vision_system: VisionSystem
## The battle hook (#524): a non-local actor's committed attack frames its
## from->to span.
@export var battle_system: BattleSystem
## The command hook (#525): every confirmed territory change frames itself.
## [signal CommandApplier.command_confirmed] rather than [AllocationSystem]'s
## signals, because a command carries THE ACTOR by construction
## ([member Command.entity_id]) and the forced channel — level-load core
## allocation, the death cascade, [BattleSystem]'s dealloc cascade — never
## builds a [Command] at all. Both of the traps that channel would have needed
## a filter for are simply not on this wire.
@export var command_applier: CommandApplier
## Resolves a command's wire ids back to live objects, exactly as
## [CommandApplier] does: [method Graph.get_by_entity_id] for the actor,
## [method Graph.get_by_stable_id] for each node.
@export var graph: Graph
## How long the player's hands stay on the camera after their last manual
## input. Without it a multi-wave spell re-steals the camera the instant they
## let go. The first thing here that will want tuning.
@export_range(0.0, 10.0, 0.1, "or_greater") var manual_grace_seconds: float = 2.5
## The span is grown by this fraction before being fitted, so the framed thing
## does not touch the viewport border.
@export_range(0.0, 1.0, 0.01) var span_margin_ratio: float = 0.15
## A focus is skipped when its fitted span already sits inside the current view
## inset by this fraction of each dimension — no point panning to something the
## player is already looking at.
@export_range(0.0, 0.49, 0.01) var on_screen_inset_ratio: float = 0.15
## Default ease duration for a focus that does not name its own.
@export_range(0.0, 2.0, 0.05) var default_focus_duration: float = 0.35
## Extra seconds held after the last hit lands, before handing the camera back.
@export_range(0.0, 2.0, 0.05) var release_tail_seconds: float = 0.25
## How long a confirmed command's focus is held (#525). The synchronous verbs
## have no arrival clock to size a hold off — the applier drains them inside a
## stack frame — so unlike an attack they need a knob. [MoveCoreCommand] is the
## exception: it DERIVES its hold from the applier's own hop beat, so the
## camera holds for exactly the walk. See [method _command_hold].
@export_range(0.0, 5.0, 0.05) var command_hold_seconds: float = 0.6
## The zoom lattice the wheel walks (`GraphCamera.zoom_step`). The director
## snaps to it and never leaves it, which is what lets the camera restore the
## player's exact `_target_zoom` on release.
const ZOOM_LATTICE := 0.25

## Who this machine plays — the predicate #524 gates its trigger on. Pushed by
## GameRoot rather than `@export`ed, because [SeatPolicy] is a RefCounted the
## level constructs during `_setup_level`, not a node in the scene.
var seat_policy: SeatPolicy = null

var _seconds_since_manual: float = INF
var _active: bool = false
var _remaining: float = 0.0


func _ready() -> void:
	set_process(true)
	if camera != null and not camera.manual_input_received.is_connected(_on_manual_input):
		camera.manual_input_received.connect(_on_manual_input)
	if battle_system != null and not battle_system.attack_committed.is_connected(_on_attack_committed):
		battle_system.attack_committed.connect(_on_attack_committed)
	if command_applier != null \
			and not command_applier.command_confirmed.is_connected(_on_command_confirmed):
		command_applier.command_confirmed.connect(_on_command_confirmed)


func _process(delta: float) -> void:
	_seconds_since_manual += delta
	if not _active:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		release()


## The player touched the camera. Their hands win instantly — any focus in
## flight dies this frame, and [method decide] refuses for
## [member manual_grace_seconds] afterwards.
func _on_manual_input() -> void:
	_seconds_since_manual = 0.0
	if _active:
		release()


## Ask the director to look somewhere. Returns the [FocusDecision] it reached,
## so a caller (or a test) can read why nothing happened.
##
## Never await this. It is reachable from `BattleSystem._commit`, where an
## await would gate the mutation loop.
func request_focus(request: FocusRequest) -> FocusDecision:
	var decision := decide(request, make_context())
	if not decision.act:
		return decision
	if camera != null:
		camera.begin_directed_focus(decision.target, decision.zoom_target, decision.duration)
	_active = true
	_remaining = decision.duration + decision.hold
	if _remaining <= 0.0:
		# A hard cut with no hold — a hot-seat handover. Hand the camera back
		# in the same call so the player's very next arrow key pans, exactly as
		# it did before #459's focus was routed through here.
		release()
	return decision


## Hand the camera back. Position stays where the action ended; only zoom
## returns (#515 decision 5).
func release() -> void:
	_active = false
	_remaining = 0.0
	if camera != null:
		camera.end_directed_focus()


func is_focusing() -> bool:
	return _active


## Snapshot the live camera into the plain values [method decide] reads.
func make_context() -> CameraContext:
	var ctx := CameraContext.new()
	ctx.seconds_since_manual_input = _seconds_since_manual
	if camera == null:
		return ctx
	var viewport := camera.get_viewport()
	if viewport != null:
		ctx.viewport_size = viewport.get_visible_rect().size
	ctx.zoom = camera.player_zoom_target()
	ctx.center = camera.global_position
	ctx.graph_bounds = camera.graph_bounds()
	ctx.pan_margin_base = camera.pan_margin_base()
	ctx.min_zoom_floor = camera.min_zoom_floor()
	return ctx


## [b]The whole policy, as one pure function.[/b] No live camera is touched and
## no frame is needed, so every acceptance assertion is written against this.
func decide(request: FocusRequest, ctx: CameraContext) -> FocusDecision:
	if request == null or request.points.is_empty():
		return FocusDecision.no(request.empty_reason if request != null else &"empty")
	if not request.mandatory and ctx.seconds_since_manual_input < manual_grace_seconds:
		return FocusDecision.no(&"grace")

	var span := request.bounds()
	var fit_size := span.size * (1.0 + span_margin_ratio)
	var zoom_target := _fit_zoom(fit_size, ctx) if request.allow_zoom_out else ctx.zoom
	var overflows := not _fits(fit_size, ctx.visible_size(zoom_target))

	# Centre of mass, not the AABB midpoint, once the span cannot fit: the
	# midpoint of a lopsided spell points at empty space while the centroid
	# points at the dense part, which is where the action is.
	var ideal: Vector2 = request.center_of_mass() if overflows else span.get_center()

	if not request.mandatory and zoom_target == ctx.zoom and _already_on_screen(fit_size, ideal, ctx):
		return FocusDecision.no(&"on_screen")

	var decision := FocusDecision.new()
	decision.act = true
	decision.reason = &"ok"
	decision.fit_size = fit_size
	decision.zoom_target = zoom_target
	decision.duration = request.duration
	decision.hold = request.hold
	decision.center_of_mass = overflows
	decision.target = _clamp_target(ideal, zoom_target, ctx)
	decision.clamped = not decision.target.is_equal_approx(ideal)
	return decision


## The zoom to take for [param fit_size]. Steps OUT along the 0.25 lattice to
## the first value that fits and no further; never in, and never past a
## zoom-out the player already chose.
##
## The floor is the smallest LATTICE value at or above `min_zoom_floor` — the
## two do not align (a small level's floor is an arbitrary float like 0.63,
## reachable by a manual scroll but not by the director). That is intended: the
## lattice is what lets the player's exact `_target_zoom` be restored, so the
## centre-of-mass fallback firing a little earlier than the raw floor implies
## is the price, not a bug to fix by going off-lattice (#524 amendment 2).
func _fit_zoom(fit_size: Vector2, ctx: CameraContext) -> float:
	if _fits(fit_size, ctx.visible_size(ctx.zoom)):
		return ctx.zoom
	var floor_zoom := ceilf(ctx.min_zoom_floor / ZOOM_LATTICE) * ZOOM_LATTICE
	if ctx.zoom <= floor_zoom:
		# Already at or below the lattice floor (a manual scroll can get below
		# it). Zooming IN to reach the lattice would be a yank.
		return ctx.zoom
	var candidate := snappedf(ctx.zoom, ZOOM_LATTICE)
	if candidate > ctx.zoom:
		candidate -= ZOOM_LATTICE
	while candidate >= floor_zoom:
		if _fits(fit_size, ctx.visible_size(candidate)):
			return candidate
		candidate = snappedf(candidate - ZOOM_LATTICE, ZOOM_LATTICE)
	return floor_zoom


func _fits(fit_size: Vector2, visible: Vector2) -> bool:
	return fit_size.x <= visible.x and fit_size.y <= visible.y


## Is [param fit_size] centred on [param at] already comfortably framed — i.e.
## inside the current view inset by [member on_screen_inset_ratio] of each
## dimension?
func _already_on_screen(fit_size: Vector2, at: Vector2, ctx: CameraContext) -> bool:
	var view := ctx.visible_rect()
	var inset := view.grow_individual(
		-view.size.x * on_screen_inset_ratio, -view.size.y * on_screen_inset_ratio,
		-view.size.x * on_screen_inset_ratio, -view.size.y * on_screen_inset_ratio)
	if inset.size.x <= 0.0 or inset.size.y <= 0.0:
		return false
	return inset.encloses(Rect2(at - fit_size * 0.5, fit_size))


## Reproduces `GraphCamera._update_limits` + `_clamp_position` exactly, at
## [param at_zoom], so the decision reports where the camera will ACTUALLY end
## up rather than where it wished to go.
##
## Both branches matter. Where the limit rect is wider than the view the
## position clamps; where it is NARROWER the camera centres on the limit rect
## instead — which is the same regime the centre-of-mass fallback lives in, so
## the clamp can and does override a centroid. And a zero-size `graph_bounds`
## means no limits have been pushed yet, mirroring `_update_limits`'s own early
## return — without that mirror a headless test would clamp against Camera2D's
## default limits and pass vacuously.
func _clamp_target(ideal: Vector2, at_zoom: float, ctx: CameraContext) -> Vector2:
	if ctx.graph_bounds.size == Vector2.ZERO:
		return ideal
	var effective := ctx.graph_bounds.grow(ctx.pan_margin_base / at_zoom)
	var half := ctx.visible_size(at_zoom) * 0.5
	var out := ideal
	var min_x := effective.position.x + half.x
	var max_x := effective.end.x - half.x
	out.x = clampf(ideal.x, min_x, max_x) if min_x <= max_x \
			else (effective.position.x + effective.end.x) * 0.5
	var min_y := effective.position.y + half.y
	var max_y := effective.end.y - half.y
	out.y = clampf(ideal.y, min_y, max_y) if min_y <= max_y \
			else (effective.position.y + effective.end.y) * 0.5
	return out


## #524's trigger. See [method _build_attack_request] for the rule.
func _on_attack_committed(outcome: AttackOutcome, attacker: Entity) -> void:
	var request := _build_attack_request(outcome, attacker)
	if request == null:
		return
	request_focus(request)


## Frame a committed attack's from->to span, for a NON-LOCAL actor only.
##
## [b]The seat predicate is the whole rule.[/b] On a couch `seats()` is true
## for every human, so a hot-seat partner's actions never yank the camera of
## the person actually driving; behind a wire only the pinned hero is seated,
## so AI and remote humans alike are framed (#515 decision 2). Returns null
## when no focus should be built at all.
##
## The span is the AABB of every contributing node's world position, filtered
## through [method VisionSystem.is_visible] FIRST — `is_sensed` does not count,
## and an attack whose origin is fogged but whose target is visible frames the
## target alone. Nothing surviving the filter is `&"fogged"`, not an error.
func _build_attack_request(outcome: AttackOutcome, attacker: Entity) -> FocusRequest:
	if outcome == null or outcome.hits.is_empty():
		return null
	if seat_policy != null and seat_policy.seats(attacker):
		return null
	var points := PackedVector2Array()
	# The schedule owns "how long does this take" (#543) — hand-computing a
	# `maxf` over every hit's cached seconds was a second implementation of
	# [method OutcomeSchedule.duration], free to drift the moment tempo became
	# a per-peer setting. Compile if nothing has yet: a focus that outlives its
	# attack is a stuck camera.
	if outcome.schedule == null:
		outcome.schedule = OutcomeSchedule.compile(outcome)
	var last_arrival: float = outcome.schedule.duration()
	for hit in outcome.hits:
		_append_if_visible(points, hit.origin)
		_append_if_visible(points, hit.target)
	var request := FocusRequest.span(points, default_focus_duration,
			last_arrival + release_tail_seconds, &"attack")
	request.empty_reason = &"fogged"
	return request


func _append_if_visible(points: PackedVector2Array, node: SkillNode) -> void:
	if node == null or not is_instance_valid(node):
		return
	if vision_system != null and not vision_system.is_visible(node):
		return
	var pos := node.global_position
	if not points.has(pos):
		points.append(pos)


## #525's trigger. See [method _build_command_request] for the rule.
##
## [signal CommandApplier.command_confirmed] fires INSIDE `_drain`, after the
## gate passed and BEFORE the mutation — so this is a genuine pre-mutation hook,
## on every peer, at most once per command, and never for a refused one. The pan
## therefore runs CONCURRENTLY with the mutation and is still ahead of any
## animation. It is never awaited: `is_applying` is true for the whole drain and
## [method PlayerInputController.can_player_act] gates on that flag, so an
## awaited pan would input-lock the player. See
## `.claude/rules/presentation-clock.md`.
func _on_command_confirmed(command: Command) -> void:
	var request := _build_command_request(command)
	if request == null:
		return
	request_focus(request)


## Frame a confirmed command's territory change, for a NON-LOCAL actor only.
## Returns null when no focus should be built at all — an excluded verb, an
## unresolvable actor, or an actor this machine seats.
##
## [b]The verb list is an explicit allow-list, never a subtype test.[/b]
## [ToggleTempUpgradeCommand] IS a [NodeCommand] and so has geometry, but it is
## not a territory change and is excluded on purpose; [LaunchAttackCommand] is
## excluded because [method _build_attack_request] already frames it, and wiring
## both would raise two focus requests per attack. So `is NodeCommand` would
## over-match and a `Command` fallback would over-match harder — every verb is
## named, and anything unnamed builds nothing.
##
## [b]The seat predicate is the same rule as the attack path.[/b] The local
## player who clicked the node is already looking at it; focusing it is the yank
## the feature exists to avoid (owner: "in your own turn we don't need a
## director"). An actor that fails to resolve is treated as unframeable rather
## than as "not seated" — `seats(null)` is false, so falling through would frame
## every unresolved command.
##
## Nothing surviving the fog filter yields an EMPTY request whose `empty_reason`
## is `&"fogged"`, not null — the same distinction `_build_attack_request` draws,
## so `decide()` can report why nothing happened.
func _build_command_request(command: Command) -> FocusRequest:
	if command == null or graph == null:
		return null
	var ids := _framed_node_ids(command)
	if ids.is_empty():
		return null
	var actor := graph.get_by_entity_id(command.entity_id)
	if actor == null:
		return null
	if seat_policy != null and seat_policy.seats(actor):
		return null

	var points := PackedVector2Array()
	for id in ids:
		_append_if_visible(points, graph.get_by_stable_id(id))
	var hold := _command_hold(command)
	var source := command.type_tag()
	var request: FocusRequest
	if points.is_empty() or ids.size() > 1:
		# A multi-node verb frames its whole set. An all-fogged command lands
		# here too, with no points at all — `decide` reads `empty_reason`.
		request = FocusRequest.span(points, default_focus_duration, hold, source)
	else:
		# One node, one command: a point focus, which sets `allow_zoom_out`
		# false and so can never yank the zoom for a single allocation.
		request = FocusRequest.point(points[0], default_focus_duration, false, source)
		request.hold = hold
	request.empty_reason = &"fogged"
	return request


## The nodes [param command] wants framed, as stable ids — empty for every verb
## this path does not claim. The exclusions are deliberate, not an oversight:
##   * [LaunchAttackCommand] — already framed by `attack_committed` (#524).
##   * [EndTurnCommand], [LootRoundCommand], [PickLootCommand] — no geometry.
##   * [ToggleTempUpgradeCommand] — has geometry, is not a territory change.
##
## [MassAllocateCommand] over-frames by design: its affordable count is
## re-computed at apply time (#458), so the path framed here may be longer than
## what actually lands. The requested path is the intent, and framing the intent
## is not wrong.
func _framed_node_ids(command: Command) -> Array[int]:
	if command is AllocateCommand or command is DeallocateCommand \
			or command is StakeCommand or command is ExtractCommand:
		return [(command as NodeCommand).node_id]
	if command is DeallocateSetCommand:
		return (command as DeallocateSetCommand).node_ids
	if command is MassAllocateCommand:
		return (command as MassAllocateCommand).path_ids
	if command is MoveCoreCommand:
		return (command as MoveCoreCommand).path_ids
	return []


## Seconds to hold a command's focus after the pan settles.
##
## [MoveCoreCommand] is the only verb with a real duration to read, and it is
## the applier's own beat: the walk is ONE command whose hops are spaced by
## [constant CommandApplier.CORE_HOP_SLIDE_DELAY], each hop gliding for
## [constant SkillNode.CORE_SLIDE_DURATION]. The two are deliberately unequal —
## the hops overlap so the walk reads as a cascade — so do not "fix" them to
## match. Every other verb is drained inside a stack frame and takes the knob.
func _command_hold(command: Command) -> float:
	if command is MoveCoreCommand:
		var hops := maxi((command as MoveCoreCommand).path_ids.size() - 1, 0)
		return hops * CommandApplier.CORE_HOP_SLIDE_DELAY + SkillNode.CORE_SLIDE_DURATION
	return command_hold_seconds

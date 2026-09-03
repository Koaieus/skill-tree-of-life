@tool
class_name FrontmatterRoot
extends Node2D

## The frontmatter shell: builds the menu tree once, then navigates it by moving
## the camera (#570).
##
## [b]One persistent graph. Nodes never move. The camera does.[/b] Every view is
## built at its [method FrontmatterLayout.solve] home and stays parented where it
## was put, at the z-index it was put at, for the life of the scene. The design
## canvas's `_select()` lifts the clicked node into a `transit` layer at
## `z-index: 15` while the hero fades out — the owner vetoed that in as many
## words ([i]"a big nope"[/i]), and this file is the shape of the veto:
## [method navigation_state] is a pure function of [member focus_id], so a
## forward-and-back traversal provably lands every view exactly where it started.
##
## [b]Grow, don't cut.[/b] A node's children rest COLLAPSED — stacked tight on
## their parent at [constant FrontmatterLayout.PREVIEW_SCALE] — and grow out to
## their homes when that parent takes the focus. The collapsed position is
## canonical, not a hover-only trick: it is where those children are whenever
## their parent is not the focus, which is also what makes back navigation
## symmetric for free. Both the camera travel and the sprout ride ONE `t`
## ([method set_progress]), so they are one motion rather than two that overlap.
##
## [b]Edges never pop.[/b] Every frame of a transition re-pushes both endpoints
## of every edge from the live view positions. No edge is ever reparented or
## rebuilt mid-transition — there is no code path here that could.
##
## [b]Panels are reached through the seam only.[/b] Routing a leaf calls
## [method FrontmatterPanels.show_panel]; this file knows nothing else about what
## a panel is. #573 fills them in, and an id whose panel has not landed yet is a
## documented no-op, so an unfinished panel leaves the graph on screen rather
## than erroring.

const _NODE_VIEW := preload("res://ui/frontmatter/menu_node_view.tscn")
## The ROOT's view alone, which inherits the one above and adds the splash's
## bespoke charge ring (#734). Branched on in [method _build_views] rather than
## exported, because "the root is the one node that can charge up" is a fact
## about this menu, not a knob.
const _SPLASH_ROOT_VIEW := preload("res://ui/frontmatter/splash_root_view.tscn")
const _EDGE_VIEW := preload("res://ui/frontmatter/menu_edge_view.tscn")

## Emitted once the camera has settled on a new focus. #574/#576 hang off this.
signal focus_changed(id: StringName)

## Emitted the instant [member focus_id] changes — when the camera SETS OFF,
## not when it arrives.
##
## [b]Two signals, because "where the menu is" and "where the camera is" are
## different questions during a transition[/b], and anything that decides what
## the NEXT input means has to answer the first one. [FrontmatterInput] reseats
## its cursor on this: seating it on [signal focus_changed] left the cursor
## pointing into the previous fan for the whole 850ms of travel, so pressing
## `ui_left` and then `ui_right` mid-flight committed to a GRANDCHILD of the node
## the camera had just returned to — one level skipped, from one stale
## [StringName]. Pinned by `test_frontmatter_input.gd`'s mid-flight tests.
##
## Anything that decorates an ARRIVAL — the splash handoff — still wants
## [signal focus_changed]. Do not merge them. (A leaf's panel used to be such a
## decoration; it now rides the clock itself from [member panel_lead], which is
## a third answer again: neither departure nor arrival.)
signal focus_started(id: StringName)

## Seconds a full navigation takes: the camera travel and the sprout together.
## #567's table gives 850ms for hero travel; the sprout rides the same clock
## with a snappier curve rather than a duration of its own.
@export_range(0.0, 3.0, 0.01) var travel_duration: float = 0.85

## Clock fraction (0..1 of [member travel_duration]) at which a leaf's panel
## starts sliding in — the panel no longer waits for the camera to land.
##
## [b]Sooner than arrival, on purpose.[/b] Waiting out the full pan made a leaf
## feel like it took 850ms to answer a click. The panel is up and readable
## while the tree is still settling behind it, and the slide
## ([method FrontmatterPanel.set_progress]) is what bridges the gap so it
## arrives rather than pops.
@export_range(0.0, 1.0, 0.01) var panel_lead: float = 0.3

## How long the panel's slide-in takes, in SECONDS — deliberately not a second
## clock fraction. Opening early means a low [member panel_lead], and a slide
## that rode "the rest of the travel" would get LONGER the earlier it opened,
## which is mush. This pins the slide's feel independent of how much pan it
## overlaps. Still one clock: it is read as a span of `t`, never as a [Tween].
@export_range(0.0, 1.5, 0.01) var panel_slide_duration: float = 0.25

## How long the outgoing panel takes to slide back out, in seconds. It runs
## from the START of the clock, so the stage is clear before the incoming
## panel's [member panel_lead] elapses — the panel layer still shows exactly
## one panel at a time, which is [FrontmatterPanels]' own rule and not
## something to relax for a crossfade.
@export_range(0.0, 1.5, 0.01) var panel_exit_duration: float = 0.15

## Screen-space gap between a node and the top of the slab stack that describes
## it. The stack is centred horizontally on the node, so this is the whole of
## the placement (#588) — there is no sideways component to tune.
@export_range(0.0, 200.0, 1.0) var tooltip_below_offset: float = 44.0

## Skip every transition — jump straight to `set_progress(1.0)`.
##
## [method build] overwrites this from [member GameSettings.reduce_motion], so
## what is authored on the node is the default a run without the autoload gets
## (the editor, and #578's live tab). See [method _resolve_reduce_motion].
@export var reduce_motion: bool = false

var tree: MenuGraph = null
var camera: FrontmatterCamera = null

## Where the menu is. Written by [method focus]; the whole rest of the visible
## state is derived from it.
var focus_id: StringName = &""

var _views: Dictionary = {}
var _edges: Dictionary = {}
var _from_pose: Dictionary = {}
var _to_pose: Dictionary = {}
var _progress: float = 1.0
var _settled: bool = false
## Refuses every [method focus] while raised — the menu's one navigation gate.
##
## [b]Raised by [SplashScreen] for the length of its charge (#734), and by
## nothing else.[/b] Leg 1 of the splash drives the [Camera2D] directly from its
## own tween for ~0.5s; a player who navigates during that starts a `_transition`
## that drives [method set_progress] onto the SAME camera, and two tweens fight
## over one transform. Owner call 2026-09-03: [i]lock input for the charge.[/i]
##
## [b]It gates HERE rather than at the splash's `_unhandled_input`, and that is
## the correction that closes a mouse-shaped hole.[/b] [MenuNodePickRegion] is a
## [Control], so GUI picking runs before physics picking and before
## `_unhandled_input` — a CLICK during the charge would reach
## [method _on_view_activated] and call [method focus] having never passed the
## splash at all. [method focus] is the one seam the keyboard path
## ([FrontmatterInput]) and the mouse path both converge on, so it is the only
## place a lock can be complete. [method back] routes through [method focus] too
## and is covered for free.
##
## [b]A plain var, deliberately not an `@export`.[/b] It is runtime state, not
## tuning — authored `true` in the inspector it would softlock the whole menu.
## [method build]'s seeding `focus(root, true)` runs before any splash exists and
## is unaffected.
var navigation_locked: bool = false

var _transition: Tween = null
var _tooltip: MenuTooltip = null

## First-focus latch (#599): [method build] ends on a seeding
## `focus(tree.root, true)`, which takes the root view `false -> true` — a
## naive diff in [method _sync_allocation] would drop a spike on a
## splash-zoomed root before the prompt is even up. Suppresses VFX for the
## first `_sync_allocation` call after a build only; reset there so #578's
## live-tab rebuild-in-place does not leave it permanently armed.
var _first_focus_done: bool = false

## The panel of the focus the CURRENT transition LEFT, or `&""`. Captured by
## [method focus] the same way [member _from_pose] captures where the views
## were: an exit needs to outlive the focus that owned it, and deriving it from
## the previous [member focus_id] rather than from what the container happens
## to be showing keeps it true even when a panel dismissed itself on the way out
## (the exit confirm's "no", which takes itself down before [method back] runs).
##
## It may equal the INCOMING panel — two leaves can share one (both offline
## routes open the lobby) — which is a third case rather than an exit: see
## [method _drive_panel].
var _left_panel: StringName = &""

const TOOLTIP_SCENE := preload("res://ui/frontmatter/menu_tooltip.tscn")

@onready var _camera_2d: Camera2D = %Camera
@onready var _graph_layer: Node2D = %GraphLayer
@onready var _panel_layer: CanvasLayer = %PanelLayer
@onready var _hover_preview: HoverPreview = %HoverPreview
@onready var _back_affordance: BackAffordance = %BackAffordance
@onready var _input: FrontmatterInput = %FrontmatterInput


func _ready() -> void:
	build()


## Re-parks the tooltip beside its node, every frame it is up.
##
## [b]Placing it once, when the hover changes, is not enough — twice over.[/b]
## The node it describes is still travelling for [member travel_duration] after
## the hover is set, and a [Camera2D] does not publish its transform until its
## own internal process runs, so `get_viewport_transform()` read from inside
## [method set_progress] is a frame stale and the LAST such read is the one the
## slab keeps once the transition stops driving it. Both show up as a tooltip
## parked hundreds of pixels from the node that summoned it.
##
## Per-frame is the honest fix rather than a chase: it is one [Transform2D]
## multiply for one [Control], and it cannot be stale by construction.
func _process(_delta: float) -> void:
	if _tooltip != null and _tooltip.modulate.a > 0.0:
		_place_tooltip(_hover_preview.hovered_id)


## Builds the whole menu — every node view, every edge view, the camera — and
## parks the camera on the root. Idempotent: a rebuild clears what it made
## first, so #578's live tab can retune geometry and rebuild in place.
func build(menu_tree: MenuGraph = null) -> void:
	tree = menu_tree if menu_tree != null else MenuGraph.build()
	reduce_motion = _resolve_reduce_motion()
	_clear()
	_first_focus_done = false
	# Defensive: `focus_id` still holds the PRE-rebuild focus here, so an
	# uncleared exit would describe a panel this build never showed. Today's
	# seeding focus is instant and lands past the exit in the same call, so
	# nothing observes it — which is exactly why it is worth clearing rather
	# than reasoning about again the next time this focus stops being instant.
	_left_panel = &""
	_build_views()
	_build_edges()
	camera = FrontmatterCamera.new(_camera_2d, tree)
	_connect_panels()
	_bind_affordances()
	focus(tree.root, true)


## Navigates to [param id]. [param instant] (or [member reduce_motion]) lands it
## in one frame; otherwise a [Tween] drives [method set_progress] across
## [member travel_duration].
##
## The tween lives HERE and nowhere else: `set_progress(t)` with one external
## caller owning the clock is the repo's convention for an animated unit
## (`ui/tooltip_fan/addon_item.gd`), and it is what lets a test assert `t == 0`
## and `t == 1` without chasing frames.
func focus(id: StringName, instant: bool = false) -> void:
	if navigation_locked:
		return
	if not tree.has(id):
		return
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = null
	_left_panel = _panel_of(focus_id)
	focus_id = id
	_settled = false
	set_hovered(&"")
	_back_affordance.apply(focus_id, true)
	_sync_allocation()
	_capture_transition()
	camera.travel_to(id)
	# Before the transition is driven, so a listener that reseats input state
	# cannot be beaten to it by `set_progress(1.0)`'s `focus_changed` on the
	# instant path.
	focus_started.emit(focus_id)
	if instant or reduce_motion or travel_duration <= 0.0:
		set_progress(1.0)
		return
	set_progress(0.0)
	_transition = create_tween()
	_transition.tween_method(set_progress, 0.0, 1.0, travel_duration)


## Up one level. A no-op at the root — there is nowhere above it, and the menu
## must not empty itself out from under the player.
##
## [b]This is [method focus] with the parent's id, deliberately.[/b] The motion
## notes list "back-navigation doesn't mirror forward navigation" as a gap; under
## a camera there is nothing to mirror. Do not add a reverse path here.
func back() -> bool:
	var parent := tree.parent_of(focus_id)
	if parent == &"":
		return false
	# No `hide_all()` here any more: taking the panel down is the clock's job
	# now ([method _drive_panel]), and cutting it away first is precisely the
	# hard cut the exit slide replaces. The instant path still clears it in the
	# same call, via `set_progress(1.0)`.
	focus(parent)
	return true


## Applies the whole transition at clock position `t` (0..1) — the camera, every
## sprouting child, and every edge, off ONE clock.
func set_progress(t: float) -> void:
	_progress = clampf(t, 0.0, 1.0)
	camera.set_progress(_progress)
	var eased := FrontmatterCamera.ease_sprout(_progress)
	for id in _views:
		var view: MenuNodeView = _views[id]
		var from: Array = _from_pose[id]
		var to: Array = _to_pose[id]
		view.position = (from[0] as Vector2).lerp(to[0] as Vector2, eased)
		var s: float = lerpf(from[1] as float, to[1] as float, eased)
		view.scale = Vector2(s, s)
	_push_edges()
	_drive_panel(_progress)
	if _progress >= 1.0 and not _settled:
		_settled = true
		focus_changed.emit(focus_id)


## Everything a caller can see about where the menu is, as one comparable value.
##
## This exists for the anti-detaching guarantee: it is a pure function of
## [member focus_id], so "forward then back returns the exact prior state" is one
## equality rather than a list of spot checks — and any future change that made a
## view's pose depend on HOW it got there would fail it.
func navigation_state() -> Dictionary:
	var poses: Dictionary = {}
	for id in _views:
		var view: MenuNodeView = _views[id]
		poses[id] = [view.position, view.scale, view.allocated, view.get_parent(), view.z_index]
	var panels := panel_container()
	return {
		&"focus": focus_id,
		&"camera": camera.current_transform(),
		&"poses": poses,
		&"panel": panels.shown_panel if panels != null else &"",
	}


## The view for a menu id, for #571/#574/#576 to reach without walking children.
func view_for(id: StringName) -> MenuNodeView:
	return _views.get(id) as MenuNodeView


## The edge view running from [param id]'s PARENT down to it — edges are keyed
## by their child end, since every node has exactly one incoming edge and the
## root has none. Public for the same reason as [method view_for].
func edge_for(id: StringName) -> MenuEdgeView:
	return _edges.get(id) as MenuEdgeView


## Points the hover affordances at [param id], or clears them with `&""`.
##
## Called by the mouse (each view's [MenuNodePickRegion], wired in
## [method _build_views]) and by the keyboard ([FrontmatterInput] treats its
## cursor as a hover) — one seam, so the peek-ahead and the tooltip cannot tell
## the two apart and there is no second highlight rule to keep in sync.
func set_hovered(id: StringName) -> void:
	_hover_preview.apply(focus_id, id)
	# `bind` owns its own CONTENT — it empties itself on a null item or on one
	# with nothing to say (#575's content-driven rule, which is why the ROOT
	# shows no tooltip). Do not second-guess what it puts in the stack here.
	var look := FrontmatterLayout.look_of(id)
	_tooltip.bind(look)
	# But it does not raise itself. The stack fades and never hides (#588), so
	# its reveal is `set_progress`, and this is its one caller — gating on
	# `visible` instead, as this did, is a condition that is ALWAYS true: the
	# stack was bound with rows and then left at `t = 0`, so the frontmatter
	# tooltip never appeared at all. Landed instantly, per the repo's
	# animated-unit convention (an external caller may drive the clock; nothing
	# does yet).
	_tooltip.set_progress(1.0 if MenuTooltip.has_content(look) else 0.0)
	if MenuTooltip.has_content(look):
		_place_tooltip(id)


## Parks the slab stack directly and centrally UNDER its node, in SCREEN space.
##
## It lives in the `CanvasLayer` rather than beside the view in graph space for
## the reason `.claude/rules/modal-system.md` and #573 both give about panels:
## a canvas the camera transforms pans and *zooms* its text, and zoomed text is
## the "why is this blurry and drifting" bug. The conversion is the engine's own
## `get_viewport_transform()`, never hand-rolled camera math.
##
## Centred-below replaces the old up-and-to-the-right offset outright (#588):
## the stack authors its own width and fits itself to its rows, so its centre is
## a known quantity and the placement is `node_x - width / 2`. The stack centres
## its own scale pivot, so this holds mid-reveal too.
##
## [b]`get_global_transform_with_canvas()`, NOT `get_viewport_transform()`.[/b]
## The latter carries the viewport's FINAL transform — the `canvas_items`
## stretch and the letterbox — so it answers in WINDOW pixels, while a
## [CanvasLayer] child's `position` is read in viewport units. The two agree
## only in a window that happens to be exactly the 1440x960 base, and drift
## apart with distance from the centre everywhere else: the slab sat right of
## and below its node, by more the further out the node was. Found by looking at
## it, once it was visible at all.
func _place_tooltip(id: StringName) -> void:
	var view := view_for(id)
	if view == null:
		return
	var screen_pos := view.get_global_transform_with_canvas().origin
	_tooltip.position = Vector2(
		screen_pos.x - _tooltip.size.x * 0.5,
		screen_pos.y + tooltip_below_offset,
	)


## Hands each affordance the tree and the lookups it needs, once per build.
## They take [Callable]s rather than a reference to this node so that none of
## them can steer the navigation they decorate — [signal
## BackAffordance.back_requested] going to [method back] is the only edge the
## other way.
func _bind_affordances() -> void:
	_ensure_tooltip()
	_hover_preview.bind(tree, view_for, edge_for)
	# Bound from HERE rather than through FrontmatterInput's own
	# `frontmatter_path` export, even though the export exists and works: a
	# child's `_ready` runs BEFORE its parent's, so a self-binding input node
	# seats its cursor — and drives `focus()` — while this node's `@onready`
	# affordances are still null. Binding at build time is the only ordering in
	# which the shell is fully assembled first.
	_input.bind(self)
	_back_affordance.bind(tree)
	if not _back_affordance.back_requested.is_connected(_on_back_requested):
		_back_affordance.back_requested.connect(_on_back_requested)


func _on_back_requested() -> void:
	back()


## Mints the tooltip in CODE rather than instancing it in `frontmatter_root.tscn`.
##
## [b]This is a deliberate exception to `.claude/rules/scene-composition.md`, not
## an oversight.[/b] `menu_tooltip.tscn` instances `slab_panel.tscn`, which
## reaches its own children through `%Label`. A `%` name is registered against
## the node's `owner`, and instancing a scene that already instances another
## re-owns that third level to the OUTER scene root — so `%Label` stops
## resolving and `slab_panel.gd`'s `@onready` fails at
## `Node not found: "%Label"`. Two levels of nesting are fine, which is why
## `menu_tooltip.tscn` works standalone and its own tests pass; the third level
## is what breaks. An instance added from code has no `owner`, so its unique
## names resolve inside itself and the chain holds.
func _ensure_tooltip() -> void:
	if _tooltip != null and is_instance_valid(_tooltip):
		return
	_tooltip = TOOLTIP_SCENE.instantiate()
	# Never hidden — it rests at `modulate.a = 0` (#588). A hidden Control
	# skips layout, and a stack that skipped layout cannot report the width
	# `_place_tooltip` centres it by.
	_panel_layer.add_child(_tooltip)


## Ids on the path from the root to the current focus, root first.
func focus_path() -> Array[StringName]:
	return tree.path_to(focus_id)


## The panel container. Public since the panel reveal became tunable — #578's
## live tab pushes [member FrontmatterPanel.slide_offset] onto each registered
## panel, and a dev tab reaching in with its own `find_children` would be a
## second copy of this lookup.
##
## Found by type rather than by a direct-child walk (#603 D6): the container
## used to sit right on `%PanelLayer`, but it now lives at
## `%PanelLayer/FrontmatterColumns/Remainder/FrontmatterPanels`, and a
## `get_children()` walk one level deep would silently stop finding it the
## next time the columns scene grows a level. `find_children` is the same
## robust-to-nesting lookup `FrontmatterInput._panels` and `MetaRoot._panels`
## already use.
func panel_container() -> FrontmatterPanels:
	if _panel_layer == null:
		return null
	var found := _panel_layer.find_children("*", "FrontmatterPanels", true, false)
	return null if found.is_empty() else found[0] as FrontmatterPanels


## The exit confirm asks; the SHELL quits. A panel that called
## `get_tree().quit()` itself would end the process the moment a test pressed its
## button, which is exactly why C1's routing-parity test asserts the old menu's
## quit CONNECTION rather than pressing it. Same one-liner `meta_root.gd` used.
##
## `has_signal` guarded because the panel container is filled in by #573: the
## signal exists once that lands, and connecting a signal that is not there yet
## would be an error rather than a no-op.
func _connect_panels() -> void:
	var panels := panel_container()
	if panels == null:
		return
	if not panels.panel_dismissed.is_connected(_on_panel_dismissed):
		panels.panel_dismissed.connect(_on_panel_dismissed)
	if not panels.quit_requested.is_connected(_on_quit_requested):
		panels.quit_requested.connect(_on_quit_requested)


## The panel asked to go away; [method back] is what makes it go away — the
## exit slide included. (The container has already taken it off its own books;
## [member _left_panel] is derived from the focus being left, not from what the
## container is showing, so the slide still plays.)
func _on_panel_dismissed(_id: StringName) -> void:
	back()


func _on_quit_requested() -> void:
	get_tree().quit()


## Raises, drives and tears down the focus's panel — every frame, as a pure
## function of the clock.
##
## [b]Not latched, deliberately.[/b] The obvious shape here is "raise it once,
## when `t` first crosses [member panel_lead]" — but `t` runs BACKWARDS
## routinely: #578's live tab wires a scrub slider straight into
## [method set_progress], which is exactly the loop this animation gets tuned
## in. A one-way latch would leave [member FrontmatterPanels.shown_panel] set
## with the panel clamped invisible. Derived from `t` instead, so scrubbing is
## symmetric for free — the same reason [method navigation_state] is a pure
## function of [member focus_id].
##
## Landing on a branch (or a leaf with no panel) is itself a routing target,
## not a no-op — it must tear down whatever panel the previous leaf left up,
## same as [method back] already does explicitly.
func _drive_panel(t: float) -> void:
	var panels := panel_container()
	if panels == null:
		return
	var incoming := _panel_of(focus_id)
	# Three cases, not two. A panel the transition both LEFT and is arriving at
	# — two leaves can share one — never left the stage, so it is HELD rather
	# than slid out and back in, which would be a flinch around nothing. Its
	# contents still swap, at departure (`meta_root.gd`'s `_on_focus_started`).
	if incoming != &"" and _left_panel == incoming:
		panels.show_panel(incoming)
		return
	# Otherwise the outgoing panel owns the head of the clock, alone. Both
	# panels visible at once would be a crossfade, and `FrontmatterPanels`
	# allows exactly one.
	var exit_t := exit_progress_at(t)
	if _left_panel != &"" and exit_t < 1.0:
		panels.show_panel(_left_panel)
		panels.set_exit_progress(exit_t)
		return
	var panel_t := panel_progress_at(t, _effective_lead())
	if incoming == &"" or panel_t <= 0.0:
		panels.hide_all()
		return
	# In this order and in ONE call: `show_panel` lands the panel fully
	# revealed, so a `set_progress` a frame later would flash it opaque first.
	panels.show_panel(incoming)
	panels.set_progress(panel_t)


## The panel [param id] raises, or `&""` for a branch, an unknown id, or a leaf
## that authors none.
func _panel_of(id: StringName) -> StringName:
	if tree == null:
		return &""
	var item := tree.get_item(id)
	# A leaf may carry no panel at all — `Item.panel` defaults to `&""` and
	# `is_leaf()` is "has no children", not "has a panel".
	return item.panel if item != null and item.is_leaf() else &""


## [member panel_lead], floored by the exit so the incoming panel cannot be
## scheduled to start while the outgoing one is still on stage — at the authored
## values it never is (170ms out, 255ms lead), but a lead dragged below the exit
## in #578's tab would otherwise make the entry POP in mid-slide, at whatever
## progress its own curve had already reached.
func _effective_lead() -> float:
	if _left_panel == &"":
		return panel_lead
	return maxf(panel_lead, exit_span())


## The panel's own reveal clock at travel clock position [param t] — 0 until the
## lead has elapsed, then a [member panel_slide_duration]-long ramp expressed as
## a span of `t`. Public because it is the whole timing contract, and a test
## asserting it needs no frames.
func panel_progress_at(t: float, lead: float = -1.0) -> float:
	if lead < 0.0:
		lead = panel_lead
	var span := minf(1.0 - lead, panel_slide_duration / maxf(travel_duration, 0.001))
	# A zero span is a SNAP, not a hidden panel — reachable from both ends of
	# the tuning range (`panel_lead = 1.0`, `panel_slide_duration = 0.0`), and
	# `lead = 1.0` is exactly the "show me the old wait-for-arrival behaviour"
	# comparison. Dividing by an epsilon instead left `(t - lead) == 0` at
	# `t = 1`, i.e. the panel never appearing at all.
	if span <= 0.0:
		return 1.0 if t >= lead else 0.0
	return clampf((t - lead) / span, 0.0, 1.0)


## The outgoing panel's dismissal clock at travel clock position [param t]. Runs
## from `t = 0`, so leaving a leaf clears the stage first and the incoming panel
## follows into an empty one.
func exit_progress_at(t: float) -> float:
	var span := exit_span()
	if span <= 0.0:
		return 1.0
	return clampf(t / span, 0.0, 1.0)


## How much of the travel clock the exit occupies.
func exit_span() -> float:
	return minf(1.0, panel_exit_duration / maxf(travel_duration, 0.001))


## Allocation is "on the focus path" (#569) — an identity change, not motion, so
## it lands at once rather than being tweened.
func _sync_allocation() -> void:
	var path := tree.path_to(focus_id)
	# Suppress on the first call after a build (the seeding `focus(root, true)`)
	# — VFX still needs the `allocated` flags written, just not to fire.
	var suppress := not _first_focus_done
	_first_focus_done = true
	for id in _views:
		var view: MenuNodeView = _views[id]
		# Diff against the view's LIVE flag, read before it is overwritten —
		# what makes `SplashScreen._park()`'s direct `allocated = false` write
		# account for itself for free, with no cached previous-path state here.
		var was_allocated := view.allocated
		var now_allocated := path.has(id)
		view.allocated = now_allocated
		if suppress or was_allocated == now_allocated:
			continue
		if now_allocated:
			view.play_allocation_spike()
		else:
			view.play_dealloc_lift(_graph_layer)
	for key in _edges:
		var edge: MenuEdgeView = _edges[key]
		var parent_view: MenuNodeView = _views[tree.parent_of(key)]
		var child_view: MenuNodeView = _views[key]
		edge.lit = parent_view.allocated and child_view.allocated


## Snapshots where every view is now, and where the new focus wants it, so
## [method set_progress] is a straight interpolation between two poses.
func _capture_transition() -> void:
	_from_pose = {}
	_to_pose = {}
	var homes := FrontmatterLayout.solve(tree)
	var path := tree.path_to(focus_id)
	for id in _views:
		var view: MenuNodeView = _views[id]
		_from_pose[id] = [view.position, view.scale.x]
		_to_pose[id] = _target_pose(id, homes, path)


## A view is at its canonical home when its PARENT is on the focus path — which
## is the whole of "grow, don't cut": the focus's children fan out, everything
## deeper stays collapsed on its own parent, and the root is always home because
## it has no parent to be anywhere else.
func _target_pose(id: StringName, homes: Dictionary, path: Array[StringName]) -> Array:
	var parent := tree.parent_of(id)
	if parent == &"" or path.has(parent):
		return [homes[id] as Vector2, 1.0]
	var slots := FrontmatterLayout.preview_slots(tree, parent)
	return [slots.get(id, homes[id]) as Vector2, FrontmatterLayout.PREVIEW_SCALE]


func _build_views() -> void:
	var homes := FrontmatterLayout.solve(tree)
	for id in tree.ids():
		var scene := _SPLASH_ROOT_VIEW if id == tree.root else _NODE_VIEW
		var view: MenuNodeView = scene.instantiate()
		view.name = String(id)
		_graph_layer.add_child(view)
		view.bind(FrontmatterLayout.look_of(id))
		view.position = homes[id]
		view.hover_entered.connect(set_hovered.bind(id))
		view.hover_exited.connect(_on_hover_exited.bind(id))
		view.activated.connect(_on_view_activated.bind(id))
		_views[id] = view


## The mouse left [param id]. Guarded on it still BEING the hovered node so that
## the exit of the node you just left cannot clear the hover of the one you have
## already entered — `mouse_exited` and `mouse_entered` arrive in that order when
## two hit areas touch.
func _on_hover_exited(id: StringName) -> void:
	if _hover_preview.hovered_id == id:
		set_hovered(&"")


## A click on a node navigates to it — the same call `ui_accept` makes, so mouse
## and keyboard cannot drift into two navigation paths (#576's rule, restated
## for the mouse).
##
## [b]It navigates to the node CLICKED, not to a cursor[/b], and it refuses a
## disabled one exactly as [method FrontmatterInput.commit] does. Clicking a node
## that is not a child of the focus is not special-cased: [method focus] accepts
## any id in the tree, and the collapsed nodes that would make it surprising are
## already unclickable — [HoverPreview] holds their pick regions at
## `MOUSE_FILTER_IGNORE`.
func _on_view_activated(id: StringName) -> void:
	var item := tree.get_item(id)
	if item == null or item.disabled:
		return
	focus(id)


## One edge per parent/child pair, keyed by the CHILD's id — a tree, so a child
## has exactly one incoming edge, which is also the "hero keeps its incoming
## edge" affordance #572 hangs its back button on.
func _build_edges() -> void:
	for id in tree.ids():
		for child_id in tree.children_of(id):
			var edge: MenuEdgeView = _EDGE_VIEW.instantiate()
			edge.name = "edge_%s" % child_id
			_graph_layer.add_child(edge)
			edge.connect_views(_views[id], _views[child_id])
			_edges[child_id] = edge


## Both endpoints of every edge, every frame of a transition. Cheap at nine
## edges, and it is what makes "edges never pop" true by construction rather
## than by nothing having moved yet.
func _push_edges() -> void:
	for child_id in _edges:
		var edge: MenuEdgeView = _edges[child_id]
		var parent_view: MenuNodeView = _views[tree.parent_of(child_id)]
		edge.set_endpoints(parent_view.position, (_views[child_id] as MenuNodeView).position)


## Tears down what a previous [method build] MADE, and nothing else.
##
## [b]It frees the tracked views and edges, never "every child of
## `%GraphLayer`".[/b] That layer also holds scene-authored siblings — #572's
## [BackAffordance] is parented there so it sits in graph space with the edge it
## decorates — and clearing the layer wholesale destroyed them on the very first
## build, since `build()` clears before it fills.
##
## It failed silently, which is the part worth remembering: `queue_free()`
## defers to end of frame, so everything later in the same frame still ran
## against a live object and every test passed. The node was simply gone a frame
## later. Found by #578's live tab, which reads the affordance one frame after
## build.
func _clear() -> void:
	for id in _views:
		var view: Node = _views[id]
		if is_instance_valid(view):
			view.get_parent().remove_child(view)
			view.queue_free()
	for key in _edges:
		var edge: Node = _edges[key]
		if is_instance_valid(edge):
			edge.get_parent().remove_child(edge)
			edge.queue_free()
	_views = {}
	_edges = {}
	_from_pose = {}
	_to_pose = {}


## The player's accessibility setting, read straight off [GameSettings].
##
## [b]A direct, statically-typed read, deliberately.[/b] `GameSettings`'s own
## docstring argues that retiring a setting must break every call site at
## COMPILE time rather than silently read as null — so renaming `reduce_motion`
## has to fail `mise run check` here, which a reflective `get_property_list()`
## lookup would have quietly swallowed by falling back to the export.
##
## The one guard is the EDITOR, and it is a different question: project
## autoloads are not in the editor's tree, and this script is `@tool` so #578's
## live tab can mount it. That is about the autoload existing, not the property.
func _resolve_reduce_motion() -> bool:
	if Engine.is_editor_hint():
		return reduce_motion
	return Settings.current.reduce_motion

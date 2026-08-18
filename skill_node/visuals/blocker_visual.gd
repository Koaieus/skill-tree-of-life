extends Node2D
## Boulder overlay for a removable-blocked node (#300 / #478). While the node
## reads as blocked, draws a neutral grey rock that dominates the node's inner
## disk. Three crack stages sync to the node's combat-HP fraction (intact >
## 66%, cracked ≤ 66%, shattered ≤ 33%) and refresh synchronously on the
## node's [signal SkillNode.damaged] — no frame wait. Crack stage does lag one
## idle frame behind a FRESH allocation (see [method _on_owner_changed_deferred]
## for why); that only delays picking up new ownership, never a mid-life
## damage tick.
##
## [b]Blocked is a LATCH, not a live predicate.[/b] The first entity to own
## this node (a blocker force-allocates its blocked node as its own core at
## spawn) is latched as `_latched_owner`; the node reads blocked for as long as
## [member SkillNode.owned_by] stays that entity. The instant ownership
## differs — including going back to null on the blocker's death — clearing is
## PERMANENT: a real entity re-allocating the node afterward must never
## re-show the boulder, even though `owned_by` briefly equals a non-blocker
## entity that could otherwise look plausible. `owned_by.core_class == null`
## was considered and rejected as the predicate: it can't distinguish "still
## the original blocker" from "some other null-core actor", and it re-derives
## every read instead of remembering the one fact that actually matters (who
## owned this first).
##
## Drives [member SkillNode.core_presence_suppressed] instead of reaching into
## the visual composite's private tree — the boulder fully replaces the
## CoreHalos gimbal a blocked node's force-allocated core would otherwise
## wear, and un-suppressing on clear is what lets the node's normal core
## presence come back once a real entity owns it. That write runs
## SYNCHRONOUSLY, not deferred like the crack-stage refresh — see
## [method _on_owner_changed_latch] for why the two halves of "react to
## owner_changed" need opposite timing.
##
## Fog mirrors every other owner-detail on the node (the disk, the addons):
## hidden while [member SkillNode.sensed]. Resynced off the node's
## [signal SkillNode.sensed_changed] (plus one initial sync in `_ready`) —
## deliberately not a `_process` poll; `sensed` gained a signal specifically so
## fog-reactive visuals don't need one (#478).
##
## [b]Not [code]@tool[/code][/b] — unlike [CoreHealthBar] (which opts in for
## the editor-hosted Spell Playground), there's no editor-preview use case
## here worth the scene-baking hazard (`.claude/rules/godot-workflow.md`): an
## `@tool` `_ready` writing `visible` while `blocker_node.tscn` is open in the
## editor would get serialized back into the scene on save. Staying non-tool
## sidesteps that outright — the boulder simply doesn't run until the scene is
## live in a real game/test tree.

## Crack stages are the contract (the exact boulder art is placeholder).
enum CrackStage { INTACT, CRACKED, SHATTERED }

## Node HP fraction at or below which the boulder reads "cracked" (≤ 66%).
const CRACKED_AT := 2.0 / 3.0
## Node HP fraction at or below which the boulder reads "shattered" (≤ 33%).
const SHATTERED_AT := 1.0 / 3.0

## Neutral grey — deliberately not the blocker's own entity tint, so the rock
## reads as an obstacle surface rather than a washed-out enemy disk.
const ROCK_COLOR := Color(0.46, 0.47, 0.53, 1.0)
const ROCK_SHADE := Color(0.27, 0.28, 0.33, 1.0)
const ROCK_HILITE := Color(0.60, 0.62, 0.68, 1.0)
const CRACK_COLOR := Color(0.13, 0.14, 0.17, 1.0)

## Fixed per-vertex radial jitter for the rocky silhouette (deterministic, not
## per-frame random) — a smooth circle reads as a marble, not a boulder.
const SILHOUETTE_JITTER: Array[float] = [
	1.00, 0.94, 1.02, 0.90, 1.00, 0.96, 1.04, 0.92,
	1.00, 0.95, 1.03, 0.91, 1.00, 0.97, 1.01, 0.93,
]

## Boulder footprint as a fraction of the node's [member SkillNode.radius].
const BOULDER_RADIUS_SCALE := 0.92

## How many crack lines each stage draws.
const CRACK_COUNTS: Array[int] = [0, 2, 4]

var crack_stage: CrackStage = CrackStage.INTACT

var _node: SkillNode = null

## The entity latched as "the blocker" — the first non-null [member
## SkillNode.owned_by] this node ever saw. Null until that first ownership.
var _latched_owner: Entity = null
## True once ownership has diverged from [member _latched_owner] even once.
## Permanent: never reset back to false.
var _cleared: bool = false


func _ready() -> void:
	_node = owner as SkillNode
	if _node != null:
		if not _node.damaged.is_connected(_on_damaged):
			_node.damaged.connect(_on_damaged)
		# TWO separate connections on the same signal, deliberately at
		# different priorities — see each handler's docstring for why one must
		# run early and the other must run late.
		if not _node.owner_changed.is_connected(_on_owner_changed_latch):
			_node.owner_changed.connect(_on_owner_changed_latch)
		if not _node.owner_changed.is_connected(_on_owner_changed_deferred):
			_node.owner_changed.connect(_on_owner_changed_deferred, CONNECT_DEFERRED)
		if not _node.sensed_changed.is_connected(_on_sensed_changed):
			_node.sensed_changed.connect(_on_sensed_changed)
	# Synchronous, matching `_on_owner_changed_latch` below — see its
	# docstring. A pre-owned scene node (dev_sandbox-style) has `owned_by`
	# already set as a baked @export by the time ANY `_ready` runs (property
	# deserialization predates the whole `_ready` pass), so there's no signal
	# to catch it; every node's own `_ready` re-derives from current state.
	_on_owner_changed_latch()
	# Deferred, matching `_on_owner_changed_deferred` below — see its
	# docstring for why crack stage / visibility can't run inline here.
	_on_owner_changed_deferred.call_deferred()


func _on_damaged(_amount: float, _source: Variant) -> void:
	_refresh_stage_and_visibility()


## Advances the latch + drives [member SkillNode.core_presence_suppressed].
## Connected PLAIN (not deferred) and deliberately runs FIRST among
## `owner_changed`'s listeners: Godot calls a child's `_ready` before its
## parent's, so this visual's connect call (in `_ready`, above) lands ahead of
## `SkillNode._ready`'s OWN `owner_changed.connect(_refresh_core_presence)` —
## and `core_presence_suppressed` has no setter of its own to trigger a
## re-sync, so it MUST already hold the right value by the time
## `_refresh_core_presence` reads it, not merely by the time this frame ends.
func _on_owner_changed_latch() -> void:
	_update_latch()
	if _node != null:
		_node.core_presence_suppressed = _is_blocked()


## Crack stage + visibility. Connected CONNECT_DEFERRED, matching
## health_bar.gd's `_on_owner_changed`: reading combat HP needs
## `SkillNode._refresh_hp_binding` to have already bound this node's
## `node_board` to the new owner's baseline, and that handler is connected
## AFTER this visual's own child-before-parent connect — so it hasn't run yet
## at the moment `owner_changed` fires synchronously. Reading HP inline here
## would see a stale/zero max and misreport SHATTERED at full health.
## Deferring runs this once the same-frame synchronous listeners (including
## the hp binding) have all fired.
func _on_owner_changed_deferred() -> void:
	_refresh_stage_and_visibility()


func _on_sensed_changed() -> void:
	_apply_visibility()


## Advances the latch state machine. Idempotent — safe to call on every
## `owner_changed`, including ones that don't move the latch at all.
func _update_latch() -> void:
	if _cleared or _node == null:
		return
	var cur := _node.owned_by
	if _latched_owner == null:
		if cur != null:
			_latched_owner = cur
		return
	if cur != _latched_owner:
		_cleared = true
		_latched_owner = null


func _is_blocked() -> bool:
	return not _cleared and _latched_owner != null


## Re-derive crack stage + visibility (NOT suppression — that's
## [method _on_owner_changed_latch]'s job, and must stay synchronous). Runs
## off `damaged` (inline) and `owner_changed` (deferred — see
## [method _on_owner_changed_deferred]), so `crack_stage` is correct the
## instant a hit lands with no extra frame wait, while still reading a
## correctly-bound HP pool on a fresh allocation.
func _refresh_stage_and_visibility() -> void:
	var blocked := _is_blocked()
	if blocked:
		_update_stage()
	else:
		crack_stage = CrackStage.INTACT
	_apply_visibility()


func _apply_visibility() -> void:
	visible = _is_blocked() and (_node == null or not _node.sensed)
	queue_redraw()


func _update_stage() -> void:
	var frac := _hp_fraction()
	if frac <= SHATTERED_AT:
		crack_stage = CrackStage.SHATTERED
	elif frac <= CRACKED_AT:
		crack_stage = CrackStage.CRACKED
	else:
		crack_stage = CrackStage.INTACT


func _hp_fraction() -> float:
	if _node == null:
		return 1.0
	var max_hp := _node.get_max_hp()
	if max_hp <= 0.0:
		return 0.0
	return _node.get_current_hp() / max_hp


func _radius() -> float:
	return _node.radius if _node != null else 0.0


func _draw() -> void:
	var r := _radius()
	if r <= 0.0 or not _is_blocked() or (_node != null and _node.sensed):
		return
	var base_r := r * BOULDER_RADIUS_SCALE
	_draw_rock(base_r)
	_draw_cracks(base_r)


## The boulder body: a jagged grey polygon with a darker rim and a top-left
## highlight, so it reads as an opaque rock sitting over the disk rather than a
## flat grey disc.
func _draw_rock(base_r: float) -> void:
	var pts := _silhouette(base_r)
	draw_colored_polygon(pts, ROCK_COLOR)
	draw_polyline(pts, ROCK_SHADE, 2.0, true)
	# Off-centre highlight patch for a rounded-rock read.
	var hilite := _silhouette(base_r * 0.62)
	for i in hilite.size():
		hilite[i] += Vector2(-base_r * 0.14, -base_r * 0.14)
	draw_colored_polygon(hilite, Color(ROCK_HILITE.r, ROCK_HILITE.g, ROCK_HILITE.b, 0.35))


## Jagged circular silhouette, jittered by the fixed table.
func _silhouette(base_r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var count := SILHOUETTE_JITTER.size()
	for i in count:
		var angle := TAU * float(i) / float(count)
		pts.append(Vector2.from_angle(angle) * (base_r * SILHOUETTE_JITTER[i]))
	return pts


func _draw_cracks(base_r: float) -> void:
	var count := CRACK_COUNTS[int(crack_stage)]
	for i in count:
		_draw_crack(_crack_angle(i, count), base_r * 0.92)


## Deterministic spread: cracks radiate evenly from the centre, offset so a
## 2-crack and a 4-crack stage don't line up identically.
func _crack_angle(i: int, count: int) -> float:
	return TAU * float(i) / float(count) + 0.35


## One jagged crack: a polyline from near the centre to the rim, with a small
## deterministic perpendicular jitter per segment.
func _draw_crack(angle: float, length: float) -> void:
	var dir := Vector2.from_angle(angle)
	var perp := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array()
	pts.append(dir * length * 0.08)
	for s in 4:
		var t := float(s + 1) / 4.0
		var jitter := sin(angle * 7.0 + float(s) * 2.4) * 3.0
		pts.append(dir * (length * t) + perp * jitter)
	draw_polyline(pts, CRACK_COLOR, 2.0, true)

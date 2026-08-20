extends Node2D
## Boulder overlay for a removable-blocked node (#300 / #478). While the node
## reads as blocked, draws a neutral grey rock that dominates the node's inner
## disk. Three crack stages sync to the node's combat-HP fraction (intact >
## 66%, cracked ≤ 66%, shattered ≤ 33%).
##
## [b]Crack stage is combat PAINT, so it honours the presentation clock
## (#479/#482/#491).[/b] Model HP mutates synchronously on `take_damage`, but a
## blocked node must not visibly crack before the hit that caused it has
## actually landed on screen. [method _on_view_state_changed] re-syncs the
## stage off [signal SkillNode.view_state_changed] — [PresentationPlayer]'s own
## reveal cadence — so a rapid multi-hit exchange still lands on the FINAL HP
## fraction rather than replaying each intermediate stage. Crack stage ALSO
## lags one idle frame behind a FRESH allocation (see `_ready`'s docstring for
## why); that only delays picking up new ownership, never a mid-life damage tick.
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
## Drives [member SkillNode.core_halo_style] in lockstep with the latch — COG
## (the cheap preset) while blocked, `-1` (Default, restoring whatever
## `core_presence.tscn` authored — GIMBAL today) once cleared. Core presence
## itself stays ACTIVE the whole time; it's cheaper to keep it on the
## cog-machinery style than to suppress-and-restore it, and a level can spawn
## several blockers (GIMBAL's per-frame quaternion chain is expensive at a
## handful of instances — see that export's docstring). `blocker_node.tscn`
## also pins the style to COG statically so a freshly-instantiated-but-not-yet-
## allocated node never has a stray frame of GIMBAL before this script's first
## deferred sync runs; this script's write is what makes the `-1` restore on
## clear possible; the boulder simply draws over whichever style is live.
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

## Plain-int mirrors of [member SkillNode.core_halo_style]'s own
## `@export_enum` values — [CoreHalos] deliberately carries no `class_name`
## (see .claude/rules/skill-node-visuals.md), so there's no enum type to
## reference here either; these name the two values this script actually uses.
const _HALO_STYLE_DEFAULT := -1
const _HALO_STYLE_COG := 4

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
		# CONNECT_DEFERRED, matching health_bar.gd's `_on_owner_changed`:
		# reading combat HP needs `SkillNode._refresh_hp_binding` to have
		# already bound this node's `node_board` to the new owner's baseline.
		# Godot calls a child's `_ready` before its parent's, so this visual's
		# connect call (here) lands AHEAD of `SkillNode._ready`'s own
		# `owner_changed.connect(_refresh_hp_binding)` — a plain connection
		# would run this handler first and read a stale/zero max, misreporting
		# SHATTERED at full health. Deferring runs it once the same-frame
		# synchronous listeners (including the hp binding) have all fired.
		if not _node.owner_changed.is_connected(_on_owner_changed):
			_node.owner_changed.connect(_on_owner_changed, CONNECT_DEFERRED)
		if not _node.sensed_changed.is_connected(_on_sensed_changed):
			_node.sensed_changed.connect(_on_sensed_changed)
			# #491: crack stage re-syncs off the node's own DRAWN hp, pushed by
			# PresentationPlayer — replaces the old 'damaged' + hold/release
			# catch-up trio with one signal.
		if not _node.view_state_changed.is_connected(_on_view_state_changed):
			_node.view_state_changed.connect(_on_view_state_changed)
	# Deferred for the same reason as the connect above. Establishes the
	# initial latch (a freshly-spawned blocker's force_allocate already ran
	# before this visual entered the tree, so `owned_by` is non-null here) and
	# syncs crack stage / visibility for the first frame, once SkillNode's own
	# `_ready` has bound the node_board.
	_on_owner_changed.call_deferred()


## #491: the node's DRAWN hp changed — re-sync the crack stage against it.
## Fires on PresentationPlayer's own reveal cadence, so a rapid multi-hit
## exchange still lands on its FINAL hp fraction rather than replaying every
## intermediate step (each push already IS the intermediate step).
func _on_view_state_changed(_hp: float, _owner: Entity) -> void:
	_refresh_stage_and_visibility()


func _on_owner_changed() -> void:
	_update_latch()
	if _node != null:
		_node.core_halo_style = _HALO_STYLE_COG if _is_blocked() else _HALO_STYLE_DEFAULT
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


## Re-derive crack stage + visibility. Runs off `damaged` (inline) and
## `owner_changed` (deferred — see `_ready`'s docstring), so `crack_stage` is
## correct the instant a hit lands with no extra frame wait, while still
## reading a correctly-bound HP pool on a fresh allocation.
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
	return _node.shown_hp / max_hp


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

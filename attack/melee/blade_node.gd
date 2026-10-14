@tool
class_name BladeNode
extends Node2D

## Pure visual — its position is written each playback frame by SkillBlade
## from a BladeTrajectory sample. No physics, no collision.

const DEFAULT_STYLE: BladeStyle = preload("res://attack/melee/default_blade_style.tres")

@export_range(1.0, 100., 1.0) var radius: float = 32.0:
	set(value):
		radius = value
		_reconfigure()

## Inner-disk radius, mirroring [member SkillNode.base_inner_radius] (default
## 24) so a blade node fills the same disc the SkillNode it was built from
## does. The band between this and [member radius] is where the rim strokes.
@export_range(1.0, 100.0, 1.0) var inner_radius: float = 24.0:
	set(value):
		inner_radius = value
		_reconfigure()

@export var is_pivot: bool = false:
	set(value):
		is_pivot = value
		_reconfigure()

## Look profile (#256). Falls back to [constant DEFAULT_STYLE] so a bare
## `blade_node.tscn` still draws.
@export var style: BladeStyle = null:
	set(value):
		if style != null and style.changed.is_connected(_reconfigure):
			style.changed.disconnect(_reconfigure)
		style = value
		if style != null:
			style.changed.connect(_reconfigure)
		_reconfigure()

## The wielder's identity colour, blended in per [member BladeStyle.entity_tint].
## Transparent means "no owner" — the authored base is used as-is.
@export var tint: Color = Color.TRANSPARENT:
	set(value):
		tint = value
		_reconfigure()

## Pop state (#787), replacing the old #256 de-lit interim: `0.0` while alive,
## then `clampf((t - dead_at) / window, 0.0, 1.0)` for the rest of the swing —
## driven every playback frame by [member SkillBlade._apply_playback_frame] as
## a pure function of (dead_at, t), never a fired-once animation
## (`.claude/rules/presentation-clock.md`). Also settable by hand for look
## tuning (`addons/melee_sandbox`'s forced de-lit slider).
##
## The instant this leaves 0.0 the disc stops drawing entirely — "pop is
## immediate, no glow up first" (owner, 2026-09-10) — and [SkillBlade] spawns
## this vertex's shards into its [ShatterField] on that same transition. The
## float only continues to matter after that instant for [BladeEdge]'s
## fuse-burn draw, which needs a ramp to erode along.
@export_range(0.0, 1.0) var death_progress: float = 0.0:
	set(value):
		var clamped := clampf(value, 0.0, 1.0)
		if death_progress == clamped:
			return
		death_progress = clamped
		_reconfigure()

## Explosive charges this piece holds right now: one bead each on a band inside
## the rim, none at 0. [SkillBlade] sets it at build and, during playback,
## re-derives it every frame from the contacts at or before `t` — a channel,
## like [member death_progress], never a counter decremented by events.
@export_range(0, 32, 1) var charges: int = 0:
	set(value):
		value = maxi(value, 0)
		if charges == value:
			return
		charges = value
		_reconfigure()

## The latest spend's flare: `0.0` until a contact spends this piece's charges,
## then `clampf((t - contact.t) / BladeStyle.spend_window, 0, 1)` — the spent
## bead flares out and fades. Driven per frame like [member death_progress];
## settable by hand for look tuning (`addons/melee_sandbox`).
@export_range(0.0, 1.0) var spend_progress: float = 0.0:
	set(value):
		var clamped := clampf(value, 0.0, 1.0)
		if spend_progress == clamped:
			return
		spend_progress = clamped
		_reconfigure()

## The latest shrug's sheen: `0.0` until a node's blast spares this charged
## piece (a SHRUGGED verdict), then `clampf((t - contact.t) /
## BladeStyle.shrug_window, 0, 1)` — a protective band expands over the rim and
## fades. Exclusive with [member spend_progress] per contact. Driven per frame
## like [member death_progress]; settable by hand (`addons/melee_sandbox`).
@export_range(0.0, 1.0) var shrug_progress: float = 0.0:
	set(value):
		var clamped := clampf(value, 0.0, 1.0)
		if shrug_progress == clamped:
			return
		shrug_progress = clamped
		_reconfigure()

## The sight marker a scout vertex carries (`ui/fog_overlay/lantern.tscn`,
## set in `blade_node.tscn`). Injected, never preloaded: `attack/` sits below
## `ui/`, so this script treats the instance as a plain [Node2D] with
## `radius`/`source` properties. Null means this vertex can never light.
@export var lantern_scene: PackedScene = null

@onready var _visual: Node2D = $Visuals/BladeCircle

## The one marker this vertex carries once lit, a child at local zero — so it
## sits on the drawn vertex whatever playback writes to [member global_position],
## and frees with it. Null while unlit.
var _lantern: Node2D = null

## Draws the charge beads; authored after `Visuals` so it paints over the disc.
@onready var _charge_band: BladeChargeBand = $ChargeBand


func _ready() -> void:
	_reconfigure()


func _reconfigure() -> void:
	if not is_node_ready():
		return
	_visual.configure(
			radius, inner_radius, is_pivot,
			style if style != null else DEFAULT_STYLE, tint, death_progress,
			shrug_progress)
	_charge_band.configure(
			radius, inner_radius, charges, spend_progress,
			style if style != null else DEFAULT_STYLE, death_progress > 0.0)


## Light this vertex for [param source]'s camp: instances [member lantern_scene]
## once and keeps it (a second call only re-points its source). The radius is
## [param radius] when positive, else the scene's own default.
func light_lantern(source: Entity, radius: float = 0.0) -> void:
	if _lantern == null:
		if lantern_scene == null:
			return
		_lantern = lantern_scene.instantiate() as Node2D
		add_child(_lantern)
	_lantern.set(&"source", source)
	if radius > 0.0:
		_lantern.set(&"radius", radius)


## The lit marker, or null — for tests and the sandbox.
func get_lantern() -> Node2D:
	return _lantern


## Returns the point on this node's circumference facing `world_target`.
## BladeEdge uses this to trim edges to the rim.
func edge_point(world_target: Vector2) -> Vector2:
	var dir := (world_target - global_position).normalized()
	return global_position + dir * radius


func _to_string() -> String:
	return "<BladeNode>"

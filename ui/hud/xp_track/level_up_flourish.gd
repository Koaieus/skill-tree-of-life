@tool
class_name LevelUpFlourish
extends Control

## The level-up announcement, living on the XP track instead of center screen
## (#320). Owned and paced by [XpTrack].
##
## [b]Why it moved off [AnnouncementLayer].[/b] The center [TitleBand] runs a
## fixed timeline — 0.30s in, 1.20s hold, 0.30s out — and the hold is a step in
## a chained tween that cannot grow. A level segment takes ~1.1-1.35s, so a
## four-level cascade outlived the banner: it stamped "×2", slid out while
## levels 3 and 4 were still landing, and a second banner opened behind it. The
## fix was never a longer hold, because the banner is structurally unable to
## know whether more levels are coming. The XP bar is: it holds the queue. So
## the announcement belongs to the thing that owns the timeline, and the center
## of the screen — the most valuable real estate the HUD has — goes back to
## YOUR TURN and the kill line.
##
## The contract is therefore [b]stamp until told to stop[/b], not "play for N
## seconds": [method stamp] once per level, [method release] when the cascade
## drains. Nothing here decides when it ends.
##
## Anchored inside a plain (non-container) [Control] so it cannot reflow the
## strip it decorates — same rule as [XpDeltaChip], and the same warning:
## never re-parent this into a Container.

## The XP track's gold. Matches the gauge's `fill_color`; the emissive lift is
## authored as a named tier, never a hand-picked float (`.claude/rules/hdr-color.md`).
const GOLD := Color(0.8909, 0.7204, 0.2596)

## Minimum time on screen after the LAST stamp. A single level-up would
## otherwise flash and leave inside the wrap; a cascade re-arms this on every
## stamp, so the tail is measured from the last level, not the first.
@export_range(0.0, 1.5, 0.05) var min_dwell: float = 0.35
@export_range(0.0, 1.0, 0.02) var open_time: float = 0.14
@export_range(0.0, 1.0, 0.02) var stamp_time: float = 0.10
@export_range(0.0, 1.5, 0.02) var fade_time: float = 0.28
## How far the flourish drifts up as it leaves, in pixels.
@export var exit_rise: float = -8.0

## Inspector button: play a sample cascade for live preview in the editor.
@export_tool_button("Preview") var _preview_button: Callable = _preview

@onready var _title: Label = %Title
@onready var _detail: Label = %Detail

var _tween: Tween
var _release_timer: SceneTreeTimer
## Set on the first stamp of a cascade — see the note on [member _rest_position].
var _rest_position: Vector2
var _rest_captured: bool = false
var _open: bool = false


## Applied lazily on the first stamp, NOT in `_ready`. The colours have to be
## written in code — `Emissive.at` is the only sanctioned way to author an HDR
## value, so the .tscn would otherwise carry two hand-typed floats nothing could
## re-derive — but this is a `@tool` script, and a node property written at load
## time dirties the scene just by opening it. First stamp never happens on load.
## Same reasoning as [XpDeltaChip]'s lazily captured rest position.
var _colors_applied: bool = false


func _apply_colors() -> void:
	if _colors_applied:
		return
	_colors_applied = true
	_title.add_theme_color_override(&"font_color", Emissive.at(GOLD, Emissive.ALERT))
	_detail.add_theme_color_override(&"font_color", Emissive.at(GOLD, Emissive.VALUE))


## Announce one level. The first call opens the flourish; every later one
## re-stamps it in place with a pop, so a cascade is ONE element counting up
## rather than N elements queued behind each other.
##
## [param stack] is how many levels this cascade has now narrated — shown as
## "×N" from 2 up. [param sp_total] is the skill points those levels minted
## between them, asked of [method Entity.sp_minted_for_level] per level, since
## the milestone rule makes every 5th level worth more.
func stamp(level: int, sp_total: int, stack: int) -> void:
	_apply_colors()
	if not _rest_captured:
		_rest_position = position
		_rest_captured = true
	_cancel_release()
	_title.text = "L E V E L   U P" if stack <= 1 else "L E V E L   U P  ×%d" % stack
	_detail.text = "+%d SP — LEVEL %d" % [sp_total, level]
	if _tween != null and _tween.is_valid():
		_tween.kill()
	position = _rest_position
	modulate.a = 1.0
	# Scale about the centre, so the pop grows both ways off the bar's midline
	# instead of shoving the text right.
	pivot_offset = size * 0.5
	var from_scale := 1.28 if not _open else 1.14
	var duration := open_time if not _open else stamp_time
	scale = Vector2.ONE * from_scale
	_open = true
	_tween = create_tween()
	_tween.tween_property(self, ^"scale", Vector2.ONE, duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The cascade is over: leave, once [member min_dwell] has been served from the
## last stamp. Safe to call when nothing is up, and safe to call twice.
func release() -> void:
	if not _open:
		return
	_cancel_release()
	_release_timer = get_tree().create_timer(min_dwell)
	_release_timer.timeout.connect(_play_exit)


## Cut to hidden with no animation — for a rebind, where the flourish would
## otherwise finish narrating the previous hero's levels on the new one's bar.
func cut() -> void:
	_cancel_release()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_open = false
	modulate.a = 0.0
	scale = Vector2.ONE
	if _rest_captured:
		position = _rest_position


func _play_exit() -> void:
	_release_timer = null
	if not _open:
		return
	_open = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, ^"modulate:a", 0.0, fade_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, ^"position:y", _rest_position.y + exit_rise, fade_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## A pending release is armed against a SceneTreeTimer, which cannot be
## cancelled — so disconnect instead, and drop the reference.
func _cancel_release() -> void:
	if _release_timer != null:
		if _release_timer.timeout.is_connected(_play_exit):
			_release_timer.timeout.disconnect(_play_exit)
		_release_timer = null


func _preview() -> void:
	stamp(7, 2, 1)
	await get_tree().create_timer(0.45).timeout
	stamp(8, 4, 2)
	await get_tree().create_timer(0.45).timeout
	stamp(9, 6, 3)
	release()

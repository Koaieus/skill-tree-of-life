@tool
class_name XpDeltaChip
extends Label

## "+3 XP" chip that pops above the XP gauge and fades (#317). Replaces the
## player's XP floater toast entirely — the player reads XP off the HUD gauge,
## so a toast that flew off the Hero Sigil anchor was narrating a number the
## eye was already on. NPCs keep their core toast (see [FloaterDirector]), since
## they have no gauge.
##
## Anchored INSIDE the gauge (a ColorRect, not a Container) precisely so it
## can't reflow the XP row: a Control child of a non-container parent takes no
## part in layout. Never re-parent this into the row's HBoxContainer.

## Total rise over the chip's life, in pixels (negative = up).
@export var rise_distance: float = -14.0
@export_range(0.0, 2.0, 0.05) var hold_time: float = 0.45
@export_range(0.0, 2.0, 0.05) var fade_time: float = 0.35

## Inspector button: pop a sample chip for live preview in the editor.
@export_tool_button("Preview") var _preview_button: Callable = func(): show_delta(3.0)

## Amount currently being displayed. A second grant while the chip is still up
## adds into it rather than replacing it — two sources in one turn (passive
## income and a kill reward) read as one "+N", not a flicker between numbers.
var _shown_amount: float = 0.0

var _tween: Tween
## Where the chip sits when idle, captured LAZILY on the first pop. This is
## anchor-positioned, and anchors only resolve on the layout pass *after*
## `_ready` — snapshotting there would bank (0,0) and every pop would then
## teleport the chip to the gauge's top-left corner and keep it there, since
## each pop restores the same wrong value. Also note resting invisibility is
## AUTHORED in the .tscn (modulate alpha 0) rather than written in `_ready`: a
## @tool script that writes node properties there dirties the scene on load.
var _rest_position: Vector2
var _rest_captured: bool = false


func show_delta(amount: float) -> void:
	if amount <= 0.0:
		return
	if not _rest_captured:
		_rest_position = position
		_rest_captured = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	else:
		_shown_amount = 0.0
	_shown_amount += amount
	text = "+%d XP" % int(round(_shown_amount))
	position = _rest_position
	modulate.a = 1.0
	# The rise spans the whole life; the fade rides along, delayed until the
	# number has had its hold. `set_delay` (not a chained interval) is what lets
	# the two overlap — a chain would make the fade wait for the rise to land.
	_tween = create_tween()
	_tween.tween_property(self, ^"position:y", _rest_position.y + rise_distance,
			hold_time + fade_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.parallel().tween_property(self, ^"modulate:a", 0.0, fade_time) \
			.set_delay(hold_time)
	_tween.tween_callback(func() -> void: _shown_amount = 0.0)

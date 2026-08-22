class_name FocusDecision
extends RefCounted

## The answer to one [FocusRequest] — a pure value, produced by
## [method CameraDirector.decide] and consumed by the camera (#523).
##
## [member target] is ALREADY CLAMPED to what `GraphCamera._clamp_position`
## will allow. That is the whole reason the decision carries a target at all
## rather than the director poking the camera: an acceptance test asserts the
## RESULTING visible rect against the span it asked for, and a test that
## asserts what the director *requested* passes while the feature is broken.

## Whether the camera should move at all. False carries the why in
## [member reason].
var act: bool = false
## Why. `&"ok"` when acting; `&"empty"` / `&"fogged"` (nothing to frame),
## `&"grace"` (the player's hands are still on it), `&"on_screen"` (already
## comfortably framed) when not.
var reason: StringName = &"empty"
## Where the camera should end up, post-clamp.
var target: Vector2 = Vector2.ZERO
## The world-space size the decision tried to fit — the span plus its margin.
var fit_size: Vector2 = Vector2.ZERO
## The zoom to take. Never smaller than the lattice floor, never larger than
## the zoom the player already chose.
var zoom_target: float = 1.0
## Ease duration for the pan; 0.0 is a hard cut.
var duration: float = 0.0
## Seconds to hold after the pan settles.
var hold: float = 0.0
## True when the pan clamp moved [member target] away from the ideal centre.
## Not a failure — it is what the clamp does near a map edge — but a test
## asserting "the span is on screen" must branch on it.
var clamped: bool = false
## True when the span does not fit even at the lattice floor, so
## [member target] is the span's CENTER OF MASS and the edges fall off screen.
## A normal outcome (a 20-hop melee blade reaches it), not an error: no
## warning, no `push_warning` (#515 decision 6).
var center_of_mass: bool = false


static func no(why: StringName) -> FocusDecision:
	var d := FocusDecision.new()
	d.act = false
	d.reason = why
	return d


## The world rect the camera will actually show if this decision is applied.
## What acceptance asserts against.
func resulting_rect(viewport_size: Vector2) -> Rect2:
	var size := viewport_size / zoom_target
	return Rect2(target - size * 0.5, size)


func _to_string() -> String:
	if not act:
		return "FocusDecision(no: %s)" % reason
	return "FocusDecision(%s @ %s zoom %.2f%s%s)" % [
		target, fit_size, zoom_target,
		" clamped" if clamped else "",
		" com" if center_of_mass else "",
	]

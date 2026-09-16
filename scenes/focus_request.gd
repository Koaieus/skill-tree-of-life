class_name FocusRequest
extends RefCounted

## "Look at this." One ask handed to [method CameraDirector.decide] (#523).
##
## A request names WHAT to frame — a set of world points — and how long to hold
## it. It never names a camera position or a zoom: those are the decision's
## job, because only the decision knows the current view, the grace window and
## the pan clamp.

## The world positions to frame. The span is their AABB; the fallback centre
## (when the span does not fit even at the zoom floor) is their centroid.
var points: PackedVector2Array = PackedVector2Array()
## Who asked, for logging and for reading a [FocusDecision] in a test.
var source: StringName = &"unknown"
## Ease duration for the pan. 0.0 is a hard cut.
var duration: float = 0.35
## Seconds to keep the camera after the pan settles, before releasing it.
var hold: float = 0.0
## Bypasses the grace window and the skip-if-on-screen check. Set only by a
## focus the player themselves triggered — a hot-seat handover re-points the
## view because the seat changed hands, and must fire unconditionally or #459's
## behaviour changes.
var mandatory: bool = false
## May the decision step the zoom OUT to fit the span? False for a point focus,
## which has nothing to fit.
var allow_zoom_out: bool = true
## What [method CameraDirector.decide] reports when [member points] is empty.
## An attack whose every contributing node is fogged is a distinct outcome from
## a malformed request, and #524's acceptance names it — so the builder that
## did the filtering says which emptiness this is, rather than `decide`
## inferring it from [member source].
var empty_reason: StringName = &"empty"


## A single-point focus: no span to fit, so no zoom change is ever considered.
static func point(at: Vector2, duration_seconds: float = 0.35,
		is_mandatory: bool = false, from: StringName = &"point") -> FocusRequest:
	var req := FocusRequest.new()
	req.points = PackedVector2Array([at])
	req.duration = duration_seconds
	req.mandatory = is_mandatory
	req.allow_zoom_out = false
	req.source = from
	return req


## A span focus: frame every point, stepping the zoom out if they do not fit.
static func span(world_points: PackedVector2Array, duration_seconds: float = 0.35,
		hold_seconds: float = 0.0, from: StringName = &"span") -> FocusRequest:
	var req := FocusRequest.new()
	req.points = world_points
	req.duration = duration_seconds
	req.hold = hold_seconds
	req.source = from
	return req


## AABB of [member points]. Zero-size for a single point; empty rect for none.
func bounds() -> Rect2:
	if points.is_empty():
		return Rect2()
	var rect := Rect2(points[0], Vector2.ZERO)
	for i in range(1, points.size()):
		rect = rect.expand(points[i])
	return rect


## Centroid of [member points] — the CENTER OF MASS, deliberately not the AABB
## midpoint. For a two-point ranged shot they coincide; for a spell radiating
## lopsidedly across forty nodes the midpoint points at empty space while this
## points at the dense part, which is where the action is (#515 decision 6).
func center_of_mass() -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in points:
		sum += p
	return sum / float(points.size())

class_name CameraContext
extends RefCounted

## Everything [method CameraDirector.decide] is allowed to know about the
## camera, as PLAIN VALUES (#523).
##
## The point is that `decide` never reads a live [GraphCamera]: GUT is
## headless, easing is not assertable in pixels, and every policy question the
## director answers — grace window, skip-if-on-screen, fit-or-zoom-out, and the
## pan clamp — is answerable from these seven numbers. A test constructs one of
## these directly and asserts a [FocusDecision].
##
## [member graph_bounds] / [member pan_margin_base] / [member min_zoom_floor]
## are here for the CLAMP. `_clamp_position()` runs every frame regardless of
## who asked for the move, so a focus near a map edge is silently pulled back
## and the span lands off-screen with nothing erroring. Since
## `GraphCamera._update_limits` derives `limit_*` entirely from
## `_graph_bounds.grow(_pan_margin_base / zoom)`, the clamp is computable here
## — so [method CameraDirector.decide] returns a target that is ALREADY
## clamped, and the acceptance test asserts the resulting visible rect rather
## than the requested one.

## Viewport size in pixels. Visible world size is this divided by [member zoom].
var viewport_size: Vector2 = Vector2(1440, 960)
## The camera's authoritative zoom TARGET (`GraphCamera._target_zoom`), not the
## fractional mid-tween `zoom.x` — the same distinction `_zoom_by` makes.
var zoom: float = 1.0
## The camera's current world-space center (`global_position`).
var center: Vector2 = Vector2.ZERO
## Raw world AABB of the level's SkillNodes (`GraphCamera._graph_bounds`).
## A zero-size rect means "no bounds pushed yet" and disables the clamp,
## mirroring `_update_limits`'s own early return — without that mirror a
## headless test would clamp against Camera2D's default ±1e7 limits and every
## assertion would pass vacuously.
var graph_bounds: Rect2 = Rect2()
## Pan slack at zoom == 1.0 (`GraphCamera._pan_margin_base`).
var pan_margin_base: float = 400.0
## The level's effective zoom-out floor (`GraphCamera._min_zoom_floor`) — an
## arbitrary float, NOT a multiple of the director's 0.25 lattice. Pushed at
## runtime by `GameRoot._apply_graph_bounds`, so it cannot be a constant.
var min_zoom_floor: float = GraphCamera.MIN_ZOOM
## Seconds since the last manual pan/zoom. [constant INF] means "the player has
## not touched the camera this session". Carried in the context rather than
## read off the director's own clock so `decide` stays pure.
var seconds_since_manual_input: float = INF


static func make(viewport: Vector2, zoom_value: float, center_value: Vector2) -> CameraContext:
	var ctx := CameraContext.new()
	ctx.viewport_size = viewport
	ctx.zoom = zoom_value
	ctx.center = center_value
	return ctx


## World-space size of what the camera shows at [param at_zoom] (defaults to
## the context's own zoom).
func visible_size(at_zoom: float = -1.0) -> Vector2:
	var z: float = at_zoom if at_zoom > 0.0 else zoom
	return viewport_size / z


## World-space rect the camera shows, centred on [member center].
func visible_rect(at_zoom: float = -1.0) -> Rect2:
	var size := visible_size(at_zoom)
	return Rect2(center - size * 0.5, size)

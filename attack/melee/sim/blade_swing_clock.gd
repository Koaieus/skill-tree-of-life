class_name BladeSwingClock
extends RefCounted

## The swing's own clock, and the channel Fortification's drag acts on (#780).
##
## [b]Drag slows the CLOCK, never a particle.[/b] Subtracting velocity from a
## particle on a rigid blade does nothing: the distance constraints fight it,
## and then [method BladeSim._step] re-applies the drivers AFTER the Verlet
## integration, so [method BladeArcDriver.apply] — a pure function of its
## argument — overwrites the damped position outright. Particle-level damping
## therefore has no effect on exactly the rigid blade it is meant to slow.
## (That is also why [member BladeSim.simulate]'s `linear_damping` is the wrong
## channel: it is the free-flight knob for an UNPINNED fragment, where there is
## no driver to overwrite anything.) What drag can move is the argument itself —
## the angular progress `f` the arc driver evaluates its ease curve at.
##
## [b]Where this sits under ADR 0005.[/b] A spike destroys matter, a bunker
## destroys structure, and a wall destroys neither — it spends the swing's
## budget instead. Drag removes no blade part, so it is a THIRD defensive
## effect that cannot violate the ADR's vertex/edge disjointness rather than an
## exception to it. Sensing on capsules as well as discs (below) is a question
## of what the swing TOUCHES, not of which blade part is doing the defending, so
## it does not disturb that either.
##
## [b]Monotonic by construction.[/b] [member _f] only ever has a non-negative
## quantity added and is clamped at 1: the warp factor [method warp] is
## `1 / (1 + drag)` with `drag >= 0`, hence strictly positive and at most 1. No
## configuration of fortified nodes can reverse a swing, and none can freeze one
## either — the hard stall is #781's bunker, not this. What a wall does instead
## is spend the arc: five nodes at drag 1 leave the swing running at a sixth of
## its nominal rate, so within the fixed swing duration it covers roughly a
## sixth of its sweep and everything further round the arc is simply never
## reached. That is how a wall protects what is behind it without deleting,
## severing or cascading anything.
##
## [b]Causal, not global.[/b] A zone's drag is added only once its own contact
## has happened, so it slows the REST of the arc and never the approach to
## itself. A global warp would be paradoxical: a fortified node at the end of
## the sweep would retroactively prevent the swing from ever reaching it.
##
## [b]One sensing model, since #811.[/b] This class no longer senses anything.
## It is handed a contact — [method bank_drag] — by [BladeObstacleField], which
## carries the single merged defender field and tests the blade against it with
## the same geometry its bunker pushout uses. What this class owns is the
## ACCUMULATOR and the physics above it: which zones have been banked, how much
## drag they add up to, and how that warps the arc.
##
## Before #811 there were three hand-rolled implementations of "blade vertex
## disc / rim-trimmed edge capsule vs. node disc" — [BladeHitScan]'s physics
## query, this class's analytic `sense()`, and the obstacle field's pushout —
## kept in step only by a shared const and a comment. The seam they were
## separated by ("the solver must never touch the space state, because
## [AiBladeRollout] simulates off-thread") turned out to be narrower than it
## looked: the FIELD is built on the main thread by one physics query and then
## consumed as plain arrays, so the off-thread solver queries nothing. See
## docs/adr/0014-one-physics-built-defender-field.md.

## Nominal swing duration — the same value the drivers were built with.
var duration: float = 1.2

## Accumulated drag from every zone touched so far. Never decreases.
var drag: float = 0.0

## Indices into [member BladeObstacleField.zones] already counted. A zone
## contributes its drag AT MOST ONCE for the whole swing — never disc +
## capsule, never once per incident edge, and never twice for a node that
## carries `deflection` as well as `swing_drag` (that is ONE zone of two kinds,
## #811). This is the only latch: [BladeObstacleField.project] asks
## [method has_banked] rather than keeping a second set of its own.
var touched: Dictionary = {}

## Warped angular progress. Meaningful only once [member _warping] is true; see
## [method progress] for why it does not exist before that.
var _f: float = 0.0

## False until the first contact. [b]This is load-bearing, not an
## optimisation.[/b] Accumulating `f` in float steps from t=0 would drift from
## `t / duration` in the last bits, so a swing that merely has a fortified node
## in its FIELD — but never touches it — would produce a different trajectory
## from one that has none at all. Acceptance 5 ("drag has no effect on a blade
## that never contacts a fortified node") is a bit-exactness claim, and this
## flag is what makes it one: before first contact [method progress] declines to
## answer and the driver evaluates its original `t / duration` expression,
## unchanged, character for character.
var _warping: bool = false

## The most recent `t` a driver asked about, kept so the accumulator can be
## seeded from the exact pre-contact progress at the moment drag first lands.
var _last_t: float = 0.0

## The hard stall (#781): set once a DRIVEN grip particle touches a bunker, and
## never cleared — [method warp] is then exactly 0, so [member _f] stops where
## it is and every arc driver holds its particle on the plate for the rest of
## the swing while everything outboard keeps simulating on its own momentum.
## Still monotonic: `_f` gains 0, never loses. Deliberately not expressed as
## `drag = INF`; a flag reads as the distinct mechanism it is.
var _stalled: bool = false


func _init(duration_: float = 1.2) -> void:
	duration = duration_


## True once at least one zone has been touched — i.e. once this clock is
## actually diverging from nominal time.
func is_warping() -> bool:
	return _warping


## The [Bank] at every sample of the chunk [method BladeSim.simulate_range] last
## ran with this clock, parallel to that chunk's `samples` (`history[0]` is the
## bank on entry) — chunk-local and rebuilt every call, exactly like
## [member BladeState.speed_history] (#803). A severance at local sample `j`
## rewinds with `restore(history[j])`, which lands on the same bank a replay of
## the head would have re-ticked to, without running one.
var history: Array[Bank] = []


## Everything on this clock that a substep MUTATES, captured so the resolve loop
## can rewind it (#801). [b]The clock is sim state[/b] — `_f`, banked `drag`,
## which zones it has `touched` — so replaying a span of the swing to recover an
## exact pose must replay the clock with it. Restoring a FRESH clock instead
## would un-bank a Fortification wall's drag mid-swing and silently stop it
## sheltering what is behind it. The zones themselves are not in here: they
## live on [BladeDefenderZones], are built once before the sim, and never
## change — which is also what lets one zone set be SHARED across a pivot's
## whole rollout while each swing banks its own drag (#811).
class Bank extends RefCounted:
	var f: float
	var drag: float
	var touched: Dictionary
	var warping: bool
	var last_t: float
	var stalled: bool


## Capture [Bank] — the mutable half of this clock. `touched` is duplicated, so
## a later [method bank_drag] cannot write through the snapshot.
func capture() -> Bank:
	var b := Bank.new()
	b.f = _f
	b.drag = drag
	b.touched = touched.duplicate()
	b.warping = _warping
	b.last_t = _last_t
	b.stalled = _stalled
	return b


## Rewind to [param b] — the exact inverse of [method capture].
func restore(b: Bank) -> void:
	if b == null:
		return
	_f = b.f
	drag = b.drag
	touched = b.touched.duplicate()
	_warping = b.warping
	_last_t = b.last_t
	_stalled = b.stalled


## Time-warp factor in (0, 1]: the fraction of nominal angular rate the swing
## still advances at. Strictly positive for every `drag >= 0`, which is what
## makes progress non-decreasing AND keeps a hard stall out of this issue.
func warp() -> float:
	if _stalled:
		return 0.0
	return 1.0 / (1.0 + drag)


## Freeze the swing where it is (#781's grip rule). Seeds the accumulator from
## the nominal progress exactly as first contact in [method bank_drag] does, so the
## drivers hold THIS substep's angle from here on. Idempotent.
func stall() -> void:
	if _stalled:
		return
	_stalled = true
	if not _warping:
		_warping = true
		_f = clampf(_last_t / duration, 0.0, 1.0) if duration > 0.0 else 0.0


func is_stalled() -> bool:
	return _stalled


## Open one substep at nominal time [param t]: remember it, and — once the
## clock is warping — advance the warped progress by this substep's share.
## Called by [method BladeSim._step] BEFORE the drivers apply, so a driver
## reading [method progress] on the same substep sees the advanced value.
##
## Monotonic: `sub_dt` and [method warp] are both positive, so `_f` only ever
## rises, and `minf` caps it at a completed sweep.
func tick(t: float, sub_dt: float) -> void:
	_last_t = t
	if not _warping or duration <= 0.0:
		return
	_f = minf(1.0, _f + (sub_dt / duration) * warp())


## The angular progress the arc driver should use, or -1.0 meaning "I have
## nothing to say — use your own `t / duration`". See [member _warping].
func progress() -> float:
	return _f if _warping else -1.0


## Bank zone [param z]'s drag, once, because some part of the blade has just
## touched it. Called by [method BladeObstacleField.project] the moment its
## contact test passes; a second call for the same zone is a no-op.
##
## [b]Causal, never global.[/b] The drag applies to the REST of the arc and
## never to the approach: on first contact the accumulator is SEEDED from the
## nominal progress the drivers have been reading up to now, and only then does
## this clock take over. A global warp would be paradoxical — a fortified node
## at the end of the sweep would retroactively prevent the swing from ever
## reaching it.
##
## [b]The seed reads [member _last_t], which is per-SUBSTEP.[/b]
## [method BladeSim._step] calls [method tick] before the drivers apply, so by
## the time the projection pass reaches here `_last_t` is this substep's own
## time, not the sample's. That is what lets the contact be sensed at the
## solver's cadence (four times finer than #780's per-sample `sense()`) without
## the seed going stale — checked when the sensing moved, #811.
func bank_drag(z: int, amount: float) -> void:
	if amount <= 0.0 or touched.has(z):
		return
	touched[z] = true
	drag += amount
	if not _warping:
		_warping = true
		_f = clampf(_last_t / duration, 0.0, 1.0) if duration > 0.0 else 0.0


## True if zone [param z] has already banked its drag this swing — the latch
## [method BladeObstacleField.project] early-outs a wall contact on.
func has_banked(z: int) -> bool:
	return touched.has(z)


# ── The native boundary (#813) ────────────────────────────────────────────────
# The C++ backend advances this clock itself rather than calling back into
# GDScript per substep, so the mutable half crosses as plain values and comes
# back advanced — plus one such Dictionary per sample, which is [member history].
# The three functions below are [method capture] / [method restore] in
# Dictionary clothing: keep them beside those two, and change all of them
# together, because a field that stops crossing is not an error anywhere.


## The mutable half as a plain Dictionary — the same six fields [Bank] carries.
func native_state() -> Dictionary:
	return {
		"f": _f,
		"drag": drag,
		"touched": touched.duplicate(),
		"warping": _warping,
		"last_t": _last_t,
		"stalled": _stalled,
	}


## Turn one of the C++ loop's per-sample Dictionaries back into a [Bank]. The
## packed/dictionary values are already fresh copies made on the far side.
static func bank_from_native(d: Dictionary) -> Bank:
	var b := Bank.new()
	b.f = d["f"]
	b.drag = d["drag"]
	b.touched = d["touched"]
	b.warping = d["warping"]
	b.last_t = d["last_t"]
	b.stalled = d["stalled"]
	return b


## Adopt the state the C++ loop left — the inverse of [method native_state],
## and the reason a chunk that ran native can be continued by either backend.
func apply_native_state(d: Dictionary) -> void:
	_f = d["f"]
	drag = d["drag"]
	touched = d["touched"]
	_warping = d["warping"]
	_last_t = d["last_t"]
	_stalled = d["stalled"]

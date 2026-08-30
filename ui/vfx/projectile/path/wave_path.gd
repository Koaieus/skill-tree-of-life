@tool
class_name WavePath
extends ProjectilePath

## Straight lerp plus a transverse sine (#670 P3) — the "this is a wave, not a
## bolt" motion. Reverberator and Resonator are built on it, and it is the
## natural EDGE-verb alternative to [LinearPath] for anything that should read
## as propagating rather than as being thrown.
##
## [b]Pure function of `t`.[/b] No state, no time reference, no randomness — the
## same `t` always yields the same point, which is what lets a coordinator
## re-evaluate a path (a rewind, a second visual sharing one path resource, a
## test) without the shape drifting. [JitterPath] is the deliberately impure
## sibling; read its class docs for why that one is allowed to be.
##
## The `sin` here is not the transcendental `.claude/rules/multiplayer-sync.md`
## bans: that rule scopes to gameplay code and stat formulas, results a peer
## recomputes. A path is presentation, and nothing downstream reads its output.
##
## The offset is perpendicular to origin→target, so the wave rides the segment
## at any angle and both endpoints are exact: [member decay] shapes the envelope
## but the `sin(0) == sin(TAU * frequency) == 0` term already pins t=0 and t=1
## for whole-number frequencies, and [method _envelope] pins them for every
## other value too.

## Peak transverse offset in world pixels, before the envelope.
@export_range(0.0, 200.0, 0.5) var amplitude: float = 18.0

## Whole cycles across the flight. Whole numbers keep the wave symmetric; a
## half value lands the projectile coming off the opposite side.
@export_range(0.0, 8.0, 0.25) var frequency: float = 1.5

## How the amplitude envelope decays along the flight.
##   0.0 — no decay: the wave is as wide at the target as at the origin.
##   1.0 — fully decayed by arrival: a wave that settles onto its target.
## Below 0 the wave GROWS instead, which reads as a signal building.
@export_range(-1.0, 1.0, 0.05) var decay: float = 0.35


func evaluate(t: float, origin: Vector2, target: Vector2) -> Vector2:
	t = eased(t)
	var base: Vector2 = origin.lerp(target, t)
	var along: Vector2 = target - origin
	if along.length_squared() < 1e-6:
		# Degenerate segment (a self-loop routed here by mistake): there is no
		# perpendicular to speak of, so fall through to the lerp rather than
		# normalising a zero vector.
		return base
	var perpendicular := Vector2(-along.y, along.x).normalized()
	return base + perpendicular * amplitude * _envelope(t) * sin(TAU * frequency * t)


## Amplitude scale at [param t]. Pinned to 0 at BOTH ends regardless of
## [member frequency], so a fractional frequency can never displace the impact
## point off the target node — the coordinator's whole beat alignment rests on
## the projectile actually reaching `target`.
func _envelope(t: float) -> float:
	var ends: float = 4.0 * t * (1.0 - t)
	return ends * (1.0 - decay * t)

@tool
class_name JitterPath
extends ProjectilePath

## Straight lerp plus perpendicular hash-noise offsets (#670 P4) — the unstable,
## arcing-electricity motion. Spark and the lightning family are built on it.
##
## [b]Unseeded randomness is FINE here, and this comment exists so a future
## reader does not "fix" it.[/b] `.claude/rules/multiplayer-sync.md` bans an
## unseeded roll for any result a peer *reproduces* rather than receives. No
## peer reproduces a projectile's wiggle: the wiggle is not a result, nothing
## downstream reads it, and two machines showing two different squiggles between
## the same two nodes is not a desync — it is two machines drawing the same
## event. So the noise seeds off [member seed_source], which defaults to this
## resource's own instance id.
##
## [b]Still a pure function of `t`[/b], for a fixed seed: the offsets come from
## an integer hash of the sample index, never from a timer or an RNG stream, so
## the same `t` yields the same point every call. That is what keeps a shared
## path resource from drifting between two visuals — the *shape* is fixed at
## construction, only *which* shape you get is arbitrary.

## Peak transverse offset in world pixels.
@export_range(0.0, 200.0, 0.5) var amplitude: float = 10.0

## How many noise samples span the flight. More = a busier, higher-frequency
## crackle; fewer = broad lazy swerves.
@export_range(1, 32, 1) var segments: int = 7

## 0 = hard corners between samples (crackling electricity). 1 = smooth
## interpolation between them (a drunken swerve).
@export_range(0.0, 1.0, 0.05) var smoothing: float = 0.35

## Envelope: 0 keeps the jitter full-width all the way in, 1 tapers it to
## nothing at the target so the impact point stays clean.
@export_range(0.0, 1.0, 0.05) var settle: float = 0.6

## Seed for the hash. 0 = "pick one for me", resolved once, lazily, off this
## resource's instance id — see the class docs for why an arbitrary seed is
## allowed here and nowhere near gameplay.
@export var seed_source: int = 0

## The resolved seed. Lazily fixed on first use so a `.tres` authored with
## `seed_source = 0` still behaves as a pure function afterwards.
var _seed: int = 0


func evaluate(t: float, origin: Vector2, target: Vector2) -> Vector2:
	t = eased(t)
	var base: Vector2 = origin.lerp(target, t)
	var along: Vector2 = target - origin
	if along.length_squared() < 1e-6:
		return base
	var perpendicular := Vector2(-along.y, along.x).normalized()
	return base + perpendicular * amplitude * _envelope(t) * _noise(t)


## Resolved once; every later call reuses it, which is what makes `evaluate`
## repeatable for one instance.
func _resolved_seed() -> int:
	if _seed != 0:
		return _seed
	_seed = seed_source if seed_source != 0 else int(get_instance_id())
	return _seed


## Signed noise in [-1, 1] at [param t]. Samples the hash at the two bracketing
## sample indices and blends by [member smoothing] — 0 holds the left sample
## (hard corners), 1 lerps (smooth swerve).
func _noise(t: float) -> float:
	var scaled: float = clampf(t, 0.0, 1.0) * float(segments)
	var i: int = int(floor(scaled))
	var frac: float = scaled - float(i)
	var a: float = _hash_unit(i)
	var b: float = _hash_unit(i + 1)
	return lerpf(a, lerpf(a, b, frac), clampf(smoothing, 0.0, 1.0))


## Deterministic integer hash → [-1, 1]. An xorshift-style mix rather than
## [RandomNumberGenerator]: no stream state to advance, so sampling index 4
## twice gives the same answer both times, which is the whole purity claim.
func _hash_unit(index: int) -> float:
	var h: int = (index * 0x27d4eb2d) ^ (_resolved_seed() * 0x165667b1)
	h = (h ^ (h >> 15)) * 0x2545f491
	h = h ^ (h >> 13)
	# Fold to 24 bits before the divide — plenty of resolution for a pixel
	# offset, and it keeps the value well inside float's exact-integer range.
	var bits: int = absi(h) & 0xffffff
	return float(bits) / float(0x7fffff) - 1.0


## Envelope. The origin end is left full-width — a bolt leaves the caster
## already crackling — and [member settle] tapers the target end so the crackle
## calms into the impact. It does not have to reach zero: [Projectile] snaps
## `global_position` to the target on its final frame regardless, so the beat
## alignment is safe at any [member settle].
func _envelope(t: float) -> float:
	return 1.0 - settle * clampf(t, 0.0, 1.0)

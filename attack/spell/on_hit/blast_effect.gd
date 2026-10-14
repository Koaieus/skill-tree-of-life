@tool
class_name BlastEffect
extends SplashEffect

## The explosion: a [SplashEffect] preset that never lands on its centre (the
## centre already took the main hit) and inherits its landing's
## [member HitLanding.target_mask] — an arrow's blast hits what an arrow may, a
## spell's what its targeting may. Its reach is [member range_finder]'s, built
## by whoever emits it; one finder per distinct radius keeps
## [member HitLanding.gather_cache] deduping a volley. A named type because
## every Explosive emitter instances it.


func _init() -> void:
	hits_centre = false
	ownership_filter = 0


## The detonation's power, for the mark's audience only ([member BlastMark.power]);
## the reach is [member range_finder]'s. 0 = the emitter did not say.
var power: int = 0


## The splash, then one [BlastMark] stamped on every hit it appended that no
## chained blast inside it already claimed. A blast that lands nothing mints
## nothing: no hit, no ring.
func apply(landing: HitLanding) -> void:
	if landing == null:
		return
	var before := landing.hits.size()
	super.apply(landing)
	if landing.hits.size() == before:
		return
	var mark := mark_for(landing)
	for i in range(before, landing.hits.size()):
		if landing.hits[i].blast_mark == null:
			landing.hits[i].blast_mark = mark


## The mark this blast mints on [param landing]: centred on its target, at
## [member range_finder]'s reach, carrying the identities of [member inners]'
## status riders (explosive stripped — a blast never plants charges).
func mark_for(landing: HitLanding) -> BlastMark:
	var mark := BlastMark.new()
	mark.centre = landing.target
	mark.attacker = landing.attacker
	mark.power = power
	var finder := range_finder as EuclideanRangeFinder
	mark.reach = finder.max_distance if finder != null else 0.0
	for effect in DetonateEffect.strip(inners):
		if effect == null or effect is DetonateEffect:
			continue
		var def := effect.status_def()
		if def != null and def.identity != null and not mark.riders.has(def.identity):
			mark.riders.append(def.identity)
	return mark

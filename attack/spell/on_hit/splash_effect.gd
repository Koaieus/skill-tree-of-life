@tool
class_name SplashEffect
extends OnHitEffect

## Runs [member inner] on the landed node and again on every node in its
## [member reach] — *who* the effect lands on, split from *what* it does (the
## blindness flare; a later reach is another [enum Reach] value, a bigger dose
## on the main target is a second entry). Mode-agnostic: an arrow, a blade
## contact or a spell may carry one.
##
## Each extra landing is a copy of the original retargeted at the neighbour:
## same [member HitLanding.hit_key] (one hit, so Greed spends once), same
## [member HitLanding.paired] (a gated arrow duds every splash), same
## structural key, and the same [member HitLanding.hits] sink by reference.
## The reach is read from topology when the effect runs (plan compile, for an
## arrow); whether each neighbour is STILL hostile is decided at land — every
## [StatusInstance] a splash copy emits carries
## [member StatusInstance.require_hostile].

enum Reach {
	## The landed node plus its direct graph neighbours whose
	## [method SkillNode.ownership_bit] to the attacker is HOSTILE.
	TARGET_AND_HOSTILE_NEIGHBOURS,
}

@export var inner: OnHitEffect = null
@export var reach: Reach = Reach.TARGET_AND_HOSTILE_NEIGHBOURS


func apply(landing: HitLanding) -> void:
	if inner == null or landing == null:
		return
	inner.apply(landing)
	for node in _reach_of(landing):
		var copy := _retargeted(landing, node)
		var before := landing.hits.size()
		inner.apply(copy)
		for i in range(before, landing.hits.size()):
			var status := landing.hits[i] as StatusInstance
			if status != null:
				status.require_hostile = true


func get_description(spell: SpellDef = null, board: StatBoard = null) -> String:
	var line := inner.get_description(spell, board) if inner != null else ""
	match reach:
		Reach.TARGET_AND_HOSTILE_NEIGHBOURS:
			return "%s Splashes onto adjacent hostile nodes." % line if not line.is_empty() \
				else "Splashes onto adjacent hostile nodes."
	return line


## The extra nodes this landing splashes onto, beyond its own target. Walks
## (never counts) the attacker's graph; empty with no graph to walk.
func _reach_of(landing: HitLanding) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	var attacker := landing.attacker
	if landing.target == null or attacker == null or attacker.navigator == null \
			or attacker.navigator.graph == null:
		return out
	for n in attacker.navigator.graph.get_neighbours(landing.target):
		if n != landing.target and n.ownership_bit(attacker) == SkillNode.Ownership.HOSTILE:
			out.append(n)
	return out


## A plain [HitLanding] carrying every fact of [param landing] but its target.
## `_init` mints a fresh key; the copy takes the original's back.
static func _retargeted(landing: HitLanding, node: SkillNode) -> HitLanding:
	var copy := HitLanding.new()
	copy.attacker = landing.attacker
	copy.source = landing.source
	copy.origin = landing.origin
	copy.read_node = landing.read_node
	copy.target = node
	copy.structural_key = landing.structural_key
	copy.paired = landing.paired
	copy.hits = landing.hits
	copy.hit_key = landing.hit_key
	return copy

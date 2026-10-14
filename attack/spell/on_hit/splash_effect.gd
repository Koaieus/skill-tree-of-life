@tool
class_name SplashEffect
extends OnHitEffect

## Runs [member inners] on the landed node (unless [member hits_centre] is
## off) and again on every other node its [member range_finder] gathers around
## it whose relation to the attacker matches the mask — *who* the effect lands
## on, split from *what* it does (the blindness flare; a bigger dose on the
## main target is a second entry). The finder answers geometry, the mask
## answers relation: the same pair [NodeTargeting] composes. Mode-agnostic: an
## arrow, a blade contact or a spell may carry one.
##
## The mask is [member ownership_filter], or — at 0 — the landing's own
## [member HitLanding.target_mask]: a splash hits what its hit may hit.
##
## Each extra landing is a copy of the original retargeted at the gathered
## node: same [member HitLanding.hit_key] (one hit, so Greed spends once),
## same [member HitLanding.paired] (a gated arrow duds every splash), same raw
## amount and mask, same structural key, and the same [member HitLanding.hits]
## sink and [member HitLanding.gather_cache] by reference.
## The reach is read when the effect runs (plan compile, for an arrow);
## whether each node STILL matches the mask is decided at land — every hit a
## copy emits carries the mask as its [member HitInstance.land_mask].

## What lands — on the centre and on every splashed node, in order.
@export var inners: Array[OnHitEffect] = []
## Whether [member inners] also run on the landed node itself. Off for a blast:
## the centre already took the main hit.
@export var hits_centre: bool = true
## Who a splash may land on, beyond the target — [NodeTargeting]'s flag set.
## 0 = inherit the landing's [member HitLanding.target_mask].
@export_flags("Neutral:1", "Mine:2", "Ally:4", "Hostile:8", "Friendly:6", "Allocated:14", "Any:15") var ownership_filter: int = 8
## Where it reaches. The radius is the finder's own export, unscaled by any
## cast-range stat. No finder: no splash.
@export var range_finder: RangeFinder


func apply(landing: HitLanding) -> void:
	if inners.is_empty() or landing == null:
		return
	if hits_centre:
		OnHitEffect.run_all(inners, landing)
	var mask := mask_for(landing)
	for node in _reach_of(landing, mask):
		var copy := _retargeted(landing, node)
		var before := landing.hits.size()
		OnHitEffect.run_all(inners, copy)
		for i in range(before, landing.hits.size()):
			landing.hits[i].land_mask = mask


## The relation mask this splash gathers and lands with on [param landing]:
## [member ownership_filter], or the landing's own mask when that is 0.
func mask_for(landing: HitLanding) -> int:
	return ownership_filter if ownership_filter != 0 else landing.target_mask


func status_def() -> StatusDef:
	for effect in inners:
		var def := effect.status_def() if effect != null else null
		if def != null:
			return def
	return null


func get_description(spell: SpellDef = null, board: StatBoard = null, read_node: SkillNode = null) -> String:
	var parts: PackedStringArray = []
	for effect in inners:
		if effect != null:
			var text := effect.get_description(spell, board, read_node)
			if not text.is_empty():
				parts.append(text)
	var line := " ".join(parts)
	if range_finder == null:
		return line
	# The finder's own text, with no board: the reach is unscaled (see
	# [method _reach_of]), so a stat-scaled number would lie.
	var reach := "Splashes onto %s nodes %s." % [_filter_word(),
			range_finder.get_description(null).to_lower()]
	return "%s %s" % [line, reach] if not line.is_empty() else reach


func _filter_word() -> String:
	match ownership_filter:
		0: return "targetable"
		SkillNode.Ownership.HOSTILE: return "hostile"
		SkillNode.Ownership.NEUTRAL: return "neutral"
		6: return "friendly"
		14: return "allocated"
		15: return "all"
	return "matching"


## The extra nodes this landing splashes onto, beyond its own target: the
## finder's gather around the target over the GLOBAL [Navigator] (the whole
## board, every owner — the scope the old neighbour walk had). Never the
## attacker's own [EntityNavigator]: an owned-subgraph mirror holds no hostile
## node, so a HOSTILE splash would reach nothing. `attacker = null` keeps the
## gather unscaled. Empty with no finder, no graph or a 0 [param mask].
##
## The gather goes through [member HitLanding.gather_cache], keyed
## `[target, finder, reach]` and holding the result BEFORE the mask, so a
## volley's arrows on one node sweep the board once whatever their masks.
func _reach_of(landing: HitLanding, mask: int) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	var attacker := landing.attacker
	if mask == 0 or range_finder == null or landing.target == null or attacker == null \
			or attacker.navigator == null or attacker.navigator.graph == null:
		return out
	var mirror: GraphMirror = attacker.navigator.graph.navigator
	var key := [landing.target, range_finder, range_finder.max_reach()]
	var gathered: Dictionary = landing.gather_cache.get(key, {})
	if not landing.gather_cache.has(key):
		gathered = range_finder.gather(landing.target, mirror)
		landing.gather_cache[key] = gathered
	for n in gathered:
		if n != landing.target and n.ownership_bit(attacker) & mask != 0:
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
	copy.read_overlays = landing.read_overlays
	copy.target = node
	copy.structural_key = landing.structural_key
	copy.paired = landing.paired
	copy.hits = landing.hits
	copy.gather_cache = landing.gather_cache
	copy.hit_key = landing.hit_key
	copy.raw_amount = landing.raw_amount
	copy.raw_type = landing.raw_type
	copy.target_mask = landing.target_mask
	copy.detonated = landing.detonated
	return copy

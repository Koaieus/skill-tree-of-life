@tool
class_name ExplosiveSpread
extends StatusSpread

## The explosive status's spread and the ONE owner of a charge's boom shape:
## every node-centred blast (detonation, barrel pop, warhead, exchange, death)
## asks [method radius_for] / [method blast_for] and never computes a reach
## itself. The bomb is the node: reach = node radius × [member reach_per_radius]
## × power^[member charge_exponent], uncapped — area grows linearly in
## the blast's power, and the charge economy bounds it. No stat targets it, so it lives
## here as knobs (`docs/domain/stat-knobs-and-bins.md` §1).
##
## Death ([method on_removed]): a killed node spends every charge at once —
## one burn transfer, nothing spills onto a neighbour.

## Death-blast damage per charge spent; one blast in all. Tentative, easy to
## change (no owner number; linear vs √ vs cap is a playtest call).
@export_range(0.0, 100.0, 0.5, "or_greater") var damage_per_charge: float = 2.0
## Blast reach in units of the exploding node's own radius, at one charge.
## Tentative, easy to change.
@export_range(0.0, 20.0, 0.1, "or_greater") var reach_per_radius: float = 3.0
## How reach grows with the charges present: 0.5 = √ (area linear in
## charges), 0 = flat. In halves only: reach is gameplay math, so it is built
## from integer powers and one `sqrt`, never `pow` (`lint-transcendentals`).
## Tentative, easy to change.
@export_range(0.0, 2.0, 0.5) var charge_exponent: float = 0.5
## The shared chunk's weight on each side of a detonation's power:
## `power = load + present + 2 × resonance × min(load, present)`
## ([method DetonateEffect.power_of]). Tentative, easy to change.
@export_range(0, 5, 1, "or_greater") var resonance: int = 1
## Which removal causes spend the charges, as [constant StatusSpread.CAUSE_DEATH]
## / [constant StatusSpread.CAUSE_DEALLOC] bits. Default: a kill only.
@export_flags("Death", "Dealloc") var triggers: int = CAUSE_DEATH

## Finder per distinct reach: [member HitLanding.gather_cache] keys on finder
## identity, so two blasts of one size on one node must share a finder to
## sweep the board once. A cache of immutable values, never per-node state.
var _finders: Dictionary = {}  # float reach -> EuclideanRangeFinder


## The reach in px of a blast on a node of [param node_radius] px holding
## a blast of [param charges] power: every caller passes the formula's power
## (present and load, before the spend), never a raw charge count. `0.0` for 0.
func radius_for(node_radius: float, charges: int) -> float:
	if charges <= 0 or node_radius <= 0.0:
		return 0.0
	return node_radius * reach_per_radius * _charge_scale(charges)


## charges^[member charge_exponent], the exponent snapped to a half: an
## integer power times one `sqrt` for the odd half.
func _charge_scale(charges: int) -> float:
	var halves := roundi(charge_exponent * 2.0)
	var scale := 1.0
	@warning_ignore("integer_division")
	for i in halves / 2:
		scale *= float(charges)
	if halves % 2 == 1:
		scale *= sqrt(float(charges))
	return scale


## The [BlastEffect] for [param centre] holding [param charges] charges before
## the spend, landing [param inners] on everything in reach (never the centre;
## the mask is the landing's own). The caller strips explosive from
## [param inners] — a blast never plants charges.
func blast_for(centre: SkillNode, charges: int, inners: Array[OnHitEffect]) -> BlastEffect:
	var blast := BlastEffect.new()
	blast.inners = inners
	blast.power = charges
	blast.range_finder = _finder(radius_for(centre.radius if centre != null else 0.0, charges))
	return blast


func _finder(reach: float) -> EuclideanRangeFinder:
	var finder: EuclideanRangeFinder = _finders.get(reach)
	if finder == null:
		finder = EuclideanRangeFinder.new()
		finder.max_distance = reach
		_finders[reach] = finder
	return finder


## A removed node's charges all go at once: one burn of the whole row per
## removed node, never a share onto a survivor.
func on_removed(field: StackField, removed: Array[NodeCombat], cause: int) -> Array[StackTransfer]:
	var out: Array[StackTransfer] = []
	if cause & triggers == 0:
		return out
	for r in removed:
		var stacks: float = field.stacks(r)
		if stacks > 0.0:
			out.append(StackTransfer.new(r, null, stacks, field.key))
	return out


func describe() -> String:
	var when := cause_phrase(triggers)
	if when.is_empty():
		return ""
	return "When the node is %s, every charge goes off in one blast for %s damage per charge." % [
			when, NumFmt.num(damage_per_charge)]

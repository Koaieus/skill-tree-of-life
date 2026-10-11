@tool
class_name RumourSpread
extends PropagationSpread

## Malediction's rumour: the main payload flows to the neighbours that score
## at or below the current node AND tie for the lowest score (a fork on ties);
## every other eligible neighbour takes a minor, terminal share — it lands but
## never carries the rumour on.
##
## The off-path share is decided before the hop, in whole stacks: the cast's
## first status rider folded the way [method StatusInstance.land_on] folds it
## (the attacker's stacks stat, read at the landing's read node), times the
## payload's stack weight and [member off_path_share], floored. Below 1 the
## neighbour is not visited at all. The pick's stack share then makes the
## landing round to exactly that count. Assumes one status rider and no
## [member PropagationConfig.hop_stacks] (Malediction's shape); crits still
## multiply at the landing.

const _EPS := 1e-6

## The downhill metric, scored on the current node and each neighbour.
@export var ranker: NodeRanker = null

## Fraction of the winners' stacks an off-path neighbour takes. Tentative.
@export_range(0.0, 1.0, 0.05) var off_path_share: float = 0.25


func select(eligible: Array[SkillNode], lctx: LandingContext) -> Array[PropagationPick]:
	var out: Array[PropagationPick] = []
	if eligible.is_empty() or ranker == null:
		return out
	var winners := _winners(eligible, lctx)
	for nb in winners:
		out.append(PropagationPick.to(nb, 1.0))
	if winners.size() == eligible.size():
		return out
	var full := _payload_stacks(lctx)
	var off := floorf(full * off_path_share + _EPS)
	if off < 1.0:
		return out
	for nb in eligible:
		if winners.has(nb):
			continue
		var pick := PropagationPick.to(nb, off_path_share)
		pick.stack_share = off / full
		pick.terminal = true
		out.append(pick)
	return out


func _winners(eligible: Array[SkillNode], lctx: LandingContext) -> Array[SkillNode]:
	var downhill := RankThresholdFilter.new()
	downhill.ranker = ranker
	downhill.compare = RankThresholdFilter.Compare.LESS_OR_EQUAL
	var lowest := TopTiesFilter.new()
	lowest.ranker = ranker
	lowest.direction = TopTiesFilter.Direction.LOWEST
	return lowest.narrow(downhill.narrow(eligible, lctx), lctx)


## The stacks this payload would land at full share; 0 with no status rider.
func _payload_stacks(lctx: LandingContext) -> float:
	if lctx.cast == null or lctx.payload == null:
		return 0.0
	for rider in lctx.cast.riders:
		var apply := rider as ApplyStatusEffect
		if apply == null or apply.def == null:
			continue
		var base := apply.def.stacks_per_hit(
				lctx.cast.caster.stat_board if lctx.cast.caster != null else null, apply.power)
		if lctx.cast.world != null and lctx.read_node != null:
			var rn := lctx.cast.world.combat_for(lctx.read_node)
			if rn != null:
				base = apply.def.stacks_per_hit_at(rn, apply.power)
		return base * lctx.payload.stack_weight
	return 0.0


func get_description() -> String:
	var metric := ranker.get_description() if ranker != null else "rank"
	return "Flows toward the lowest %s, forking on ties; every other neighbour takes %d%% of the stacks and stops there." \
			% [metric, roundi(off_path_share * 100.0)]

class_name SpellRangeRules
extends RefCounted
## The cast-range rule: how a caster's stats stretch a spell's authored reach.
## **The one home for the expression** — geometry consumes the number, it does
## not define it. [HopRangeFinder] folds its `max_hops` under
## `cast_range_hops`, [EuclideanRangeFinder] its `max_distance` under
## `cast_range_distance`; both stats are base 0 on every board by contract, and
## the spell contributes the base as an overlay bin (see
## docs/domain/stat-knobs-and-bins.md §5). So `+N` on the stat is a flat add
## in the spell's own unit, `% increased` / `MULTIPLY` scale the authored
## reach, and a `SET` replaces it outright.


## [param authored] folded as `base_add` under [param stat_id], in order:
##   1. [param source] — the cast-from node — via
##      [method SkillNode.get_local_value_with]: entity bins + node-local bins
##      (a range-extender addon on the cast-from node) + the overlay, one fold,
##      coerced once by the stat (an INT stat floors the finished total).
##   2. [param board] — the caster's own board, for previews with no cast-from
##      node picked yet ([SpellTooltip]). Misses node-local addons by
##      construction; that's the price of previewing before a source exists.
##   3. Neither — the raw authored reach. A null [param attacker] takes this
##      too: a [CoreClass] aura must not scale with the caster's cast range.
## A tier whose board holds no stat under [param stat_id] also answers the raw
## authored reach: there is nothing to fold through.
##
## One [ModifierBins] per read, no cache — a [RangeFinder] is a shared Resource.
static func reach(stat_id: StringName, authored: float, attacker: Entity, source: SkillNode,
		board: StatBoard = null) -> float:
	var bins := ModifierBins.new()
	bins.base_add = authored
	var overlays: Array[ModifierBins] = [bins]
	if attacker != null and source != null:
		var v: Variant = source.get_local_value_with(stat_id, overlays)
		return authored if v == null else float(v)
	if board != null:
		var stat: Stat = board.get_stat(stat_id)
		if stat != null:
			return float(stat.get_value_with(overlays))
	return authored

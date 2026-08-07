class_name SpellRangeRules
extends RefCounted
## The `spell_range` reach rule: how far a caster's stats stretch a spell's
## authored reach. **The one home for the expression** — geometry consumes the
## number, it does not define it.
##
## Extracted from [RangeFinder], which had no business knowing about the stat
## system: a reach model answers "is this within N of that", and *what N is*
## for a given caster is a stat question. Both concrete finders
## ([HopRangeFinder], [EuclideanRangeFinder]) scale their exported reach by
## this, so the rule could not live in a spell-specific finder subclass either
## — they're siblings.
##
## [SpellTooltip] previously carried a second copy that read the caster's board
## directly instead of node-locally, so a range-extender addon on the cast-from
## node moved the real reach but not the number the tooltip showed.

## Percent-bonus reach multiplier for a cast, in [code]1.0 + spell_range /
## 100[/code] form. Subclasses of [RangeFinder] multiply their base reach by
## this so INT-driven boosts propagate uniformly across hop and euclidean
## models.
##
## Where the `spell_range` term comes from, in order:
##   1. [param source] — the cast-from node — via [method SkillNode.get_local_value],
##      so the wielder's baseline merges with node-local addons (e.g. a
##      range-extender granting local `spell_range`, #171).
##   2. [param board] — the caster's own board, for previews with no cast-from
##      node picked yet ([SpellTooltip]). Misses node-local addons by
##      construction; that's the price of previewing before a source exists.
##   3. Neither — 1.0, the deliberate "no scaling" path. A null [param attacker]
##      takes this too: a [CoreClass] aura must not scale with the caster's
##      `spell_range`.
static func multiplier(attacker: Entity, source: SkillNode, board: StatBoard = null) -> float:
	if attacker != null and source != null:
		return _from_percent(float(source.get_local_value(&"spell_range")))
	if board != null:
		var stat: Stat = board.get_stat(&"spell_range")
		if stat != null:
			return _from_percent(float(stat.value))
	return 1.0


static func _from_percent(bonus: float) -> float:
	return 1.0 + bonus / 100.0

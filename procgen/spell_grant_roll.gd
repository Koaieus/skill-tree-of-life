@tool
class_name GraphProcgenSpellGrants
extends RefCounted

## Third-pass spell-grant roll (#206), split out of [GraphProcgen] to keep
## that file from growing further — same static-helper shape as the addon
## roll it sits beside, just simple enough not to need its own Policy
## resource (see [SpellGrantPool]).
##
## v1 scope, settled with the issue owner: gated to INT-archetype nodes only
## (spells are INT-flavoured), at most one grant per node, flat per-spell
## weight (default 1.0, override via [member SpellGrantPoolEntry.weight]).
## Multi-slot / per-band weighting / tier scaling are explicit follow-ups,
## not missing pieces — see #206.

const _INT_PRIMARY_STAT := &"intelligence"


## Rolls at most one [SpellGrant] onto `sn` and appends it to
## `sn.effects`. No-ops when `pool` is unset, `chance` is 0, or
## `archetype_primary_stat` isn't the INT archetype's.
static func roll_and_attach(
		sn: SkillNode,
		pool: SpellGrantPool,
		chance: float,
		archetype_primary_stat: StringName,
		rng: RandomNumberGenerator,
) -> void:
	if pool == null or chance <= 0.0:
		return
	if archetype_primary_stat != _INT_PRIMARY_STAT:
		return
	if rng.randf() >= chance:
		return
	var entry := _weighted_pick(pool, rng)
	if entry == null or entry.spell_def == null:
		return
	var grant := SpellGrant.new()
	grant.spell_def = entry.spell_def
	print_debug('[PROCGEN] Rolled SpellGrant: %s' % grant.spell_def.name)
	sn.add_effect(grant)


static func _weighted_pick(pool: SpellGrantPool, rng: RandomNumberGenerator) -> SpellGrantPoolEntry:
	var total := 0.0
	for e in pool.entries:
		if e == null or e.spell_def == null or e.weight <= 0.0:
			continue
		total += e.weight
	if total <= 0.0:
		return null
	var r := rng.randf() * total
	for e in pool.entries:
		if e == null or e.spell_def == null or e.weight <= 0.0:
			continue
		r -= e.weight
		if r <= 0.0:
			return e
	return null

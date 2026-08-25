@tool
class_name ModSlabRow
extends SlabRow

## One [StatModifier] rendered as its own mini slab — the full sentence from
## [method StatModifier.format] (#305) on a [SlabRow] tinted by the target
## stat's [member StatDef.tint_color]. The operator carries no color of its
## own — it lives entirely in the text (`+18% increased`, `bonus`, `Max `,
## ...). Content row for Tooltip V2 (epic #159, #221).
##
## [b]Everything visual lives on [SlabRow][/b] (#588) — this is an inherited
## scene of `slab_row.tscn` and adds exactly one thing: resolving a modifier
## into the (text, tint) pair the base renders. Sizing, the tint→text colour
## mix and [method SlabRow.set_progress] are all the base's.
##
## Reused standalone (#306's "you gained these" toast instantiates slabs with
## nothing driving them) as well as inside [AddonItem]'s modifier list (#293).

## Renders `m.format()` (the full sentence, stat name included — #305) into
## the slab's Label, and drives the slab + text from the target stat's
## [member StatDef.tint_color], read raw. Falls back to [constant Color.WHITE]
## only if the def can't be resolved (not expected for a real stat_id).
##
## `m` is assumed to be a leaf modifier — a [CompositeStatModifier] has no
## single meaningful `stat_id`; callers are specified to flatten before
## binding one row per leaf (see `.claude/rules/stats-system.md` §Composite).
func bind(m: StatModifier) -> void:
	var def := StatRegistry.get_def(m.stat_id)
	bind_text(m.format(), def.tint_color if def != null else Color.WHITE)

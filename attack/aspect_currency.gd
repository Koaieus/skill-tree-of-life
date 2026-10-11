class_name AspectCurrency
extends RefCounted

## The one board read behind every per-attack currency cap: a melee swing's
## `<concept>_aspect` temp costs and a cast's infusion caps (`<concept>_aspect`,
## `infusion_slots`, `infusion_points`) all ask "how much of this stat may one
## attack spend", floored. A pooled budget — nothing is consumed.


## [param attacker]'s live [param stat_id], floored at 0; 0 with no board.
static func cap_of(attacker: Entity, stat_id: StringName) -> int:
	if attacker == null or attacker.stat_board == null:
		return 0
	return maxi(0, floori(attacker.stat_board.get_value(stat_id)))


## The count stat of concept [param aspect_id] — `&"poison"` → `&"poison_aspect"`,
## its ASPECT facet in the registry; `&""` for a concept with none.
static func stat_of(aspect_id: StringName) -> StringName:
	var def: StatDef = StatRegistry.facet_def(aspect_id, StatDef.Role.ASPECT)
	return def.id if def != null else &""

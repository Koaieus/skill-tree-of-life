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
## the `<concept>_aspect` naming `test_identity_roster.gd` pins. Spelled here
## rather than read off [code]AspectRoster[/code], which ranks above `attack`.
static func stat_of(aspect_id: StringName) -> StringName:
	return StringName("%s_aspect" % aspect_id)

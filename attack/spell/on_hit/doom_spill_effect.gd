@tool
class_name DoomSpillEffect
extends OnHitEffect

## Doombrand's doom: stamps [member spill_scale] onto the damage hit this
## rider rides ([member HitLanding.paired]) when the riders are built, so a
## node that hit depletes spills its statuses multiplied
## ([method SpillSpread.on_removed]). Lands nothing itself.

## Multiplier on the depleted node's spillable stacks. `1.0` = a plain kill.
@export_range(1.0, 5.0, 0.1) var spill_scale: float = 2.0


func apply(landing: HitLanding) -> void:
	if landing == null:
		return
	var hit := landing.paired as DamageInstance
	if hit != null:
		hit.spill_scale = spill_scale


func get_description(_spell: SpellDef = null, _board: StatBoard = null, _read_node: SkillNode = null) -> String:
	return "A node this contact kills spills its statuses ×%s." % NumFmt.num(spill_scale)

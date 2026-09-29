@tool
class_name StatusRow
extends SlabRow

## One [NodeStatus] rendered as its own mini slab — display name plus
## normalised power (`power / power_max`), tinted by the status def's own
## [member StatusDef.tint]. Tooltip-fan Effects panel row for #876 (child of
## #868); the node's own visual tint from the same [member StatusDef.tint] is
## a separate consumer (#880), out of scope here.
##
## [b]Everything visual lives on [SlabRow][/b] (#588) — this is an inherited
## scene of `slab_row.tscn`, same shape as [ModSlabRow]: resolve the
## (text, tint) pair from the domain object, the base renders it.

## Renders "<display_name> <⌊power⌋> — <dmg> dmg next tick" for a status that
## deals damage — e.g. "Poison 12 — 9 dmg next tick" for a 12.7 row at 25%
## resistance — and bare "<display_name> <⌊power⌋>" for one that doesn't
## (curse, wither, blindness, armor-break). [param host] answers
## [method StatusDef.next_tick_damage], the SAME call the health bar's
## projection reads its first term from (#1190), so the row and the bar never
## disagree; a def that deals no damage answers `0` there and the dmg clause
## is dropped. Tinted by the def's own [member StatusDef.tint]. Falls back to
## the status id when [member StatusDef.display_name] is blank.
func bind(status: NodeStatus, host) -> void:
	var def := status.def
	var label := def.display_name if not def.display_name.is_empty() else String(def.id)
	var whole := floori(status.power)
	var dmg := def.next_tick_damage(host, status.power)
	if dmg > 0.0:
		bind_text("%s %d — %s dmg next tick" % [label, whole, NumFmt.num(dmg)], def.tint)
	else:
		bind_text("%s %d" % [label, whole], def.tint)

@tool
class_name FuelUse
extends LoadUse

## The load spends nothing at the hit — no rider, no blast; it only shapes the
## spell, which reads it from [member PropagationContext.load] (Firecracker's
## explosive fuel feeding its [FuelBlastReach]).


func describe(row: AspectIntake, _board: StatBoard = null, _read_node: SkillNode = null) -> String:
	var def := row.status()
	var label := def.display_name if not def.display_name.is_empty() else String(def.id)
	return "Fuels the spell with %s %s (%s)." % [row.innate, label, row.ingest_line()]

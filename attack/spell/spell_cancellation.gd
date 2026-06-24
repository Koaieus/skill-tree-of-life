class_name SpellCancellation
extends RefCounted

## Telemetry record emitted when an [IncidentReducer] resolves to null,
## fizzling the spell at a node. Lands on [member AttackOutcome.cancellations]
## and (globally) on the [code]Events.spell_incident_cancelled[/code] signal
## so VFX coordinators can hook a pop/dissipate effect.

var node: SkillNode = null
var wave_index: int = 0
var incident_count: int = 0


func _to_string() -> String:
	return "<Cancel %s wave=%d incidents=%d>" % [node, wave_index, incident_count]

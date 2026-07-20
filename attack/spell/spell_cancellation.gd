class_name SpellCancellation
extends RefCounted

## Telemetry record emitted when an [IncidentReducer] resolves to null,
## fizzling the spell at a node. Lands on [member AttackOutcome.cancellations]
## for replay/battle-log. Cancel VFX is driven by the PropagationEvent timeline
## ([code]Verb.CANCEL[/code] → [code]MagicBounceCoordinator.cancel_visual[/code]),
## not by this record.

var node: SkillNode = null
var wave_index: int = 0
var incident_count: int = 0


func _to_string() -> String:
	return "<Cancel %s wave=%d incidents=%d>" % [node, wave_index, incident_count]

@tool
class_name DefenderStatShare
extends StackTerm

## A share of the RECEIVING node's live [member stat_id] (`armor` by default) as
## extra stacks: `maxf(0, stat) × ratio`, read at land against the landing
## world, so a shadow resolve sees an earlier contact's sunder. Gated on the
## read node's allocation level; an addon-only number, never a stat.

## The receiving node's stat the share is taken of.
@export var stat_id: StringName = &"armor"
## Extra stacks per point of the stat. Tentative default, easy to change.
@export_range(0, 4) var ratio: float = 0.25
## The read node's allocation level (the A of A/B) the term starts at.
@export_range(1, 8, 1, "or_greater") var unlock_level: int = 1


func extra(read: NodeCombat, host: NodeCombat) -> float:
	if read == null or host == null or read.get_allocation_level() < unlock_level:
		return 0.0
	return maxf(0.0, float(host.get_local_value(stat_id))) * ratio


## The [LevelGatedModifier] readout: on a carrier below the gate, no line; at or
## above it, the plain share; off a carrier, the share and its gate.
func describe(read_node: SkillNode = null) -> String:
	var text := "+%s%% of target %s" % [NumFmt.num(ratio * 100.0), String(stat_id).replace("_", " ")]
	if read_node == null:
		return "%s at %d/X" % [text, unlock_level]
	return text if read_node.allocation_level >= unlock_level else ""

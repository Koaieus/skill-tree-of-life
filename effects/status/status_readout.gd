class_name StatusReadout
extends RefCounted

## The one rule every UI reader of a [NodeStatus] goes through to decide how
## much of the row the local machine may read: its count, or only that it is
## there. Never re-derive it at a call site — the tooltip row and the node
## tint must not disagree about the same row.
##
## [b]Viewers[/b] are the machine's local eyes — the array [VisionSystem]
## pushes to each node as [member SkillNode.status_viewers].


## [param row]'s power when [method StatusDef.count_visible] holds for ANY of
## [param viewers], else `-1` (presence only). A shared row (empty
## [member StatusDef.visible_if]) always reads its power. No viewers means no
## eyes and therefore no fog (vision disabled, a sandbox, the editor) — the fog
## already shows everything then, so the count shows too.
static func shown_power(row: NodeStatus, viewers: Array[Entity]) -> int:
	if row.def == null or row.def.visible_if.strip_edges().is_empty() or viewers.is_empty():
		return row.power
	for v in viewers:
		if v != null and row.def.count_visible(row, v.faction_id, v.entity_id):
			return row.power
	return -1


## [method NodeStatus.normalised] at the power [param viewers] may read — a
## presence row normalises as a 1-stack row, so a foreign row's tint strength
## cannot leak its count.
static func shown_normalised(row: NodeStatus, viewers: Array[Entity]) -> float:
	if shown_power(row, viewers) >= 0:
		return row.normalised()
	var probe := row.clone()
	probe.power = 1
	return probe.normalised()

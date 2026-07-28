@tool
class_name FanAnchorDriver
extends Node2D

## Tooltip V2 (#226) — keeps every [FanUnit]'s trace terminus derived live
## from its panel's CURRENT position (Decision 4). Attached as the root
## script of every variant scene (`unowned.tscn` / `owned.tscn` /
## `owned_core.tscn`) so a human dragging a panel in the editor sees the
## trace re-route immediately, without opening [TooltipFan] at all — that is
## the whole point of the split (see the #226 issue body).
##
## Deliberately NOT part of [TooltipFan]: the coordinator only exists at
## runtime (mounted under the HUD), but "drag a panel, watch the line follow"
## has to work with just the variant scene open. Splitting the concern this
## way means panel position is the only authored quantity in EITHER context.
##
## Finds its FanUnits by group (`fan_unit`), never by NodePath — the mount
## contract's "bindings resolve by type/group, not per-variant NodePaths".
## Every FanUnit instance in a variant scene must carry that group (authored
## in the .tscn's `groups=` on the node, not in code).

const _GROUP := &"fan_unit"


func _ready() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	for unit in _units():
		_reroute(unit)


## Recomputes and applies one unit's derived terminus. Public + idempotent so
## tests can call it directly on a single frame instead of waiting on
## `_process` — matches the "call the continuation directly" testing pattern
## already used by fan_trace/fan_unit tests in this epic.
func reroute(unit: Node) -> void:
	_reroute(unit)


func _reroute(unit: Node) -> void:
	if not is_instance_valid(unit):
		return
	var trace: FanTrace = unit.get_node_or_null("%Trace")
	var panel: FanPanel = unit.get_node_or_null("%Panel")
	if trace == null or panel == null:
		return
	var rect := FanAnchor.panel_rect_of(panel)
	trace.to_point = FanAnchor.derive_anchor(trace.from_point, rect, trace.trunk_dir, trace.bend_start)


func _units() -> Array[Node]:
	var out: Array[Node] = []
	for n in find_children("*", "", true, false):
		if n.is_in_group(_GROUP) and n.get_node_or_null("%Trace") != null and n.get_node_or_null("%Panel") != null:
			out.append(n)
	return out

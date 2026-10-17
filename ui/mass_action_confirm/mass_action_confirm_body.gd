@tool
class_name MassActionConfirmBody
extends ModalBodyBase

## [MassActionConfirmPanel]'s swappable body (#486) — the per-node breakdown of
## a pending [MassActionRequest], one block per node (display name + its
## modifiers) in a scrolling list.
##
## [b]Nothing to select.[/b] Unlike the loot bodies there is exactly one thing
## to decide, and the base's Confirm/Cancel buttons already decide it — so
## [method resolve] is empty and [method is_selection_valid] means "can this be
## afforded at all", which is what dims Confirm.

const _NODE_BLOCK := preload("res://ui/mass_action_confirm/mass_action_node_block.tscn")
const _MODIFIER_LABEL := preload("res://ui/mass_action_confirm/mass_action_modifier_label.tscn")

@onready var _node_list: VBoxContainer = %NodeList

var _request: MassActionRequest = null
var _allocation_system: AllocationSystem = null


## Handed down by [MassActionConfirmPanel] before [method populate] — the DP
## affordability of a cascade is AllocationSystem's answer, not the request's.
func bind(allocation_system: AllocationSystem) -> void:
	_allocation_system = allocation_system


func populate(request: Variant) -> void:
	_request = request as MassActionRequest
	for c in _node_list.get_children():
		c.queue_free()

	match _request.verb:
		MassActionRequest.Verb.ALLOCATE:
			# nodes[0] is the already-owned frontier anchor — never listed, it's
			# not being allocated. nodes[1..affordable] is the paid-for prefix;
			# anything past that (up to the clicked target) is dimmed.
			for i in range(1, _request.nodes.size()):
				_add_node_block(_request.nodes[i], i <= _request.affordable_count)
		MassActionRequest.Verb.DEALLOCATE:
			for n in _request.nodes:
				_add_node_block(n, true)


func is_selection_valid() -> bool:
	if _request == null:
		return false
	match _request.verb:
		MassActionRequest.Verb.ALLOCATE:
			return _request.affordable_count >= 1
		MassActionRequest.Verb.DEALLOCATE:
			return _allocation_system != null \
					and _allocation_system.can_deallocate_set(_request.nodes, _request.entity)
	return false


func status_text() -> String:
	if _request == null:
		return ""
	if _request.verb == MassActionRequest.Verb.ALLOCATE:
		var affordable := _request.affordable_count
		var line := "%d Skill Point%s" % [affordable, "" if affordable == 1 else "s"]
		if affordable < _request.nodes.size() - 1:
			line += "  —  reaches %d of %d nodes toward target" % [
					affordable, _request.nodes.size() - 1]
		return line

	var dp_cost := _request.nodes.size()
	var sp_refund := 0
	for n in _request.nodes:
		sp_refund += n.allocation_level
	return "%d Deallocation Point%s  —  refunds %d Skill Point%s" % [
			dp_cost, "" if dp_cost == 1 else "s", sp_refund, "" if sp_refund == 1 else "s"]


func confirm_text() -> String:
	if _request == null:
		return ""
	return "ALLOCATE" if _request.verb == MassActionRequest.Verb.ALLOCATE else "DEALLOCATE"


## One block per node: display name + its modifiers, each on its own line, an
## [HSeparator] after ([code]<hr>[/code] per the design ask). [param reached]
## dims the block when it's past the SP-affordable prefix (allocate only).
func _add_node_block(node: SkillNode, reached: bool) -> void:
	var block := _NODE_BLOCK.instantiate() as VBoxContainer
	block.modulate = Color(1, 1, 1, 1) if reached else Color(1, 1, 1, 0.4)
	(block.get_node(^"%Name") as Label).text = node.get_display_name()

	var mods := block.get_node(^"%Mods") as VBoxContainer
	for leaf in StatModifier.flatten_all(node.modifiers):
		var mod_label := _MODIFIER_LABEL.instantiate() as Label
		mod_label.text = leaf.format()
		mods.add_child(mod_label)
	# An empty box would still claim a separation gap under the name.
	mods.visible = mods.get_child_count() > 0

	_node_list.add_child(block)
	_node_list.add_child(HSeparator.new())

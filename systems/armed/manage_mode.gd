class_name ManageMode
extends ArmedMode

## The unpoppable root of [ArmedStack]: its native click is allocate. It
## contributes no badge and no tint — **a badge is present iff your click is
## modal** (#664), and plain allocate is not modal, so the root stays silent.
##
## Its click can push a level: your own core pushes [CoreMoveMode] (with MP to
## spend), a far unowned node pushes a [MassActionMode] allocate confirm.


func _init(p_ctl: PlayerInputController) -> void:
	ctl = p_ctl


func handle_left_click(node: SkillNode) -> bool:
	var player := ctl.player
	if player == null:
		return false
	if node == player.core_location and ctl._player_has_movement_points():
		stack.push(CoreMoveMode.new(ctl, node))
		return true
	# Refill: a player-owned node with cap headroom from a stake (#337).
	if node.owned_by == player and node.allocation_level < node.stake_level:
		ctl._submit(AllocateCommand.new(player.entity_id, ctl.graph.get_stable_id(node)))
		return true
	if node.owned_by != null:
		return false
	# can_allocate is ROUTING here, not the gate (allocate() re-gates at apply
	# time): it picks a plain allocate over the multi-hop confirm flow.
	if ctl.allocation_system.can_allocate(node, player):
		ctl._submit(AllocateCommand.new(player.entity_id, ctl.graph.get_stable_id(node)))
		return true
	ctl._try_begin_mass_allocate(node)
	return true

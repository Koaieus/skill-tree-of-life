class_name ManagerHighlightProvider
extends HighlightProvider

## Highlight provider for manage-mode allocation (#176) and, since #338, every
## other Manage-tab verb (Stake/Extract/Deallocate). A pure view-state
## snapshot the [HighlightController] rebuilds when no attack plan or core-move
## targeting is active and it's the player's turn. With no verb armed (or
## ALLOCATE explicitly armed — arming it is cosmetic, #338) it tags every
## unowned node the player can allocate with [enum HighlightRole.ALLOCATABLE],
## same as before #338. With Stake/Extract/Deallocate armed it tags every
## legal target with [enum HighlightRole.IN_RANGE] instead — reusing the
## existing role rather than adding new tinting (per #338's acceptance spec).

## The player entity whose eligibility is being queried.
var player: Entity = null
var allocation_system: AllocationSystem = null
var graph: Graph = null
var verb: PlayerInputController.ManageVerb = PlayerInputController.ManageVerb.ALLOCATE


func configure(p_player: Entity, p_alloc: AllocationSystem, p_graph: Graph,
		p_verb: PlayerInputController.ManageVerb = PlayerInputController.ManageVerb.ALLOCATE) -> void:
	player = p_player
	allocation_system = p_alloc
	graph = p_graph
	verb = p_verb
	state_changed.emit()


func get_node_role(node: SkillNode) -> HighlightRole:
	if node == null or allocation_system == null or player == null:
		return HighlightRole.NONE
	match verb:
		PlayerInputController.ManageVerb.STAKE:
			return HighlightRole.IN_RANGE if allocation_system.can_stake(node, player) else HighlightRole.NONE
		PlayerInputController.ManageVerb.EXTRACT:
			return HighlightRole.IN_RANGE if allocation_system.can_extract(node, player) else HighlightRole.NONE
		PlayerInputController.ManageVerb.DEALLOCATE:
			return HighlightRole.IN_RANGE if allocation_system.can_deallocate(node, player) else HighlightRole.NONE
	if allocation_system.can_allocate(node, player):
		return HighlightRole.ALLOCATABLE
	return HighlightRole.NONE

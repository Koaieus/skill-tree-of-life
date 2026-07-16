class_name ManagerHighlightProvider
extends HighlightProvider

## Highlight provider for manage-mode allocation (#176). A pure view-state
## snapshot the [HighlightController] rebuilds when no attack plan or core-move
## targeting is active and it's the player's turn. Tags every unowned node the
## player can allocate with [enum HighlightRole.ALLOCATABLE].

## The player entity whose allocation eligibility is being queried.
var player: Entity = null
var allocation_system: AllocationSystem = null
var graph: Graph = null


func configure(p_player: Entity, p_alloc: AllocationSystem, p_graph: Graph) -> void:
	player = p_player
	allocation_system = p_alloc
	graph = p_graph
	state_changed.emit()


func get_node_role(node: SkillNode) -> HighlightRole:
	if node == null or allocation_system == null or player == null:
		return HighlightRole.NONE
	if allocation_system.can_allocate(node, player):
		return HighlightRole.ALLOCATABLE
	return HighlightRole.NONE

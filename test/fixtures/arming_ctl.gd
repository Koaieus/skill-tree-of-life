extends RefCounted
## Test fixture: the seat's door onto the attack level. A [PlayerInputController]
## wired to an existing board, so a test arms with [method
## PlayerInputController.arm_attack] and reads the plan off
## [method ArmedStack.attack_plan] — the route production uses — instead of
## writing a plan into BattleSystem. The turn's current entity must be [param player]
## or the level drops the plan as another seat's.


static func make(host: GutTest, graph: Graph, alloc: AllocationSystem, bs: BattleSystem,
		tm: TurnManager, player: Entity) -> PlayerInputController:
	var ctl := PlayerInputController.new()
	ctl.graph = graph
	ctl.allocation_system = alloc
	ctl.battle_system = bs
	ctl.turn_manager = tm
	host.add_child(host.autofree(ctl))
	ctl.player = player
	return ctl

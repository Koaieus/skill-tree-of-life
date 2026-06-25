class_name AIController
extends EntityController

## Minimum-viable NPC controller (AI v1, #22). Walks the entity through its
## three phases with a tiny pause between each so the player can read what
## happened, then ends the turn. No infinite loops — every branch exits in
## bounded steps.
##
## EXPAND: allocates one frontier node if any SP is available.
## BATTLE: launches one ranged attack at the nearest hostile node if any AP
## is available and a leaf can reach it. Range-finding is the existing
## RangedAttackPlan logic, so per-leaf range/vision interactions stay live.
##
## Vision is intentionally NOT consulted here — fog of war is a viewer-side
## concept. A proper per-entity vision pass is post-MVP (AI v2 territory);
## v1 plays open-handed against the player. Faction filtering uses
## [member Entity.faction] so future multi-faction support drops in trivially.

@export var turn_delay: float = 0.4

# Cached on first use. Walked once via _find_game_root; cheap lookup.
var _game_root: GameRoot = null


func take_turn() -> void:
	# CONTRACT phase: NPC v1 never voluntarily deallocates.
	await _wait()
	if not _continue():
		return

	# EXPAND phase. Only pause if we actually allocated something — otherwise
	# the AI's turn drags out as a string of empty beats.
	if _turn_manager.current_phase == TurnManager.Phase.CONTRACT:
		_turn_manager.advance_phase()
	if _continue() and entity.stat_board != null:
		var sp: PoolStat = entity.stat_board.skill_points
		if sp != null and sp.current > 0 and _try_allocate_frontier():
			await _wait()

	# BATTLE phase.
	if _continue() and _turn_manager.current_phase == TurnManager.Phase.EXPAND:
		_turn_manager.advance_phase()
	if _continue() and entity.stat_board != null:
		var ap: PoolStat = entity.stat_board.action_points
		if ap != null and ap.current > 0 and await _try_attack():
			await _wait()

	if _continue():
		_turn_manager.end_turn()


func _try_allocate_frontier() -> bool:
	var alloc := _allocation_system()
	if alloc == null or entity.navigator == null:
		return false
	var candidate := _pick_frontier_node()
	if candidate == null:
		return false
	return alloc.allocate(candidate, entity)


## Frontier = unowned node adjacent to a node this entity already owns.
## Picks the first match — no scoring heuristic at v1.
func _pick_frontier_node() -> SkillNode:
	var graph := entity.navigator.graph if entity.navigator != null else null
	if graph == null:
		return null
	for edge in graph.get_edges():
		if edge == null or edge.from == null or edge.to == null:
			continue
		var a := edge.from
		var b := edge.to
		if a.owned_by == entity and b.owned_by == null:
			return b
		if b.owned_by == entity and a.owned_by == null:
			return a
	return null


func _try_attack() -> bool:
	var bs := _battle_system()
	if bs == null:
		return false
	var target := _pick_hostile_target()
	if target == null:
		return false
	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var plan := bs.attack_plan as RangedAttackPlan
	if plan == null:
		return false
	plan.target = target
	if not plan.is_valid():
		bs.cancel_attack()
		return false
	await bs.launch_attack()
	return true


## First hostile node in the graph that isn't us. Faction filter beats raw
## ownership so future allies don't get shot.
func _pick_hostile_target() -> SkillNode:
	var graph := entity.navigator.graph if entity.navigator != null else null
	if graph == null:
		return null
	for node in graph.get_skill_nodes():
		if node == null or node.owned_by == null:
			continue
		var other := node.owned_by
		if other == entity:
			continue
		if other.faction == entity.faction:
			continue
		return node
	return null


# --- helpers ---------------------------------------------------------------

## Bail if the turn has already ended or the entity died mid-turn. Keeps the
## phase walk from racing on side effects.
func _continue() -> bool:
	return _turn_manager != null \
			and _turn_manager.current_entity == entity \
			and is_instance_valid(entity)


func _wait() -> void:
	if turn_delay > 0.0:
		await get_tree().create_timer(turn_delay).timeout


func _game_root_or_null() -> GameRoot:
	if _game_root != null:
		return _game_root
	var n: Node = entity
	while n != null:
		if n is GameRoot:
			_game_root = n
			return _game_root
		n = n.get_parent()
	return null


func _allocation_system() -> AllocationSystem:
	var gr := _game_root_or_null()
	return gr.allocation_system if gr != null else null


func _battle_system() -> BattleSystem:
	var gr := _game_root_or_null()
	return gr.battle_system if gr != null else null

class_name AIController
extends EntityController

## Minimum-viable NPC controller (AI v1, #22). There are no turn phases —
## the controller sequences its own actions within the single turn, pausing
## briefly between them so the player can read what happened, then ends the
## turn. No infinite loops — every branch exits in bounded steps.
##
## Sequence (budget-driven, not phase-driven): NPC v1 never voluntarily
## deallocates → recon pass (fog-aware, per-entity — see [AiRecon]) → spend
## all SP on frontier growth → if no hostile is visible, end turn (growth-only
## short-circuit); otherwise launch one ranged attack at the nearest hostile
## node if any AP is available and a leaf can reach it. Range-finding is the
## existing RangedAttackPlan logic, so per-leaf range/vision interactions
## stay live.
##
## Fog-aware since #378: each AI consults [AiRecon] for its OWN visibility
## (not the shared player-only VisionSystem instance) — settled 2026-08-07,
## "each enemy acts only on what it personally sees", no faction-shared
## reveal in v1. Faction filtering uses [member Entity.faction] so future
## multi-faction support drops in trivially.

@export var turn_delay: float = 0.4
## Tier-gates the combat scorer's cut-vertex / enemy-weak-point / self-shape-
## risk bonuses (see [AiCombatScorer], wired in #378's follow-on slice).
## 0 = naive, picks by raw EV. Kept here (not on the scorer) since it's the
## controller's single behavior-shaping knob.
@export var ai_tier: int = 0
## Verbose `print_rich` trace of candidate scoring / chosen action to the
## console. [signal Events.ai_decision] fires regardless of this toggle —
## this only gates the local console sink.
@export var debug_trace: bool = false
## Explicit injection wins over the GameRoot tree-walk — lets tests wire a
## bare AllocationSystem / BattleSystem without composing a full
## game_root.tscn. Unset in production (GameRoot._ensure_controllers doesn't
## set these), so real levels keep resolving via [method _game_root_or_null]
## unchanged.
@export var allocation_system_override: AllocationSystem = null
@export var battle_system_override: BattleSystem = null

# Cached on first use. Walked once via _find_game_root; cheap lookup.
var _game_root: GameRoot = null


func take_turn() -> void:
	# Opening beat so the handover reads. NPC v1 never voluntarily deallocates.
	await _wait()
	if not _continue():
		return

	var saw_hostile := AiRecon.has_visible_hostile(entity)

	# Spend all available SP on frontier growth, fog-aware or not — the
	# fog short-circuit only gates the ATTACK step below.
	if entity.stat_board != null:
		var sp: SkillPointStat = entity.stat_board.skill_points
		if sp != null:
			while sp.current > 0 and _continue() and _try_allocate_frontier():
				await _wait()

	if not saw_hostile:
		_decide("no visible hostile — growth only")
		if _continue():
			_turn_manager.end_turn()
		return

	# Attack if AP is available and a target is reachable.
	if _continue() and entity.stat_board != null:
		var ap: PoolStat = entity.stat_board.action_points
		if ap != null and ap.current > 0:
			var target := _pick_hostile_target()
			if target != null and await _try_attack(target):
				_decide("ranged attack on %s" % target.name)
				await _wait()
			else:
				_decide("no reachable attack this turn")

	if _continue():
		_turn_manager.end_turn()


## Emits [signal Events.ai_decision] unconditionally, and mirrors it to the
## console when [member debug_trace] is on. The single seam both channels
## (#378) go through.
func _decide(summary: String) -> void:
	Events.ai_decision.emit(entity, summary)
	if debug_trace:
		print_rich("[AIController] %s: %s" % [entity.display_name, summary])


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


func _try_attack(target: SkillNode) -> bool:
	var bs := _battle_system()
	if bs == null or target == null:
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


## First hostile node in the graph that isn't us. `attitude_to` beats raw
## ownership so future allies don't get shot.
func _pick_hostile_target() -> SkillNode:
	var graph := entity.navigator.graph if entity.navigator != null else null
	if graph == null:
		return null
	for node in graph.get_skill_nodes():
		if node == null or node.owned_by == null:
			continue
		var other := node.owned_by
		if entity.attitude_to(other) != Entity.Attitude.HOSTILE:
			continue
		return node
	return null


# --- helpers ---------------------------------------------------------------

## Bail if the turn has already ended or the entity died mid-turn. Keeps the
## action sequence from racing on side effects.
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
	if allocation_system_override != null:
		return allocation_system_override
	var gr := _game_root_or_null()
	return gr.allocation_system if gr != null else null


func _battle_system() -> BattleSystem:
	if battle_system_override != null:
		return battle_system_override
	var gr := _game_root_or_null()
	return gr.battle_system if gr != null else null

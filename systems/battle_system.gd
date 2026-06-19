class_name BattleSystem
extends Node

enum AttackMode {
	NONE,
	MELEE,
	RANGED,
	MAGIC
}

signal attack_plan_changed(plan: AttackPlan)
## Fires for both plan swap and plan-internal mutation. Subscribers that
## care about lifecycle (mount per-mode UI) use [signal attack_plan_changed];
## subscribers that care about content (re-paint highlights) use this one.
signal attack_plan_state_changed

@export var turn_manager: TurnManager
@export var allocation_system: AllocationSystem
@export var attack_vfx: AttackVFX
@export var melee_preview: MeleePreview


var attack_plan: AttackPlan:
	set(value):
		if attack_plan == value:
			return
		if attack_plan != null and attack_plan.state_changed.is_connected(_on_plan_state_changed):
			attack_plan.state_changed.disconnect(_on_plan_state_changed)
		attack_plan = value
		if attack_plan != null:
			attack_plan.state_changed.connect(_on_plan_state_changed)
		attack_plan_changed.emit(value)
		attack_plan_state_changed.emit()


func _on_plan_state_changed() -> void:
	attack_plan_state_changed.emit()

var attack_mode: AttackMode:
	get(): return attack_plan.mode if attack_plan else AttackMode.NONE

var is_attacking: bool:
	get(): return attack_plan != null

func cancel_attack() -> void:
	if is_attacking:
		_reset()
	else:
		push_warning('Cannot cancel attack: not attacking')

func _reset() -> void:
	if attack_plan:
		attack_plan = null

func request_attack_mode(mode: AttackMode) -> void:
	if attack_mode == mode:
		return
	match mode:
		AttackMode.NONE:    cancel_attack()
		AttackMode.MELEE:   attack_plan = _new_plan(MeleeAttackPlan)
		AttackMode.RANGED:  attack_plan = _new_plan(RangedAttackPlan)
		AttackMode.MAGIC:   attack_plan = _new_plan(MagicAttackPlan)

func _new_plan(plan_class: Script) -> AttackPlan:
	var p: AttackPlan = plan_class.new()
	p.attacker = turn_manager.current_entity
	return p

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Events.skill_node_depleted.connect(_on_node_depleted)


## Commit the active plan. Three phases:
##   1. resolve() → AttackOutcome (pure, no side-effects on plan/world)
##   2. await attack_vfx → tracers fly + apply damage on arrival
##   3. AP deduction + plan clear
##
## AP + plan clear happen up front so the player can't spam-click during the
## VFX await window. Without VFX, the volley call is synchronous and damage
## lands immediately.
func launch_attack() -> void:
	if not is_attacking:
		push_warning("BattleSystem.launch_attack: no plan")
		return
	if not attack_plan.is_valid():
		push_warning("BattleSystem.launch_attack: invalid plan: %s" % str(attack_plan.validate()))
		return
	var entity := turn_manager.current_entity if turn_manager != null else null
	if entity == null:
		push_warning("BattleSystem.launch_attack: no current entity")
		return
	var outcome := attack_plan.resolve()
	var ap_pool: PoolStat = entity.stat_board.action_points \
			if entity.stat_board != null else null
	if ap_pool != null and ap_pool.current < float(outcome.ap_cost):
		push_warning("BattleSystem.launch_attack: insufficient AP (%d < %d)" \
				% [int(ap_pool.current), outcome.ap_cost])
		return
	if ap_pool != null:
		ap_pool.deplete(float(outcome.ap_cost))
	# Melee: hand off to the MeleePreview (which has the ghost mounted) for
	# the live swing + damage application BEFORE clearing the plan, so the
	# blade can read selection state during the await. Other modes go via
	# the ranged/magic VFX path that consumes the precomputed outcome.
	if attack_plan is MeleeAttackPlan and melee_preview != null:
		var melee_plan: MeleeAttackPlan = attack_plan
		_reset()
		await melee_preview.launch(melee_plan)
		return
	_reset()
	if attack_vfx != null:
		await attack_vfx.play_ranged_volley(outcome)
	else:
		# Headless / no-VFX path: apply damage directly so tests can still
		# observe the outcome without a scene-attached VFX node.
		for hit in outcome.hits:
			if hit.target != null:
				hit.target.take_damage(hit.amount, hit)


## Forced-deallocation cascade. Runs when a (non-core) node hits 0 HP: the
## depleted node and every node disconnected from the defender's core when
## it leaves are force-dealloc'd; each costs the defender 1 wound + 1 core HP.
##
## "Forced-deallocation lives elsewhere" in AllocationSystem comments —
## that elsewhere is here.
func _on_node_depleted(node: SkillNode) -> void:
	if node == null or allocation_system == null:
		return
	var defender: Entity = node.owned_by
	if defender == null:
		return
	# Cascade snapshot — must be computed BEFORE removing the depleted node
	# from the navigator mirror, or its islanded set goes stale.
	var cascade: Array[SkillNode] = [node]
	if defender.navigator != null and defender.core_location != null:
		cascade.append_array(defender.navigator.nodes_islanded_by_removing(
				node, defender.core_location))
	var board: StatBoard = defender.stat_board
	for n in cascade:
		if n == null or n.owned_by != defender:
			continue
		allocation_system.force_deallocate(n)
		if board != null:
			if board.skill_points != null:
				board.skill_points.wound(1)
			if board.health != null:
				board.health.deplete(1.0)

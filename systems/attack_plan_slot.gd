@tool
class_name AttackPlanSlot
extends Node

## The LOCAL plan-in-progress: which mode is armed, the plan being built, and
## the sticky preferences (spell, swing direction) that outlive a plan. It holds
## no [BattleSystem] reference — a launch in flight reaches it only as
## [member locked], which [BattleSystem] sets alongside every
## [member BattleSystem.is_launching] write. [BattleSystem] forwards every
## member here, so a consumer may still read the plan through it.

signal attack_plan_changed(plan: AttackPlan)

## Fires for both plan swap and plan-internal mutation. Subscribers that
## care about lifecycle (mount per-mode UI) use [signal attack_plan_changed];
## subscribers that care about content (re-paint highlights) use this one.
signal attack_plan_state_changed

## The currently-selected spell for magic attacks. Updated by the spell-picker
## UI; consumed by [method _new_plan] when constructing a [MagicAttackPlan].
## Null means "use the plan's bundled fallback". Live mutation is supported:
## changing this while a magic plan is active re-equips on the active plan
## via [method MagicAttackPlan.set_spell].
signal selected_spell_changed(spell: SpellDef)
var selected_spell: SpellDef = null:
	set(value):
		if selected_spell == value:
			return
		selected_spell = value
		if attack_plan is MagicAttackPlan:
			(attack_plan as MagicAttackPlan).set_spell(value)
		selected_spell_changed.emit(value)

@export var turn_manager: TurnManager
@export var allocation_system: AllocationSystem
## The offerable temp-upgrade kinds (#406, #1008) — authored data, wired to
## `attack/melee/temp_upgrade_catalog.tres` by the composing scene. Optional:
## an unwired slot (headless fixtures that never toggle an upgrade)
## simply offers none — [method temp_upgrade_by_id] answers null and
## [method temp_upgrade_kinds] is empty.
@export var temp_upgrade_catalog: TempUpgradeCatalog

## The viewing seat's fog, handed down to each [MagicAttackPlan] so its
## highlights can be filtered caller-side (#728). Optional — an unwired
## slot (tests, the spell playground) simply casts without fog, which
## is what those callers had before.
@export var vision_system: VisionSystem

const _AMMO_ROSTER: AmmoTypeRoster = preload("res://attack/ammo/ammo_type_roster.tres")

## True while a launch is in flight: cancel, reset and a mode change refuse.
## Written by [BattleSystem] alongside [member BattleSystem.is_launching].
var locked: bool = false


func _ready() -> void:
	_subscribe_union_invalidation()


var attack_plan: AttackPlan:
	set(value):
		if attack_plan == value:
			return
		if attack_plan != null and attack_plan.state_changed.is_connected(_on_plan_state_changed):
			attack_plan.state_changed.disconnect(_on_plan_state_changed)
		attack_plan = value
		if attack_plan != null:
			attack_plan.state_changed.connect(_on_plan_state_changed)
		_sync_pick_sensed()
		attack_plan_changed.emit(value)
		attack_plan_state_changed.emit()


func _on_plan_state_changed() -> void:
	attack_plan_state_changed.emit()


## The sensed-pickability lever (#1033) on [member vision_system]: on while a
## [RangedAttackPlan] is armed and the attacker's quiver holds scout stock —
## the scout shot's target set is the sensed nodes — off for every other plan
## and for none. VisionSystem owns the lever; this system owns the mode; the
## plan never writes another system's state.
func _sync_pick_sensed() -> void:
	if vision_system == null:
		return
	var want := false
	var ranged := attack_plan as RangedAttackPlan
	if ranged != null:
		# The plan's fog for the scout shot: wired on the setter so every
		# assigned RangedAttackPlan gets it, including one not minted by
		# _new_plan.
		ranged.viewer_vision = vision_system
	if ranged != null and ranged.attacker != null and ranged.attacker.stat_board != null:
		var quiver: Quiver = ranged.attacker.stat_board.arrows
		if quiver != null:
			for t in _AMMO_ROSTER.sorted():
				if t.reveal_fraction > 0.0 and quiver.stock_of(t.id) > 0:
					want = true
					break
	vision_system.pick_sensed = want

var attack_mode: BattleSystem.AttackMode:
	get(): return attack_plan.mode if attack_plan else BattleSystem.AttackMode.NONE

var is_attacking: bool:
	get(): return attack_plan != null

func cancel_attack() -> void:
	if is_attacking and not locked:
		_reset()
	else:
		push_warning('Cannot cancel attack: not attacking, or a swing is resolving')


## Clear the active plan's selection state without dropping the plan itself —
## keeps the mode set and any sticky preferences (melee swing_cw, magic spell)
## alive. UI's RESET button routes here.
func reset_plan() -> void:
	if attack_plan != null and not locked:
		attack_plan.reset()

## The single choke point that tears a plan down (#406) — always calls
## reset() first, so a plan's attached temp-upgrade addons (real SkillNode
## children, not plan-owned state) are freed no matter which path got here:
## cancel, RESET-adjacent teardown, or post-launch.
func _reset() -> void:
	if attack_plan:
		attack_plan.reset()
		attack_plan = null

func request_attack_mode(mode: BattleSystem.AttackMode) -> void:
	if locked or attack_mode == mode:
		return
	match mode:
		BattleSystem.AttackMode.NONE:    cancel_attack()
		BattleSystem.AttackMode.MELEE:   attack_plan = _new_plan(MeleeAttackPlan)
		BattleSystem.AttackMode.RANGED:  attack_plan = _new_plan(RangedAttackPlan)
		BattleSystem.AttackMode.MAGIC:   attack_plan = _new_plan(MagicAttackPlan)

## The catalog kind named by [param id] — the door for a temp upgrade's wire
## id — or null if unknown or no catalog is
## wired. Returns the loaded def itself, so identity checks keep working.
func temp_upgrade_by_id(id: StringName) -> TempUpgradeDef:
	if temp_upgrade_catalog == null:
		return null
	return temp_upgrade_catalog.by_id(id)


## The offerable kinds in tray order; empty when no catalog is wired.
func temp_upgrade_kinds() -> Array[TempUpgradeDef]:
	if temp_upgrade_catalog == null:
		return []
	return temp_upgrade_catalog.kinds


## Mints through [method BattleSystem.mint_plan] — the one minter an
## [AIController]'s [method BattleSystem.new_plan] shares — then layers on this
## seat's sticky preferences, which belong to the slot's human alone.
func _new_plan(plan_class: Script) -> AttackPlan:
	var mode := BattleSystem.AttackMode.NONE
	if plan_class == MeleeAttackPlan: mode = BattleSystem.AttackMode.MELEE
	elif plan_class == RangedAttackPlan: mode = BattleSystem.AttackMode.RANGED
	elif plan_class == MagicAttackPlan: mode = BattleSystem.AttackMode.MAGIC
	var p := BattleSystem.mint_plan(mode, turn_manager.current_entity, vision_system)
	if p is MagicAttackPlan and selected_spell != null:
		(p as MagicAttackPlan).spell = selected_spell
	if p is MeleeAttackPlan:
		(p as MeleeAttackPlan).swing_cw = next_melee_cw
	return p


## Sticky preference for the next [MeleeAttackPlan]'s [member MeleeAttackPlan.swing_cw].
## Toggled by UI; survives plan resets so the player doesn't re-pick direction
## every time they switch into melee mode.
var next_melee_cw: bool = false


## The pick-spell-first target union (#728) is cached on the plan and depends on
## (spell, ownership, turn) — never on the hovered or committed target, which is
## why it cannot ride [signal AttackPlan.state_changed] like the older caches do.
## Ownership and turn move it from OUTSIDE the plan, so the invalidation is
## pushed from here, over the same allocation signals [VisionSystem] listens to
## for the same reason.
##
## It matters more than it used to: with the source set derived from ownership
## rather than clicked, allocating a high-degree node mid-turn has to make the
## spell castable immediately — a stale union would keep saying "no caster"
## while the player looks at the node that fixes it.
func _subscribe_union_invalidation() -> void:
	if allocation_system != null:
		allocation_system.allocated.connect(_invalidate_plan_union.unbind(3))
		allocation_system.deallocated.connect(_invalidate_plan_union.unbind(2))
		allocation_system.force_deallocated.connect(_invalidate_plan_union.unbind(2))
	# `TurnManager` is not @tool, so in the editor the engine hands this @tool
	# script a placeholder: `.turn_started` as a PROPERTY read throws there
	# (gdscript-pitfalls.md), while connecting by name goes through Object's
	# signal table and works on placeholder and real instance alike.
	if turn_manager != null:
		turn_manager.connect(&"turn_started", _invalidate_plan_union.unbind(1))


## Emits the PLAN's [signal AttackPlan.state_changed], not this system's
## [signal attack_plan_state_changed] directly: the latter reaches the HUD
## bodies and [PlayerInputController] but NOT the highlight overlays, which
## repaint off [signal HighlightController.provider_state_changed] — i.e. off
## the plan's own signal. Allocating a node that newly clears a spell's
## `min_degree` therefore left the painted caster/target sets stale until an
## unrelated hover forced a repaint. Going through the plan reaches both:
## [method _on_plan_state_changed] re-emits it here.
##
## This is the opposite direction from [method _subscribe_union_invalidation]'s
## warning and does not reintroduce it — the union must not be INVALIDATED BY
## `state_changed` (target hover fires it constantly); invalidating it and then
## announcing the change is fine, and terminates: `state_changed` only sets
## dirty flags on the plan and re-emits outward.
func _invalidate_plan_union() -> void:
	var magic_plan := attack_plan as MagicAttackPlan
	if magic_plan != null:
		magic_plan.invalidate_union()
		magic_plan.state_changed.emit()

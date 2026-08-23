@tool
class_name Entity
extends Node

## An entity that lives on the skill tree. Owns a connected induced
## subgraph of SkillNodes. Identity + colour + an optional stat board, plus
## a child `EntityNavigator` that mirrors the owned-subgraph for connectivity
## queries (islanding checks now; combat path/reach queries later).

signal core_location_changed
signal leveled_up(new_level: int)
signal died

## The player/enemy relation. Two teams for now (#384): [constant ALLIED] is
## same-[member faction], [constant HOSTILE] is everything else. Enemies do
## not fight each other, so a scalar faction resolves it with no attitude
## matrix — going multi-faction later changes only [method attitude_to], not
## its call sites.
enum Attitude { SELF, ALLIED, HOSTILE }

@export var display_name: String = "Entity"
@export var color: Color = Color.WHITE
## Team identity, composed like [member core_class]. Defaults to the shared
## [code]npc.tres[/code] faction; authored per-entity — a hand-authored
## scene sets its own export override, a roster-driven spawn gets it from
## [method GameRoot.apply_roster] (#475). Singular, compared by
## [member Faction.id]: two entities whose factions share an id are allies,
## even across separately-loaded/duplicated resource instances.
@export var faction: Faction = preload("res://entity/factions/npc.tres")
## Whether a human (local or remote) drives this entity — the seam
## [method GameRoot._ensure_controllers] reads to attach [PlayerController]
## vs [AIController]. Authored per-entity (roster-driven spawn via
## [method GameRoot.apply_roster], or set directly on a hand-authored scene's
## node) rather than derived from entity identity. See #475.
@export var is_human_controlled: bool = false
@export var stat_board: EntityStatBoard = null
## Class specialization for this entity. Applied once on _ready via
## `core_class.apply(self)` and consulted each turn via `on_turn_started`.
## Optional — null means a plain entity with no class bonuses.
@export var core_class: CoreClass = null
## Spells this entity knows + the gating logic for whether they can be cast
## from a given node (degree, etc.). Surfaced by the spell-picker UI and
## consulted by AI when scoring magic attacks. Promotion of a known spell
## into the active slot happens via [member BattleSystem.selected_spell].
@export var spellbook: SpellBook = null

## Reward tier (#300): sizes the killing-blow XP bonus (`tier_xp_base × tier²`,
## see LootSystem) and the SkillDust pick count (`victim.entity_tier`). Players
## and ordinary NPCs keep the default 3, so nothing changes by omission;
## removable-node blockers author 1/2/3 for small/medium/large.
@export var entity_tier: int = 3

## Wire identity (#509) — the only legal way a [Command] refers to an entity,
## exactly as [member SkillNode.stable_id] is for nodes. Minted once by
## [method Graph._mint_entity_id] on entry to `entities_container` and never
## reused; 0 means unminted (an entity built in a test and never parented
## under a Graph). Plain var, not @export: it's Graph-assigned runtime
## identity, not authored content — see .claude/rules/gdscript-pitfalls.md on
## never writing a derived value back into an @export.
var entity_id: int = 0


## The entity's spellbook, created empty if it doesn't have one yet. Every
## entity *has* a book — an empty one is a real state, not an absent one — so
## granting a spell is never a no-op for lack of somewhere to put it.
## `entity.tscn` bakes one in; this covers entities built via `Entity.new()`
## (tests, sandboxes). Prefer this over touching [member spellbook] when you
## are about to write to the book; reads that tolerate "knows nothing" can
## still check the field directly.
func get_spellbook() -> SpellBook:
	if spellbook == null:
		spellbook = SpellBook.new()
	return spellbook


@export var core_location: SkillNode:
	set(value):
		if core_location == value:
			return
		var previous := core_location
		core_location = value
		core_location_changed.emit()
		# EVERY core placement re-derives auras, not just `AllocationSystem.move_core`.
		# The opening placement — `spawn_entity` assigning core_location after
		# `_ready` already granted the core class's effects, or scene-export
		# deserialization — never passes through move_core. Dispatching from the
		# setter is the only point that catches all of them. (No recursion: in
		# GDScript, assigning a property to its own backing field inside its setter
		# does not re-enter the setter.)
		dispatch(&"_on_core_moved", [previous, value])

## [member faction]'s [member Faction.id], or [code]&""[/code] with no faction
## assigned. For call sites that genuinely want the identifier rather than the
## relation — prefer [method attitude_to] for any hostility test.
var faction_id: StringName:
	get:
		return faction.id if faction != null else &""

## The ONLY place the player/enemy relation is decided (#384) — every other
## hostility test (targeting, XP gating, AI) routes through this or through
## [method SkillNode.ownership_bit], which delegates here. Same-[member faction]
## is ALLIED, compared by [member Faction.id] (not resource reference — a
## `.tres` loaded twice or `duplicate()`d must still compare equal). A null
## faction or an empty id on either side never matches, so two faction-less
## entities read HOSTILE rather than silently allying.
func attitude_to(other: Entity) -> Attitude:
	if other == self:
		return Attitude.SELF
	if faction != null and other.faction != null and faction.id != &"" \
			and faction.id == other.faction.id:
		return Attitude.ALLIED
	return Attitude.HOSTILE

## Current level. A proxy onto the `level` ScalarStat on the stat board — that's
## the canonical store (#200) so level-scaling formula modifiers can bind to it.
## Bumped (+1 base_value) on each xp fill in `_on_xp_replenished`; the getter's
## `.value` folds in any level modifiers and coerces to INT, the setter forwards
## to base_value. Falls back to 1 / no-ops for sparse boards with no `level` stat.
var level: int:
	get:
		if stat_board != null and stat_board.level != null:
			return int(stat_board.level.value)
		return 1
	set(v):
		# Convenience mutator — forwards to the one canonical store (the stat's
		# base_value), so there's no second source of truth. No-ops on sparse
		# boards. The level-up path writes base_value directly (see
		# `_on_xp_replenished`); this exists for scripted/test setup.
		if stat_board != null and stat_board.level != null:
			stat_board.level.base_value = v

## The initiative clock lives on the stat board as the `initiative` PoolStat
## (cap = this entity's action threshold). It fills by `initiative_speed` each
## TurnManager tick; crossing the cap fires `replenished`, which adds this
## entity to the `READY_GROUP` for TurnManager to serve. See _ready / TurnManager.
const READY_GROUP := &"ready_to_act"

## Group every Entity joins on enter_tree. TurnManager enumerates it to tick
## initiative and serve turns; death cleanup removes the corpse so it's skipped.
const GROUP := &"entities"

## #152: fallback AP→surplus conversion used only when a board carries no
## `ap_transfer_rate` stat (sparse / test boards). The live knob is the
## `ap_transfer_rate` ScalarStat — see `_transfer_unused_ap_to_surplus`.
const DEFAULT_AP_TRANSFER_RATE := 2.0

## Auto-created on _ready when the entity has a Graph ancestor. Stays null
## in editor (`@tool` short-circuit) and in stand-alone tests with no graph.
var navigator: EntityNavigator

## Latch for [method initialize] — bring-up runs exactly once per entity, from
## `_ready` in a running game or from a live sandbox that has to ask.
var _initialized: bool = false

## Live [Effect] attachments, in grant order. Each holds its own grant ledger,
## so revocation is exact without a provenance field on [StatModifier].
var _effect_instances: Array[EffectInstance] = []

## The granted-atom ledger for CORE modifiers (#323) — every [StatModifier]
## ever permanently granted onto this entity's core, UNFLATTENED. Two honest
## layers: this register is what LootSystem's draw reads from (composites stay
## intact, so a `loots_as_unit` pack is still one atom if this entity later
## dies); [member stat_board] is the flattened, bound leaves the board computes
## stats from. [method grant_core_modifier] is the ONLY path that writes here —
## same shape as [EffectContext]'s handle-owned pattern — so register/board
## drift is impossible by construction.
var core_modifiers: Array[StatModifier] = []


## The only path that grants a modifier onto this entity's core permanently.
## Appends `m` to [member core_modifiers] (register) and mirrors it onto
## [member stat_board] (the flattened, computed layer). Both [CoreClass.apply]
## (class-template grants) and SkillDust pickup (looted grants) route through
## this — see #323.
##
## Does NOT duplicate `m` — per #377, formula binding is stateless (lives on
## the Stat/Board, not the modifier), so the SAME shared `.tres` instance
## already applies safely to every entity of a class, and a looted candidate
## arrives here already an independent copy (LootSystem's draw duplicates when
## building the payload). Duplicating again here would just be redundant work
## on the class path and double-duplication on the loot path.
func grant_core_modifier(m: StatModifier) -> void:
	if m == null:
		return
	core_modifiers.append(m)
	if stat_board != null:
		stat_board.add_modifier(m)

## `hook name -> Array[EffectInstance]`. Bucketed once at grant time by asking
## each effect which optional hooks it implements, so `dispatch` touches only
## interested effects rather than walking every attachment on every event.
var _hook_buckets: Dictionary[StringName, Array] = {}

## Latched once `die()` runs, so death cleanup happens exactly once even if the
## `health` pool re-emits `depleted` mid-cascade. Systems read this to skip a
## corpse (TurnManager initiative, AI targeting).
var is_dead: bool = false

## Refcounted status markers, entity-wide twin of [member SkillNode._tags] — see
## docs/design/status-tags.md. Granted/revoked through [method EffectContext.grant_tag]
## / `revoke`, never written to directly.
var _tags: Dictionary[StringName, int] = {}

## The live combat-state slice (#498 step 1, docs/domain/attack-timeline.md).
## Entity COMPOSES this — it owns the live one, it does not copy one.
## Constructed here (a field initializer, not `_ready`) so it exists before
## any pre-`_ready` caller could reach for it.
var _combat := EntityCombat.new(self)


## Public accessor for [member _combat] — [AllocationSystem] (a different
## file) needs it to run the revoke sweep on a node's PREVIOUS owner; a plain
## getter keeps `_combat` itself construction-assigned with no public setter.
func get_combat() -> EntityCombat:
	return _combat


func _ready() -> void:
	# Group membership is editor-safe and lets @tool consumers (e.g.
	# VisionSystem) enumerate entities live in the inspector.
	add_to_group(GROUP)
	if Engine.is_editor_hint():
		return
	initialize()


## Bring this entity to life: navigator, board duplication + intrinsics, core
## class, and every re-emit subscription. Idempotent — a second call is a no-op,
## so it can never double-apply intrinsics.
##
## Public, and separate from [method _ready], because the editor never runs
## `_ready` (see the guard above) and a LIVE sandbox tab hosting an *authored*
## entity has to say when bring-up happens. Calling this is the whole difference
## between an inert inspector object and a real entity; there is deliberately no
## second, sandbox-flavoured copy of it.
func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	var g := _find_graph()
	if g == null:
		push_warning("Entity '%s' has no Graph ancestor; navigator disabled" % display_name)
	else:
		navigator = EntityNavigator.new()
		navigator.name = "EntityNavigator"
		navigator.entity = self
		navigator.graph = g
		add_child(navigator)
		if Engine.is_editor_hint():
			# EntityNavigator._ready deliberately no-ops in the editor (a @tool
			# mirror must not wire itself just because a scene is open). An
			# explicit `initialize()` is the opposite situation, so wire it here.
			navigator.wire_to(g)

	# Every entity.tscn instance shares the SAME authored spellbook_default.tres
	# resource object (ResourceLoader caches by path) unless duplicated here —
	# same rationale as stat_board immediately below.
	if spellbook != null:
		spellbook = spellbook.duplicate(true)

	# Initialize stat board and wiring
	if stat_board != null:
		stat_board = stat_board.duplicate(true)
		stat_board.apply_intrinsics()
		if core_class != null:
			core_class.apply(self)
		if stat_board.xp != null:
			stat_board.xp.replenished.connect(_on_xp_replenished)
			# Re-emit XP grants on the bus keyed by self — same rationale as the
			# SP wound/heal forwards below (a stat doesn't know its owner).
			stat_board.xp.replenished_by.connect(_emit_entity_xp_gained)
		# Initiative clock crossed its cap → this entity is ready to act.
		# TurnManager serves from READY_GROUP; it removes us again on start_turn.
		if stat_board.initiative != null:
			stat_board.initiative.replenished.connect(_on_initiative_ready)
		# Re-emit SP wound/heal on the global Events bus, keyed by self so
		# floater layers don't need to bind per-entity. The signals on
		# SkillPointStat fire on transfers, not on every value_changed —
		# safe to forward without spam.
		if stat_board.skill_points != null:
			stat_board.skill_points.wounds_applied.connect(_emit_entity_wounded)
			stat_board.skill_points.wounds_healed.connect(_emit_entity_healed)
		# Core HP is the entity's `health` pool: combat-HP overflow on the core
		# node eats it (see SkillNode.take_damage), and it hits 0 → the entity
		# dies. The core node never emits `depleted` itself (#18).
		if stat_board.health != null:
			stat_board.health.depleted.connect(_on_health_depleted)

	var tm := _find_turn_manager()
	if tm != null:
		tm.turn_started.connect(_on_turn_started)
		tm.turn_ended.connect(_on_turn_ended)


#region Effects
## Attach [param effect] to this entity, optionally sourced from [param source_node]
## (a keystone or addon carrier). Runs `_on_granted`, which by default applies the
## effect's modifiers and — for an [AuraEffect] — computes its first buffed set.
##
## Call only once the entity's world is coherent: `navigator` live, `core_location`
## set, `stat_board` duplicated. An aura granted before then reads an empty subgraph.
func grant_effect(effect: Effect, source_node: SkillNode = null) -> EffectInstance:
	if effect == null:
		return null
	var inst := EffectInstance.new()
	inst.effect = effect
	inst.source_node = source_node
	inst.context = EffectContext.new(_combat, inst)
	_effect_instances.append(inst)
	for hook in effect.implemented_hooks():
		if not _hook_buckets.has(hook):
			_hook_buckets[hook] = []
		_hook_buckets[hook].append(inst)
	effect._on_granted(inst.context)
	return inst


## Detach an effect, reverting every modifier it granted (wherever it landed —
## this entity's board or any node's `node_board`).
func revoke_effect(inst: EffectInstance) -> void:
	if inst == null or not _effect_instances.has(inst):
		return
	inst.effect._on_revoked(inst.context)
	for hook in _hook_buckets:
		_hook_buckets[hook].erase(inst)
	_effect_instances.erase(inst)


## Revoke every effect a given node granted — the deallocation path. Node-bound
## effects are dormant while the node is unowned.
func revoke_effects_from(source_node: SkillNode) -> void:
	for inst in _effect_instances.duplicate():
		if inst.source_node == source_node:
			revoke_effect(inst)


## Fire [param hook] on every effect that implements it, passing its context
## first. Iterates a copy: a hook may grant or revoke effects re-entrantly.
func dispatch(hook: StringName, args: Array = []) -> void:
	var bucket: Array = _hook_buckets.get(hook, [])
	if bucket.is_empty():
		return
	for inst: EffectInstance in bucket.duplicate():
		var call_args: Array = [inst.context]
		call_args.append_array(args)
		inst.effect.callv(hook, call_args)


func get_effects() -> Array[EffectInstance]:
	return _effect_instances.duplicate()


## Increment [param tag]'s refcount, creating the entry at 1 if new.
func add_tag(tag: StringName) -> void:
	_combat.add_tag(tag)


## Decrement [param tag]'s refcount; drops the entry entirely at 0 so
## [method get_active_tags] only ever reports what's actually live.
func remove_tag(tag: StringName) -> void:
	_combat.remove_tag(tag)


func has_tag(tag: StringName) -> bool:
	return _combat.has_tag(tag)


## The live tag set — no [StatRegistry] entry, no board slot.
func get_active_tags() -> Array[StringName]:
	var out: Array[StringName] = []
	for t in _tags:
		out.append(t)
	return out
#endregion


## Listens for TurnManager.turn_started. Each entity self-handles its own
## start-of-turn upkeep so we don't grow a god-mode TurnManager. Per-turn
## bookkeeping today: replenish pools (per each pool's per_turn_mode, including
## skill_points' CUSTOM wound-heal), run the gated node regen sweep (D-9) plus
## the class aura (D-10), run the class hook.
func _on_turn_started(entity: Entity) -> void:
	if entity != self or stat_board == null:
		return
	# All pool upkeep is declarative — each pool replenishes per its def's
	# per_turn_mode (AP/DP/movement REFILL, mana/xp ADD, skill_points CUSTOM
	# wound-heal). New pools opt in via their def; nothing is wired here.
	stat_board.apply_per_turn_upkeep()
	# D-9: turn-start refill-to-full is gone. Every owned node instead runs a
	# gated, ramping regen (SkillNode.apply_turn_regen) — damage persists
	# across turns. D-10's class aura is layered on top, computed once per
	# turn over the OWNED subgraph (never graph.navigator — see
	# .claude/rules/graph.md "Reach queries") and applied outside the D-9
	# gate: it heals through combat and grants no ramp.
	if navigator != null:
		var aura: CoreAura = core_class.aura if core_class != null else null
		var aura_values: Dictionary[SkillNode, float] = {}
		if aura != null and core_location != null:
			aura_values = aura.values_from(core_location, navigator)
		for n in navigator.get_mirrored_nodes():
			n.apply_turn_regen()
			var aura_value: float = aura_values.get(n, 0.0)
			if aura_value > 0.0:
				aura.apply(n, aura_value)
	if core_class != null:
		core_class.on_turn_started(self)
	dispatch(&"_on_turn_start")


## Listens for TurnManager.turn_ended. Transfers unused action points into next
## turn's DP/MP surplus (#152), then runs effect dispatch. Surplus is written
## here — not on turn start — because unused AP is only known once the turn is
## over; turn-start REFILL then leaves the surplus untouched (it sits outside the
## cap). set_surplus *overwrites*, so a turn ending with 0 unused AP self-clears
## last turn's boost.
func _on_turn_ended(entity: Entity) -> void:
	if entity != self:
		return
	_transfer_unused_ap_to_surplus()
	dispatch(&"_on_turn_end")


func _transfer_unused_ap_to_surplus() -> void:
	if stat_board == null or stat_board.action_points == null:
		return
	# `ap_transfer_rate` is a real board stat, so class identity (Pacifist ↑,
	# Berserker → 0) and future DEX scaling tune it via modifiers, no code change.
	# roundi the *product* so a fractional rate doesn't truncate the unused AP.
	var rate: float = stat_board.ap_transfer_rate.get_value() if stat_board.ap_transfer_rate != null else DEFAULT_AP_TRANSFER_RATE
	var boost := roundi(stat_board.action_points.current * rate)
	if stat_board.deallocation_points != null:
		stat_board.deallocation_points.set_surplus(boost)
	if stat_board.movement_points != null:
		stat_board.movement_points.set_surplus(boost)


## Listens for initiative.replenished (clock crossed its cap). Joins the ready
## group; TurnManager picks the highest-overshoot member and removes it on
## start_turn. The CyclicPoolStatDef has already carried the overshoot forward,
## so `current` is back near zero — readiness is the group membership, not the value.
func _on_initiative_ready() -> void:
	add_to_group(READY_GROUP)


## Listens for xp.replenished (pool crossed into full). Pool growth + current
## carry-over are handled by the def when it's a `GrowablePoolStatDef`; here
## we mint 1 SP via grant() (bumps both max and current), bump the `level` stat,
## and emit leveled_up. Writing base_value auto-emits value_changed, so any
## level-scaling formula modifier bound to `level` recalculates (#200/#194).
func _on_xp_replenished() -> void:
	if stat_board == null or stat_board.xp == null:
		return
	if stat_board.level != null:
		stat_board.level.base_value += 1
	if stat_board.skill_points != null:
		# D-16 (#271): SP minted per level-up is a stat, not a hardcoded 1 —
		# lets a CoreClass/keystone/node deviate through the normal modifier
		# pipeline. Falls back to 1 for sparse boards with no such stat.
		var sp_gain := 1
		if stat_board.sp_gain_on_levelup != null:
			sp_gain = roundi(stat_board.sp_gain_on_levelup.value)
		# Milestone bonus: +1 extra SP on every 5th level (5, 10, 15, ...).
		if level % 5 == 0:
			sp_gain += 1
		stat_board.skill_points.grant(sp_gain)
	leveled_up.emit(level)
	dispatch(&"_on_level_up", [level])

## Listens for health.depleted (Entity's core health reduced to 0) → entity dies.
func _on_health_depleted() -> void:
	die()


## Mark the entity dead and announce it. Entity stays dumb here: the actual
## cleanup (force-deallocate every owned node, free NPCs, player game-over) is
## owned by systems reacting to `Events.entity_died` off the bus — same pattern
## as BattleSystem←skill_node_depleted. Idempotent: death can fire re-entrantly
## from inside a forced-dealloc cascade (chip damage to `health`), so guard.
func die() -> void:
	if is_dead:
		return
	is_dead = true
	died.emit()
	# Before the bus phases: effects see the corpse fully intact (nodes still
	# owned, modifiers still applied), same pre-strip world LootSystem relies on.
	dispatch(&"_on_entity_dying")
	# Two-phase, in order: `entity_dying` fires with the corpse still intact
	# (LootSystem snapshots loot + awards XP here), THEN `entity_died` drives
	# cleanup (AllocationSystem strips nodes, GameRoot despawns). emit() is
	# synchronous, so every dying-handler finishes before any died-handler —
	# the phases sequence themselves, no tree-order dependency. See Events.
	Events.entity_dying.emit(self)
	Events.entity_died.emit(self)
	# #504: the death is drawn at the moment the model dies, so this fires here
	# rather than out of a replayed timeline. LAST, after `entity_died`, because
	# GameRoot's handler for it despawns the corpse and AllocationSystem's
	# `entity_died` strip must have run against a still-owned world first (see
	# `.claude/rules/entity-death.md`).
	Events.entity_death_shown.emit(self)


func _emit_entity_wounded(amount: int) -> void:
	Events.entity_wounded.emit(self, amount)


func _emit_entity_healed(amount: int) -> void:
	Events.entity_healed.emit(self, amount)


func _emit_entity_xp_gained(amount: float) -> void:
	Events.entity_xp_gained.emit(self, amount)


## Group lookup, not tree walk: TurnManager lives at `GameRoot/Systems/...`,
## a sibling of Graph, so an ancestor get_children() walk never reaches it.
## TurnManager joins its group in `_enter_tree`, which fires before any
## spawned entity's _ready.
func _find_turn_manager() -> TurnManager:
	return get_tree().get_first_node_in_group(TurnManager.GROUP) as TurnManager


func _find_graph() -> Graph:
	var n: Node = get_parent()
	while n != null:
		if n is Graph:
			return n as Graph
		n = n.get_parent()
	return null


func _to_string() -> String:
	return "Entity<%s--%s>" % [display_name, core_location as Variant if core_location else 'N/A']

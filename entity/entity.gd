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

@export var display_name: String = "Entity"
@export var color: Color = Color.WHITE
## Faction identifier for hostility checks. Single-faction MVP: player gets
## `&"player"`, NPCs default to `&"npc"`. Hostility today still uses
## `owned_by != attacker`; multi-faction is a one-line filter swap later.
@export var faction: StringName = &"npc"
@export var stat_board: StatBoard = null
## Class specialization for this entity. Applied once on _ready via
## `core_class.apply(self)` and consulted each turn via `on_turn_started`.
## Optional — null means a plain entity with no class bonuses.
@export var core_class: CoreClass = null
## Spells this entity knows + the gating logic for whether they can be cast
## from a given node (degree, etc.). Surfaced by the spell-picker UI and
## consulted by AI when scoring magic attacks. Promotion of a known spell
## into the active slot happens via [member BattleSystem.selected_spell].
@export var spellbook: SpellBook = null
@export var core_location: SkillNode:
	set(value):
		if core_location == value:
			return
		core_location = value
		core_location_changed.emit()

## Current level. Bumps on every xp pool fill via `_on_xp_replenished`.
## Tracked here (not on the stat board) so the signal payload is meaningful
## without a dedicated `level` Stat — promote to a real stat if level-scaling
## modifiers start showing up.
var level: int = 1

## The initiative clock lives on the stat board as the `initiative` PoolStat
## (cap = this entity's action threshold). It fills by `initiative_speed` each
## TurnManager tick; crossing the cap fires `replenished`, which adds this
## entity to the `READY_GROUP` for TurnManager to serve. See _ready / TurnManager.
const READY_GROUP := &"ready_to_act"

## Group every Entity joins on enter_tree. TurnManager enumerates it to tick
## initiative and serve turns; death cleanup removes the corpse so it's skipped.
const GROUP := &"entities"

## Auto-created on _ready when the entity has a Graph ancestor. Stays null
## in editor (`@tool` short-circuit) and in stand-alone tests with no graph.
var navigator: EntityNavigator

## Latched once `die()` runs, so death cleanup happens exactly once even if the
## `health` pool re-emits `depleted` mid-cascade. Systems read this to skip a
## corpse (TurnManager initiative, AI targeting).
var is_dead: bool = false


func _ready() -> void:
	# Group membership is editor-safe and lets @tool consumers (e.g.
	# VisionSystem) enumerate entities live in the inspector.
	add_to_group(GROUP)
	if Engine.is_editor_hint():
		return
	var g := _find_graph()
	if g == null:
		push_warning("Entity '%s' has no Graph ancestor; navigator disabled" % display_name)
	else:
		navigator = EntityNavigator.new()
		navigator.name = "EntityNavigator"
		navigator.entity = self
		navigator.graph = g
		add_child(navigator)

	# Initialize stat board and wiring
	if stat_board != null:
		stat_board.apply_intrinsics()
		if core_class != null:
			core_class.apply(self)
		if stat_board.xp != null:
			stat_board.xp.replenished.connect(_on_xp_replenished)
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


## Listens for TurnManager.turn_started. Each entity self-handles its own
## start-of-turn upkeep so we don't grow a god-mode TurnManager. Per-turn
## bookkeeping today: replenish pools (per each pool's per_turn_mode, including
## skill_points' CUSTOM wound-heal), refill owned-node HP, run the class hook.
func _on_turn_started(entity: Entity) -> void:
	if entity != self or stat_board == null:
		return
	# All pool upkeep is declarative — each pool replenishes per its def's
	# per_turn_mode (AP/DP/movement REFILL, mana/xp ADD, skill_points CUSTOM
	# wound-heal). New pools opt in via their def; nothing is wired here.
	stat_board.apply_per_turn_upkeep()
	# Per-node combat HP refill — every node owned by this entity returns to
	# full. Lives here rather than on the node itself so a single sweep on
	# turn start beats every node subscribing to a turn-manager signal.
	if navigator != null:
		for n in navigator.get_mirrored_nodes():
			n.refill()
	if core_class != null:
		core_class.on_turn_started(self)


## Listens for initiative.replenished (clock crossed its cap). Joins the ready
## group; TurnManager picks the highest-overshoot member and removes it on
## start_turn. The CyclicPoolStatDef has already carried the overshoot forward,
## so `current` is back near zero — readiness is the group membership, not the value.
func _on_initiative_ready() -> void:
	add_to_group(READY_GROUP)


## Listens for xp.replenished (pool crossed into full). Pool growth + current
## carry-over are handled by the def when it's a `GrowablePoolStatDef`; here
## we just mint 1 SP via grant() (bumps both max and current) and emit leveled_up.
func _on_xp_replenished() -> void:
	if stat_board == null or stat_board.xp == null:
		return
	if stat_board.skill_points != null:
		stat_board.skill_points.grant(1)
	level += 1
	leveled_up.emit(level)

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
	# Two-phase, in order: `entity_dying` fires with the corpse still intact
	# (LootSystem snapshots loot + awards XP here), THEN `entity_died` drives
	# cleanup (AllocationSystem strips nodes, GameRoot despawns). emit() is
	# synchronous, so every dying-handler finishes before any died-handler —
	# the phases sequence themselves, no tree-order dependency. See Events.
	Events.entity_dying.emit(self)
	Events.entity_died.emit(self)

func _emit_entity_wounded(amount: int) -> void:
	Events.entity_wounded.emit(self, amount)


func _emit_entity_healed(amount: int) -> void:
	Events.entity_healed.emit(self, amount)


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

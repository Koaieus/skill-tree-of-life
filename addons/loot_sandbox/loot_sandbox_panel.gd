@tool
extends PanelContainer

## LootSystem LIVE panel (#260) — the played showcase's heir. Drives a real
## kill against the REAL systems and shows the rewards land: an XP floater
## climbing on the killer, a SkillDust relic blooming on the victim's former
## core, and the death cascade. A phase selector demonstrates the per-side-effect
## kill-switches (`LootSystem.award_xp_on_kill` / `drop_skill_dust_on_death`).
##
## How it's live: the reward chain resolves synchronously off the `Events` bus
## (LootSystem is @tool; `entity_dying` fires inside the victim's death call
## stack). The ONE runtime-only dependency is `TurnManager.current_entity`,
## used for killer attribution — the panel WRITES it directly before the kill
## and never ticks / starts / ends a turn. That holds the guardrail from
## sandbox-framework.md: "auto-tick = played; explicit-step = live". Kills must
## be one-at-a-time (the attribution slot is single), so the buttons gate
## during the async reset.
##
## The victim carries a real CoreClass (`balanced_core.tres`) — without one
## `_draw_payload` has no candidates and the dust drop no-ops, which is exactly
## how the old played showcase silently lost its relic after the #173 rework.
##
## The world renders in a SubViewport (SubViewportContainer stretch=true), so
## container pixels ARE world pixels; attacker/victim are laid out against the
## viewport's live size, no camera needed.

const _SKILL_NODE_SCENE: PackedScene = preload("res://skill_node/skill_node.tscn")
const _SANDBOX_WORLD: Script = preload("res://scenes/dev/sandbox_world.gd")
const _DEFAULT_BOARD: Resource = preload("res://entity/default_entity_board.tres")
const _BALANCED_CORE: CoreClass = preload("res://entity/core/balanced_core.tres")
const _PLAYER_FACTION: Faction = preload("res://entity/factions/player.tres")

@export var victim_level: int = 3       ## scales XP award + dust payload size
@export var str_per_node: float = 6.0

@onready var graph: Graph = %Graph          ## The embedded world's graph (test/driver hook)
var _alloc: AllocationSystem
var _battle: BattleSystem
var _loot: LootSystem
var _tm: TurnManager
var _vfx: AllocationVFX
var _floaters: FloaterToasterManager
var _busy: bool = false

var _attacker: Entity
var _victim: Entity
var _attacker_core: SkillNode
var _victim_core: SkillNode
var _victim_nodes: Array[SkillNode] = []

# Phase table: which reward(s) are live this phase (mirrors the OptionButton).
var _phases := [
	{"xp": true,  "dust": true,  "desc": "full rewards — XP floater + SkillDust relic"},
	{"xp": true,  "dust": false, "desc": "drop_skill_dust_on_death = false — XP only"},
	{"xp": false, "dust": true,  "desc": "award_xp_on_kill = false — relic only"},
]

@onready var _phase_option: OptionButton = %PhaseOption
@onready var _kill_button: Button = %KillBtn
@onready var _reset_button: Button = %ResetBtn
@onready var _stat_label: Label = %StatLabel
@onready var _world: SubViewport = %World


## The SandboxLiveTab loader hook. Self-contained — nothing to route in.
func load_object(_obj: Object) -> void:
	pass


func _ready() -> void:
	_kill_button.pressed.connect(kill_victim)
	_reset_button.pressed.connect(reset_world)
	_phase_option.item_selected.connect(select_phase)
	_world.size_changed.connect(_layout_world)
	_build_systems()
	_build_world()
	# Present the world ARMED: ownership + core_locations in place from the
	# start (the kill reads `victim.core_location` for the dust drop), muted —
	# nothing animates until the user presses a button.
	_vfx.muted = true
	_rearm_world()
	_vfx.muted = false
	_layout_world()
	select_phase(0)
	_refresh_labels()


# --- Composition -------------------------------------------------------------

func _build_systems() -> void:
	# Loot needs the full reward chain — request TurnManager (killer attribution)
	# + LootSystem on top of the shared scaffold's allocation core.
	var world = _SANDBOX_WORLD.new()
	world.name = "SandboxWorld"
	_world.add_child(world)
	world.build(graph, {"loot": true})
	_alloc = world.allocation_system
	_battle = world.battle_system
	_loot = world.loot_system
	_tm = world.turn_manager
	_vfx = world.allocation_vfx
	_floaters = world.floating_number_layer
	# Sub-cap award (xp cap is 5): keeps the kill XP observable as a delta without
	# triggering a level-up, which would grow the xp cap + mint SP permanently and
	# make the per-phase reset drift. The panel is about loot landing, not levels.
	_loot.xp_per_node_killed = 1.0
	_loot.entity_kill_bonus = 1.0


## Attacker (left) + victim (right). The victim carries a real core class so the
## dust payload is non-empty (#173 rework: `_draw_payload` reads the core set
## only — a class-less victim drops nothing) — and STR-bearing nodes so its STR
## is worth watching. No edge between the two — the kill is direct `take_damage`,
## not a graph attack.
func _build_world() -> void:
	_attacker_core = _make_node(Color(0.40, 0.80, 1.00))
	_victim_core = _make_node(Color(0.95, 0.45, 0.45), str_per_node)
	_victim_nodes = [
		_make_node(Color(0.95, 0.45, 0.45), str_per_node),
		_make_node(Color(0.95, 0.45, 0.45), str_per_node),
	]
	graph.add_edge(_victim_core, _victim_nodes[0])
	graph.add_edge(_victim_core, _victim_nodes[1])

	_attacker = _spawn_entity("Attacker", Color(0.40, 0.80, 1.00))
	_attacker.faction = _PLAYER_FACTION  # #384/#386: HOSTILE to the victim's default npc faction
	_victim = _spawn_entity("Victim", Color(0.95, 0.45, 0.45), _BALANCED_CORE)


func _make_node(color: Color, str_mod: float = 0.0) -> SkillNode:
	var node: SkillNode = _SKILL_NODE_SCENE.instantiate()
	node.base_type_color = color.darkened(0.3)
	if str_mod > 0.0:
		var m := StatModifier.new()
		m.stat_id = &"strength"
		m.operation = StatModifier.Operation.ADD_BASE
		m.value = str_mod
		var mods: Array[StatModifier] = [m]
		node.modifiers = mods
	graph.add_skill_node(node)
	return node


## `core_class` must be set BEFORE `add_child` — Entity._ready applies it.
func _spawn_entity(ent_name: String, color: Color, core: CoreClass = null) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.color = color
	e.stat_board = _DEFAULT_BOARD.duplicate(true) as EntityStatBoard
	if core != null:
		e.core_class = core
	graph.entities_container.add_child(e)
	return e


# --- World layout ------------------------------------------------------------

## Attacker left strip / victim right pair, against the viewport's live size
## (SubViewportContainer stretch=true → viewport pixels ARE panel pixels).
func _layout_world() -> void:
	var size := _world.size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var mid_y := size.y * 0.5
	_attacker_core.position = Vector2(size.x * 0.32, mid_y)
	_victim_core.position = Vector2(size.x * 0.62, mid_y)
	_victim_nodes[0].position = Vector2(size.x * 0.68, mid_y - 90.0)
	_victim_nodes[1].position = Vector2(size.x * 0.68, mid_y + 90.0)
	for e in graph.get_edges():
		e.refresh_endpoints()


# --- Phase selection ----------------------------------------------------------

## Apply the phase's reward kill-switches (the showcase's per-side-effect
## modularity hook, demonstrated live). Public so a driver (test / option
## signal) can select a phase programmatically.
func select_phase(index: int) -> void:
	_phase_option.select(clampi(index, 0, _phases.size() - 1))
	_apply_phase(clampi(index, 0, _phases.size() - 1))


func _apply_phase(index: int) -> void:
	var phase: Dictionary = _phases[clampi(index, 0, _phases.size() - 1)]
	_loot.award_xp_on_kill = phase["xp"]
	_loot.drop_skill_dust_on_death = phase["dust"]
	_refresh_labels()


func _phase_desc(index: int) -> String:
	return _phases[clampi(index, 0, _phases.size() - 1)]["desc"]


# --- Beats (explicit triggers — nothing auto-runs) ----------------------------

## The kill — the whole point. Attacker holds the turn → it's the attributed
## killer; the write to `current_entity` is attribution-only, the TurnManager
## is never ticked (editor guardrail). Lethal hit overflows the core's combat
## HP into the health pool → 0 → die() → loot resolves synchronously.
func kill_victim() -> void:
	if _busy or _attacker == null or _victim == null or _victim.is_dead:
		return
	_tm.current_entity = _attacker
	_victim.stat_board.health.set_current(1.0)
	_victim_core.take_damage(10000.0, null)
	_refresh_labels()


## Re-arm both entities to a clean pre-kill state (real primitives, muted VFX).
## Async: the queued dust frees must land BEFORE we re-own the core — a live
## SkillDustAddon would otherwise catch the re-own as a pickup and pour its
## payload onto the resurrected victim (queue_free is deferred). This race is
## unique to a sandbox reusing a relic core; the game never re-owns one.
func reset_world() -> void:
	if _busy:
		return
	_busy = true
	_set_controls_enabled(false)
	_vfx.muted = true

	_teardown_world()
	await get_tree().process_frame
	_rearm_world()

	_vfx.muted = false
	_busy = false
	_set_controls_enabled(true)
	_refresh_labels()


## Strip ownership + clear any relic the last kill dropped.
func _teardown_world() -> void:
	for n in _all_nodes():
		if n.owned_by != null:
			_alloc.force_deallocate(n)
		_clear_dust(n)


## Reset boards + re-establish ownership: attacker owns its core; victim owns
## core + nodes.
func _rearm_world() -> void:
	_reset_board(_attacker)
	_reset_board(_victim)
	_attacker.level = 1
	_victim.level = victim_level

	_alloc.force_allocate(_attacker, _attacker_core)
	_attacker.core_location = _attacker_core
	_alloc.force_allocate(_victim, _victim_core)
	for n in _victim_nodes:
		_alloc.force_allocate(_victim, n)
	_victim.core_location = _victim_core

	_tm.current_entity = null    # attribution slot: clean between kills


# --- Helpers -----------------------------------------------------------------

func _all_nodes() -> Array[SkillNode]:
	var out: Array[SkillNode] = [_attacker_core, _victim_core]
	out.append_array(_victim_nodes)
	return out


func _clear_dust(node: SkillNode) -> void:
	for a in node.get_addons():
		if a is SkillDustAddon:
			a.queue_free()


func _reset_board(e: Entity) -> void:
	var b := e.stat_board
	if b == null:
		return
	if b.skill_points != null:
		b.skill_points.wounded = 0
		b.skill_points.staked = 0
		b.skill_points.base_value = 20.0
		b.skill_points.set_current(20.0)
	if b.health != null:
		b.health.restore_to_full()
	if b.xp != null:
		b.xp.set_current(0.0)
	e.is_dead = false


func _refresh_labels() -> void:
	if _attacker == null or _victim == null:
		return
	var ab := _attacker.stat_board
	var vb := _victim.stat_board
	_stat_label.text = "Lvl %d  XP %d/%d   |   Victim  STR %d  %s   ·   %s" % [
		_attacker.level,
		int(ab.xp.current), int(ab.xp.value),
		int(vb.get_value(&"strength")),
		"DEAD" if _victim.is_dead else "alive",
		_phase_desc(_phase_option.selected),
	]


func _set_controls_enabled(enabled: bool) -> void:
	_kill_button.disabled = not enabled
	_reset_button.disabled = not enabled

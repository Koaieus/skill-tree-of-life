extends Node2D

## LootSystem showcase (#68 XP + #69 SkillDust) — a played sandbox that drives a
## real kill on a loop and shows the rewards land: an XP floater climbing on the
## killer, a SkillDust relic blooming on the victim's former core, and the death
## cascade. Three sequential phases demonstrate the per-side-effect kill-switches
## (`LootSystem.award_xp_on_kill` / `drop_skill_dust_on_death`) — the sandbox
## modularity hook — by toggling one reward off at a time.
##
## Why sequential (not a parallel grid like the allocation showcase): LootSystem,
## AllocationSystem and BattleSystem are singletons — they listen on the global
## `Events` bus — and killer attribution reads `TurnManager.current_entity` at the
## synchronous death. Two simultaneous kills would race that single slot, so kills
## must be one-at-a-time. Each phase is its own SETUP (silent, muted) → PLAY beat.
##
## Systems are composed + wired in code exactly as GameRoot does — a DIFFERENT
## subset than the allocation showcase (this one needs TurnManager + LootSystem),
## which is what makes the two a real rule-of-three case for a shared scaffold.

const _SKILL_NODE_SCENE: PackedScene = preload("res://skill_node/skill_node.tscn")
const _ALLOCATION_SYSTEM_SCRIPT: Script = preload("res://systems/allocation_system.gd")
const _BATTLE_SYSTEM_SCRIPT: Script = preload("res://systems/battle_system.gd")
const _LOOT_SYSTEM_SCRIPT: Script = preload("res://systems/loot_system.gd")
const _ALLOC_VFX_SCRIPT: Script = preload("res://ui/vfx/allocation_vfx.gd")
const _FLOATER_LAYER_SCRIPT: Script = preload("res://ui/floating_number_layer/floating_number_layer.gd")
const _DEFAULT_BOARD: Resource = preload("res://entity/default_entity_board.tres")

@export var setup_hold: float = 1.0
@export var play_hold: float = 3.4
@export var victim_level: int = 3       ## scales XP award + dust payload size
@export var str_per_node: float = 6.0

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _loot: LootSystem
var _tm: TurnManager
var _vfx: AllocationVFX
var _floaters: FloatingNumberLayer

var _attacker: Entity
var _victim: Entity
var _attacker_core: SkillNode
var _victim_core: SkillNode
var _victim_nodes: Array[SkillNode] = []

var _phase_label: Label
var _stat_label: Label

# Phase table: which reward(s) are live this phase.
var _phases := [
	{"xp": true,  "dust": true,  "desc": "full rewards — XP floater + SkillDust relic"},
	{"xp": true,  "dust": false, "desc": "drop_skill_dust_on_death = false — XP only"},
	{"xp": false, "dust": true,  "desc": "award_xp_on_kill = false — relic only"},
]


func _ready() -> void:
	_graph = $Graph
	_build_systems()
	_build_world()
	_build_camera()
	_build_labels()
	_run_loop()


func _build_systems() -> void:
	_alloc = _ALLOCATION_SYSTEM_SCRIPT.new()
	_alloc.name = "AllocationSystem"
	_alloc.graph = _graph
	_alloc.navigator = _graph.get_node("Navigator")
	add_child(_alloc)

	_tm = TurnManager.new()
	_tm.name = "TurnManager"
	add_child(_tm)

	_battle = _BATTLE_SYSTEM_SCRIPT.new()
	_battle.name = "BattleSystem"
	_battle.allocation_system = _alloc
	_battle.graph = _graph
	_battle.turn_manager = _tm
	add_child(_battle)

	_loot = _LOOT_SYSTEM_SCRIPT.new()
	_loot.name = "LootSystem"
	_loot.turn_manager = _tm
	# Sub-cap award (xp cap is 5): keeps the kill XP observable as a delta without
	# triggering a level-up, which would grow the xp cap + mint SP permanently and
	# make the per-phase reset drift. The showcase is about loot landing, not levels.
	_loot.xp_per_victim_level = 1.0
	add_child(_loot)

	_vfx = _ALLOC_VFX_SCRIPT.new()
	_vfx.name = "AllocationVFX"
	_graph.add_child(_vfx)
	_vfx.bind(_alloc, _battle)

	_floaters = _FLOATER_LAYER_SCRIPT.new()
	_floaters.name = "FloatingNumberLayer"
	_floaters.vision_system = null
	_graph.add_child(_floaters)


## Attacker (left) + victim (right). The victim carries a core class + STR-bearing
## nodes so the dust payload is non-empty and its STR is worth watching. No edge
## between the two — the kill is direct `take_damage`, not a graph attack.
func _build_world() -> void:
	_attacker_core = _make_node(Vector2(-160, 0), Color(0.40, 0.80, 1.00))
	_victim_core = _make_node(Vector2(220, 0), Color(0.95, 0.45, 0.45), str_per_node)
	_victim_nodes = [
		_make_node(Vector2(320, -70), Color(0.95, 0.45, 0.45), str_per_node),
		_make_node(Vector2(320, 70), Color(0.95, 0.45, 0.45), str_per_node),
	]
	_graph.add_edge(_victim_core, _victim_nodes[0])
	_graph.add_edge(_victim_core, _victim_nodes[1])

	_attacker = _spawn_entity("Attacker", Color(0.40, 0.80, 1.00))
	# Victim's dust payload (size = level) is filled from its core + node STR mods
	# — no core_class needed (and Entity._ready already passed, so assigning one
	# here wouldn't apply anyway).
	_victim = _spawn_entity("Victim", Color(0.95, 0.45, 0.45))


func _make_node(pos: Vector2, color: Color, str_mod: float = 0.0) -> SkillNode:
	var node: SkillNode = _SKILL_NODE_SCENE.instantiate()
	node.position = pos
	node.base_type_color = color.darkened(0.3)
	if str_mod > 0.0:
		var m := StatModifier.new()
		m.stat_id = &"strength"
		m.operation = StatModifier.Operation.ADD_BASE
		m.value = str_mod
		var mods: Array[StatModifier] = [m]
		node.modifiers = mods
	_graph.add_skill_node(node)
	return node


func _spawn_entity(ent_name: String, color: Color) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.color = color
	e.stat_board = _DEFAULT_BOARD.duplicate(true) as StatBoard
	_graph.entities_container.add_child(e)
	return e


func _build_camera() -> void:
	var cam := $Camera2D as Camera2D
	if cam == null:
		return
	cam.position = Vector2(80, 0)
	cam.zoom = Vector2(1.1, 1.1)
	cam.make_current()


func _build_labels() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_phase_label = Label.new()
	_phase_label.position = Vector2(24, 16)
	_phase_label.add_theme_font_size_override("font_size", 20)
	layer.add_child(_phase_label)
	_stat_label = Label.new()
	_stat_label.position = Vector2(24, 52)
	_stat_label.add_theme_font_size_override("font_size", 15)
	layer.add_child(_stat_label)


# --- Beat loop ---------------------------------------------------------------

func _run_loop() -> void:
	while is_inside_tree():
		for i in _phases.size():
			var phase: Dictionary = _phases[i]
			_loot.award_xp_on_kill = phase["xp"]
			_loot.drop_skill_dust_on_death = phase["dust"]

			_vfx.muted = true
			await _reset()
			_vfx.muted = false
			_phase_label.text = "SETUP  ·  %d/3" % (i + 1)
			await _sleep(setup_hold)

			_phase_label.text = "PLAY  ·  %d/3  —  %s" % [i + 1, phase["desc"]]
			_kill_victim()
			await _sleep(play_hold)


## Re-arm both entities to a clean pre-kill state (real primitives, muted VFX).
func _reset() -> void:
	# Strip everything both entities own + clear any relic the last kill dropped.
	for n in _all_nodes():
		if n.owned_by != null:
			_alloc.force_deallocate(n)
		_clear_dust(n)
	# Let the queued dust free actually happen BEFORE we re-own the core below:
	# a live SkillDustAddon would otherwise catch the re-own as a pickup and pour
	# its payload onto the resurrected victim (queue_free is deferred). This race
	# is unique to the showcase reusing a relic core; the game never re-owns one.
	await get_tree().process_frame
	_reset_board(_attacker)
	_reset_board(_victim)
	_attacker.level = 1
	_victim.level = victim_level

	# Re-establish ownership: attacker owns its core; victim owns core + nodes.
	_alloc.force_allocate(_attacker, _attacker_core)
	_attacker.core_location = _attacker_core
	_alloc.force_allocate(_victim, _victim_core)
	for n in _victim_nodes:
		_alloc.force_allocate(_victim, n)
	_victim.core_location = _victim_core


func _kill_victim() -> void:
	# Attacker holds the turn → it's the attributed killer. Lethal hit overflows
	# the core's combat HP into the health pool → 0 → die() → loot resolves.
	_tm.current_entity = _attacker
	_victim.stat_board.health.set_current(1.0)
	_victim_core.take_damage(10000.0, null)


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


func _process(_dt: float) -> void:
	if _attacker == null or _victim == null:
		return
	var ab := _attacker.stat_board
	var vb := _victim.stat_board
	_stat_label.text = "Attacker  Lvl %d  XP %d/%d   |   Victim  STR %d  %s" % [
		_attacker.level,
		int(ab.xp.current), int(ab.xp.value),
		int(vb.get_value(&"strength")),
		"DEAD" if _victim.is_dead else "alive",
	]


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

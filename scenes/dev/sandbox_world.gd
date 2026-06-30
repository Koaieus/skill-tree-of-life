extends Node

## Anti-drift scaffold for **played** sandboxes (see docs/domain/sandbox-framework.md).
## Composes + wires a chosen SUBSET of the real gameplay systems against a graph,
## using the SAME calls GameRoot._ready uses, so a sandbox can't quietly diverge
## from how the game wires these systems.
##
## This is deliberately a code helper, NOT a `systems.tscn` extraction: the level
## scenes inherit game_root.tscn and override Systems children by path, so
## extracting that subtree would break their fog/input wiring (the doc has the
## full evidence). A code helper mirrors GameRoot's wiring without touching the
## central scene. The tradeoff: it's a parallel wiring source — **keep it in sync
## with game_root.tscn** if a system gains a required dependency.
##
## No class_name on purpose: keeps it off the global class cache (no editor
## refresh / scene-mutation risk), and consumers preload + duck-type it.
##
## Usage:
##   var world = preload(".../sandbox_world.gd").new()
##   add_child(world)                 # must be in-tree before build() add_childs
##   world.build($Graph, {loot = true})
##   _alloc = world.allocation_system  # ... etc

const _ALLOCATION_SYSTEM_SCRIPT: Script = preload("res://systems/allocation_system.gd")
const _BATTLE_SYSTEM_SCRIPT: Script = preload("res://systems/battle_system.gd")
const _LOOT_SYSTEM_SCRIPT: Script = preload("res://systems/loot_system.gd")
const _ALLOC_VFX_SCRIPT: Script = preload("res://ui/vfx/allocation_vfx.gd")
const _FLOATER_DIRECTOR_SCENE: PackedScene = preload("res://ui/floating_number_layer/floater_director.tscn")

# Always built.
var graph: Graph
var allocation_system: AllocationSystem
var battle_system: BattleSystem
var allocation_vfx: AllocationVFX
var floater_director: FloaterDirector
## Convenience handle to the director's renderer (used by showcases).
var floating_number_layer: FloaterToasterManager
# Opt-in (null unless requested via opts).
var turn_manager: TurnManager
var loot_system: LootSystem


## Compose against [param p_graph]. `opts` keys (all default false):
##   turn_manager — add a TurnManager (also implied by `loot`)
##   loot         — add a LootSystem (needs a TurnManager for killer attribution)
func build(p_graph: Graph, opts: Dictionary = {}) -> void:
	graph = p_graph
	var want_tm: bool = bool(opts.get("turn_manager", false)) or bool(opts.get("loot", false))
	var want_loot: bool = bool(opts.get("loot", false))

	allocation_system = _ALLOCATION_SYSTEM_SCRIPT.new()
	allocation_system.name = "AllocationSystem"
	allocation_system.graph = graph
	allocation_system.navigator = graph.get_node("Navigator")
	add_child(allocation_system)

	if want_tm:
		turn_manager = TurnManager.new()
		turn_manager.name = "TurnManager"
		add_child(turn_manager)

	# BattleSystem: allocation_system + graph mirror game_root.tscn; turn_manager
	# is null when not requested (only launch_attack reads it, which sandboxes
	# that skip the turn loop don't call — the forced-dealloc cascade doesn't).
	battle_system = _BATTLE_SYSTEM_SCRIPT.new()
	battle_system.name = "BattleSystem"
	battle_system.allocation_system = allocation_system
	battle_system.graph = graph
	battle_system.turn_manager = turn_manager
	add_child(battle_system)

	if want_loot:
		loot_system = _LOOT_SYSTEM_SCRIPT.new()
		loot_system.name = "LootSystem"
		loot_system.turn_manager = turn_manager
		add_child(loot_system)

	# VFX + floaters live under the graph so world coords line up (game_root.tscn
	# parents them under Graph too). Floaters run unfiltered — no fog in a sandbox,
	# so the director's vision_system stays null.
	allocation_vfx = _ALLOC_VFX_SCRIPT.new()
	allocation_vfx.name = "AllocationVFX"
	graph.add_child(allocation_vfx)
	allocation_vfx.bind(allocation_system, battle_system)

	floater_director = _FLOATER_DIRECTOR_SCENE.instantiate()
	floater_director.name = "FloaterDirector"
	floater_director.vision_system = null
	graph.add_child(floater_director)
	floating_number_layer = floater_director.renderer

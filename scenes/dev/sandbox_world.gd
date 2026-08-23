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
const _COMMAND_APPLIER_SCRIPT: Script = preload("res://command/command_applier.gd")
const _INPUT_CONTROLLER_SCRIPT: Script = preload("res://systems/player_input_controller.gd")
const _MELEE_PREVIEW_SCRIPT: Script = preload("res://attack/melee/melee_preview.gd")
const _ATTACK_VFX_SCRIPT: Script = preload("res://ui/vfx/attack_vfx.gd")
const _ALLOC_VFX_SCRIPT: Script = preload("res://ui/vfx/allocation_vfx.gd")
const _HIGHLIGHT_CONTROLLER_SCRIPT: Script = preload("res://systems/highlight_controller.gd")
const _NODE_HIGHLIGHT_SCRIPT: Script = preload("res://ui/node_highlight_overlay/node_highlight_overlay.gd")
const _EDGE_HIGHLIGHT_SCRIPT: Script = preload("res://ui/edge_highlight_overlay/edge_highlight_overlay.gd")
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
var command_applier: CommandApplier
var input_controller: PlayerInputController
var melee_preview: MeleePreview
var attack_vfx: AttackVFX
var highlight_controller: HighlightController
var node_highlight: NodeHighlightOverlay
var edge_highlight: EdgeHighlightOverlay


## Compose against [param p_graph]. `opts` keys (all default false):
##   turn_manager — add a TurnManager (also implied by `loot` / `input`)
##   loot         — add a LootSystem (needs a TurnManager for killer attribution)
##   commands     — add a CommandApplier (also implied by `input`)
##   input        — add a PlayerInputController (implies `commands` + `turn_manager`;
##                  the caller still has to hand it a `player`)
##   melee        — mount a MeleePreview under the graph and hand it to the
##                  BattleSystem, which is what makes a swing DRAW at all
##   attack_vfx   — mount an AttackVFX under the graph, which is what makes a
##                  ranged volley / spell DRAW at all (melee's counterpart is
##                  `melee`; BattleSystem picks between the two per plan)
##   highlight    — mount the HighlightController + both highlight overlays, which
##                  is what makes TARGETING visible: origin / in-range / committed
##                  rings and the range finder's reach. Without it a tab's plan is
##                  armed and unreadable — the state is all there and nothing says
##                  so. Plan-driven only in the editor (see
##                  [method HighlightController._live_input_ctl]).
func build(p_graph: Graph, opts: Dictionary = {}) -> void:
	graph = p_graph
	var want_input: bool = bool(opts.get("input", false))
	var want_commands: bool = bool(opts.get("commands", false)) or want_input
	var want_tm: bool = bool(opts.get("turn_manager", false)) \
			or bool(opts.get("loot", false)) or want_input
	var want_loot: bool = bool(opts.get("loot", false))
	var want_melee: bool = bool(opts.get("melee", false))
	var want_attack_vfx: bool = bool(opts.get("attack_vfx", false))
	var want_highlight: bool = bool(opts.get("highlight", false))

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

	if want_melee:
		# Under the graph so blade coordinates line up with node positions, and
		# handed to the BattleSystem BEFORE entering the tree: MeleePreview is
		# `@tool`, so its `_ready` subscribes the moment it is added.
		melee_preview = _MELEE_PREVIEW_SCRIPT.new()
		melee_preview.name = "MeleePreview"
		melee_preview.battle_system = battle_system
		graph.add_child(melee_preview)
		battle_system.melee_preview = melee_preview

	if want_attack_vfx:
		# Under the graph, like game_root.tscn — every coordinator it spawns is a
		# world-space child and has to share coordinates with the SkillNodes it
		# targets.
		attack_vfx = _ATTACK_VFX_SCRIPT.new()
		attack_vfx.name = "AttackVFX"
		graph.add_child(attack_vfx)
		battle_system.attack_vfx = attack_vfx

	if want_commands:
		command_applier = _COMMAND_APPLIER_SCRIPT.new()
		command_applier.name = "CommandApplier"
		command_applier.graph = graph
		command_applier.allocation_system = allocation_system
		command_applier.battle_system = battle_system
		command_applier.turn_manager = turn_manager
		# Registers itself on the BattleSystem in its own `_ready` — the
		# applier that calls back and the one submitted to are one object.
		add_child(command_applier)

	if want_input:
		input_controller = _INPUT_CONTROLLER_SCRIPT.new()
		input_controller.name = "PlayerInputController"
		input_controller.graph = graph
		input_controller.allocation_system = allocation_system
		input_controller.battle_system = battle_system
		input_controller.turn_manager = turn_manager
		input_controller.command_applier = command_applier
		add_child(input_controller)

	if want_highlight:
		# After the input controller on purpose: the controller resolves its
		# provider in `_ready`, and core-move / manage highlights need that dep
		# present by then. The overlays go under the graph for world coordinates,
		# edge below node so status rings paint on top of reach edges —
		# game_root.tscn's order. They land ABOVE the VFX nodes here rather than
		# below (the one z-order divergence from that scene): reach rings over a
		# projectile read fine, and hoisting them would mean index juggling.
		highlight_controller = _HIGHLIGHT_CONTROLLER_SCRIPT.new()
		highlight_controller.name = "HighlightController"
		highlight_controller.graph = graph
		highlight_controller.battle_system = battle_system
		highlight_controller.allocation_system = allocation_system
		highlight_controller.turn_manager = turn_manager
		highlight_controller.input_ctl = input_controller
		add_child(highlight_controller)
		edge_highlight = _EDGE_HIGHLIGHT_SCRIPT.new()
		edge_highlight.name = "EdgeHighlightOverlay"
		edge_highlight.highlight_controller = highlight_controller
		edge_highlight.graph = graph
		graph.add_child(edge_highlight)
		node_highlight = _NODE_HIGHLIGHT_SCRIPT.new()
		node_highlight.name = "NodeHighlightOverlay"
		node_highlight.highlight_controller = highlight_controller
		node_highlight.graph = graph
		graph.add_child(node_highlight)

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

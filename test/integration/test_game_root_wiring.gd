extends GutTest
## The wiring smoke for `scenes/game_root.tscn` (#360): the seams that
## `GameRoot._ready` / `HudRoot.compose` establish are otherwise asserted once,
## for one system pair, and every unit test drives the handlers by name
## (`_on_turn_started(...)`) without ever asserting the `connect` behind them.
##
## Two halves, deliberately separate:
##  1. scene-time `@export` NodePaths — `instantiate()` WITHOUT `add_child`
##     resolves them without paying a level's `_ready` (see
##     `.claude/rules/testing.md`: discard with `queue_free()`, never `free()`);
##  2. `_ready`/compose-time signal connections — the level in the tree for
##     one frame, turn loop and run-end routing vetoed.
##
## Both lists are explicit — one named assert per (node, dep) / (signal,
## handler) — so a red line names the exact seam. A third test walks the scene
## by reflection to prove the first list is complete against the `.tscn`.

const _GAME_ROOT := preload("res://scenes/game_root.tscn")

## (scene path relative to the root, `@export` property) — every `node_paths`
## entry authored in `game_root.tscn`, in file order.
const _EXPORT_DEPS: Array = [
	["Systems/AllocationSystem", "graph"],
	["Systems/AllocationSystem", "navigator"],
	["Systems/AllocationSystem", "turn_manager"],
	["Systems/BattleSystem", "turn_manager"],
	["Systems/BattleSystem", "allocation_system"],
	["Systems/BattleSystem", "graph"],
	["Systems/BattleSystem", "attack_vfx"],
	["Systems/BattleSystem", "melee_preview"],
	["Systems/BattleSystem", "vision_system"],
	["Systems/HighlightController", "battle_system"],
	["Systems/HighlightController", "input_ctl"],
	["Systems/HighlightController", "allocation_system"],
	["Systems/HighlightController", "graph"],
	["Systems/HighlightController", "turn_manager"],
	["Systems/LootSystem", "turn_manager"],
	["Systems/LootSystem", "battle_system"],
	["Systems/LootSystem", "command_applier"],
	["Systems/LootSystem", "pick_registry"],
	["Systems/LootSystem", "command_link"],
	["Systems/CommandApplier", "graph"],
	["Systems/CommandApplier", "allocation_system"],
	["Systems/CommandApplier", "battle_system"],
	["Systems/CommandApplier", "turn_manager"],
	["Systems/CommandApplier", "loot_pick_registry"],
	["Systems/PlayerInputController", "graph"],
	["Systems/PlayerInputController", "allocation_system"],
	["Systems/PlayerInputController", "battle_system"],
	["Systems/PlayerInputController", "turn_manager"],
	["Systems/PlayerInputController", "command_applier"],
	["Systems/VisionSystem", "graph"],
	["Systems/VisionSystem", "allocation_system"],
	["Systems/VictorySystem", "graph"],
	["Systems/VictorySystem", "turn_manager"],
	["Systems/CameraDirector", "camera"],
	["Systems/CameraDirector", "vision_system"],
	["Systems/CameraDirector", "battle_system"],
	["Systems/CameraDirector", "command_applier"],
	["Systems/CameraDirector", "graph"],
	["Graph/FogOverlay", "vision_system"],
	["Graph/AuraOverlay", "graph"],
	["Graph/AuraOverlay", "allocation_system"],
	["Graph/FloaterDirector", "vision_system"],
	["Graph/EdgeHighlightOverlay", "highlight_controller"],
	["Graph/EdgeHighlightOverlay", "graph"],
	["Graph/NodeHighlightOverlay", "highlight_controller"],
	["Graph/NodeHighlightOverlay", "graph"],
	["Graph/AllocationVFX", "allocation_system"],
	["Graph/AllocationVFX", "battle_system"],
	["Graph/MeleePreview", "battle_system"],
	["CommandLink", "transport"],
	["CommandLink", "command_applier"],
	["CommandLink", "graph"],
	["CommandLink", "turn_manager"],
	["CommandLink", "loot_pick_registry"],
]


## Deferred to the tree's own delete flush — an immediate `free()` on a
## level-sized un-parented instance poisons every later script in the run
## (`test_link_mount.gd::_discard` has the measurements).
func _discard(root: Node) -> void:
	root.queue_free()


func test_every_scene_authored_export_dep_resolves() -> void:
	var root: Node = _GAME_ROOT.instantiate()
	for pair: Array in _EXPORT_DEPS:
		var node := root.get_node_or_null(pair[0] as String)
		assert_not_null(node, "%s exists in game_root.tscn" % pair[0])
		if node == null:
			continue
		assert_not_null(node.get(pair[1]),
				"%s.%s resolves from its NodePath" % [pair[0], pair[1]])
	_discard(root)


## The explicit list above is the spec; this proves it is COMPLETE against the
## scene file. Every `NodePath`-valued property `game_root.tscn` authors (its
## `node_paths=PackedStringArray(...)` entries, read back through the packed
## scene's [SceneState]) must appear in `_EXPORT_DEPS`, and nothing else may —
## a new `@export var x: Foo` wired in the scene fails here until it is listed
## (and so asserted) above. Runtime-bound exports the scene leaves blank
## (`PlayerInputController.player`, set by `bind_player`) are not seams of the
## scene and do not appear on either side.
func test_export_dep_list_matches_the_scene_by_reflection() -> void:
	var listed: Array[String] = []
	for pair: Array in _EXPORT_DEPS:
		listed.append("%s.%s" % [pair[0], pair[1]])
	var found: Array[String] = []
	var state: SceneState = _GAME_ROOT.get_state()
	for i: int in state.get_node_count():
		var path := str(state.get_node_path(i))
		for j: int in state.get_node_property_count(i):
			if state.get_node_property_value(i, j) is NodePath:
				found.append("%s.%s" % [path.trim_prefix("./"), state.get_node_property_name(i, j)])
	for key: String in found:
		assert_true(listed.has(key), "%s is a NodePath the scene authors — list it in _EXPORT_DEPS" % key)
	for key: String in listed:
		assert_true(found.has(key), "%s is listed but game_root.tscn authors no such NodePath" % key)
	assert_eq(found.size(), _EXPORT_DEPS.size(), "same number of (node, dep) seams found as listed")


## (emitter, signal, listener, handler) — the `.connect` calls in
## `GameRoot._ready`, `HudRoot._ready` / `bind_systems` / `_bind_turn_signals`,
## and the cross-system hookups each system makes in its own `_ready` from the
## deps the scene gave it. Only plain handler connections are listed: a
## `.unbind(n)` / `.bind(x)` connection is a distinct Callable that
## `is_connected(handler)` cannot see.
func test_ready_and_compose_connect_every_cross_system_signal() -> void:
	var root: GameRoot = _GAME_ROOT.instantiate()
	root.auto_start_turn = false
	root.route_to_meta_on_run_end = false
	add_child_autofree(root)
	await get_tree().process_frame
	var hud: HudRoot = root.hud_root
	var loot: LootSystem = root.get_node("%LootSystem")
	var pairs: Array = [
		# GameRoot._ready
		[root.command_link, "resync_applied", root, "_on_resync_applied"],
		[root.command_link, "link_refused", root, "_on_refused_by_host"],
		[root.command_link, "seat_handover_received", root, "_on_seat_handover"],
		[Events, "entity_died", root, "_on_entity_died"],
		[Events, "entity_death_shown", root, "_on_entity_death_shown"],
		[Events, "run_ended", root, "_on_run_ended"],
		[root.turn_manager, "turn_started", root, "_on_turn_started_for_handover"],
		# HudRoot._ready
		[Events, "loot_pick_requested", hud, "_on_loot_pick_requested"],
		[Events, "spell_loot_requested", hud, "_on_spell_loot_requested"],
		[Events, "run_ended", hud, "_on_run_ended"],
		[hud.run_end_overlay, "main_menu_pressed", hud, "_on_run_end_main_menu_pressed"],
		[hud.loot_picker, "closed", hud, "_on_modal_closed"],
		[hud.spell_loot_picker, "closed", hud, "_on_modal_closed"],
		[hud.mass_action_confirm_panel, "closed", hud, "_on_modal_closed"],
		[hud.spell_catalogue_modal, "closed", hud, "_on_modal_closed"],
		[hud.pause_menu, "spell_catalogue_requested", hud, "_on_spell_catalogue_requested"],
		# HudRoot.bind_systems / _bind_turn_signals (via compose)
		[root.input_ctl, "mass_action_pending_changed", hud, "_on_mass_action_pending_changed"],
		[hud.xp_track, "level_display_changed", hud.hero_sigil_card, "show_level"],
		[root.turn_manager, "turn_started", hud, "_on_turn_started_for_banner"],
		[root.turn_manager, "turn_started", hud, "_on_turn_started_for_initiative"],
		[root.turn_manager, "turn_ended", hud, "_on_turn_ended_for_initiative"],
		# systems wiring themselves to the deps the scene handed them
		[root.battle_system, "attack_launched", loot, "_on_attack_launched"],
		[root.battle_system, "cascade_started", loot, "_on_cascade_started"],
		[root.command_applier, "command_applied", loot, "_on_command_applied"],
		[root.command_link, "loot_offer_received", loot, "_on_loot_offer_received"],
		[Events, "entity_dying", loot, "_on_entity_dying"],
		[Events, "entity_died", root.allocation_system, "_on_entity_died"],
		[Events, "entity_death_shown", root.victory_system, "_on_entity_death_shown"],
		[Events, "skill_node_depleted", root.battle_system, "_on_node_depleted"],
		[Events, "entity_dying", root.battle_system, "_on_entity_dying"],
	]
	for p: Array in pairs:
		var emitter: Object = p[0]
		var listener: Object = p[2]
		var label := "%s.%s -> %s.%s" % [_name_of(emitter), p[1], _name_of(listener), p[3]]
		assert_not_null(emitter, "emitter present: " + label)
		assert_not_null(listener, "listener present: " + label)
		if emitter == null or listener == null:
			continue
		assert_true(emitter.is_connected(p[1] as StringName, Callable(listener, p[3] as StringName)),
				"connected after _ready + compose: " + label)


func _name_of(o: Object) -> String:
	if o == null:
		return "<null>"
	if o is Node:
		return (o as Node).name
	return str(o)

extends GutTest

## Acceptance for #478 — the removable-blocker boulder overlay ([BlockerVisual],
## `skill_node/visuals/blocker_visual.gd`) and its home scene
## (`skill_node/blocker_node.tscn`). Covers: the scene is a real [SkillNode];
## a blocked node's live CoreHalos ends up at COG (the cheap preset, #478 perf
## amendment) rather than GIMBAL, and restores to GIMBAL once cleared; crack
## stage tracks HP synchronously off `damaged` OFF-hold, and honours the
## presentation hold (#479/#482) — withheld while held, one collapsed re-sync
## on release, never a mid-hold advance; the core HP bar keeps its ordinary
## visibility rule untouched by the boulder; clearing (owner stripped) hides
## the boulder PERMANENTLY — a later re-allocation by a normal entity must
## never re-show it; and procgen instantiates the blocker scene for exactly
## the nodes it places blockers on.

const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BLOCKER_NODE_SCENE := preload("res://skill_node/blocker_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _SMALL_BOARD := preload("res://entity/blocker/blocker_small_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _nodes: Array[SkillNode] = []


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = []
	for i in 2:
		var sn := _BLOCKER_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	_add_edge(_nodes[0], _nodes[1])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	await get_tree().process_frame  # _ready: navigators + health wiring


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


## Build a blocker owning `_nodes[0]` directly (not via GameRoot.spawn_blocker)
## — mirrors `test_blocker_entity.gd`'s fixture pattern.
func _spawn_blocker() -> Entity:
	var blocker := Entity.new()
	blocker.display_name = "Blocker"
	blocker.stat_board = _SMALL_BOARD.duplicate(true) as EntityStatBoard
	blocker.entity_tier = 1
	_graph.add_child(blocker)
	await get_tree().process_frame  # _ready: board dup + intrinsics + health wiring
	_alloc.force_allocate(blocker, _nodes[0])
	blocker.core_location = _nodes[0]
	return blocker


func _spawn_normal_entity() -> Entity:
	var ent := Entity.new()
	ent.display_name = "Player"
	ent.faction = _PLAYER_FACTION
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(ent)
	await get_tree().process_frame
	return ent


func _visual(sn: SkillNode) -> Node2D:
	return sn.get_node("Visuals/BlockerVisual") as Node2D


# ── Scene identity ────────────────────────────────────────────────────────

func test_blocker_node_scene_is_a_skill_node() -> void:
	var sn := _nodes[0]
	assert_true(sn is SkillNode, "blocker_node.tscn's root must be a SkillNode")
	assert_not_null(_visual(sn), "expected a BlockerVisual under Visuals")


# ── Crack stage follows HP synchronously ─────────────────────────────────

func test_crack_stage_follows_hp_on_damaged() -> void:
	var sn := _nodes[0]
	var visual := _visual(sn)
	await _spawn_blocker()
	await get_tree().process_frame

	var max_hp := sn.get_max_hp()
	assert_gt(max_hp, 0.0, "blocker board must give the node combat HP")
	assert_eq(visual.crack_stage, 0, "full HP → INTACT")

	# Down to 60% (≤ 66%) → CRACKED, synchronously off the `damaged` signal.
	sn.take_damage(max_hp * 0.40, null)
	assert_eq(visual.crack_stage, 1, "60% HP → CRACKED")

	# Down to 20% (≤ 33%) → SHATTERED.
	sn.take_damage(max_hp * 0.40, null)
	assert_eq(visual.crack_stage, 2, "20% HP → SHATTERED")


# ── Crack stage honours the presentation hold (#479/#482) ────────────────

## Crack stage is combat paint: a hit that lands under a presentation hold
## must not visibly crack the boulder before the projectile/swing arrives.
func test_crack_stage_withheld_under_presentation_hold_then_syncs_on_release() -> void:
	var sn := _nodes[0]
	var visual := _visual(sn)
	await _spawn_blocker()
	await get_tree().process_frame

	var max_hp := sn.get_max_hp()
	sn.hold_presentation()
	sn.take_damage(max_hp * 0.80, null)  # would be SHATTERED off-hold
	assert_eq(visual.crack_stage, 0, "held: stage does not advance on the hit itself")

	sn.release_presentation()
	assert_eq(visual.crack_stage, 2, "released: stage syncs to the FINAL hp fraction")


## A rapid multi-hit exchange under one hold must not replay each
## intermediate stage — only the one re-sync on release, against final HP.
func test_multiple_held_hits_collapse_to_one_release_sync() -> void:
	var sn := _nodes[0]
	var visual := _visual(sn)
	await _spawn_blocker()
	await get_tree().process_frame

	var max_hp := sn.get_max_hp()
	sn.hold_presentation()
	sn.take_damage(max_hp * 0.40, null)
	sn.take_damage(max_hp * 0.40, null)
	assert_eq(visual.crack_stage, 0, "held: still no advance after a second hit")

	sn.release_presentation()
	assert_eq(visual.crack_stage, 2, "released: one sync lands on the accumulated 20% hp")


# ── HP bar semantics: ASSERT ONLY, no behaviour change ───────────────────

func test_core_health_bar_visibility_untouched_by_boulder() -> void:
	var sn := _nodes[0]
	await _spawn_blocker()
	await get_tree().process_frame
	var is_core := sn.owned_by != null and sn.owned_by.core_location == sn
	assert_eq(
		sn.core_health_bar.visible, sn.revealed and is_core,
		"core HP bar keeps its ordinary revealed-and-is-core rule for a blocked node")


# ── Core presence: COG, not suppressed (#478 perf amendment) ─────────────

## GIMBAL is expensive per-instance (28-segment quaternion chain, redrawn every
## `_process` tick — see .claude/rules/skill-node-visuals.md) and a level can
## spawn several blockers, so a blocked node keeps its core presence ACTIVE
## (unlike a suppress-and-restore design) but wears the cheap COG preset
## instead. `blocker_node.tscn` pins this statically via
## [member SkillNode.core_halo_style]; a normal entity's core (a PLAIN
## skill_node.tscn — both `_nodes` fixture entries are themselves
## blocker_node.tscn instances, so this needs its own node) is untouched.
func test_blocked_node_core_halo_is_cog_not_gimbal() -> void:
	var sn := _nodes[0]
	await _spawn_blocker()
	await get_tree().process_frame
	var CoreHalosScript := preload("res://skill_node/visuals/core_halos.gd")
	var halos = sn.get_node("Visuals/NodeVisualsComposite/ShaderStack/CorePresence/CoreHalos")
	assert_eq(
		halos.halo_style, CoreHalosScript.CoreHaloStyle.COG,
		"a blocked node's core wears the cheap COG halo")
	assert_true(sn._node_visuals.core_active, "core presence stays ACTIVE, not suppressed")

	var plain := _SKILL_NODE_SCENE.instantiate() as SkillNode
	plain.name = "PlainCore"
	_graph.skill_nodes_container.add_child(plain)
	var player := await _spawn_normal_entity()
	_alloc.force_allocate(player, plain)
	player.core_location = plain
	await get_tree().process_frame
	var other_halos = plain.get_node(
		"Visuals/NodeVisualsComposite/ShaderStack/CorePresence/CoreHalos")
	assert_eq(
		other_halos.halo_style, CoreHalosScript.CoreHaloStyle.GIMBAL,
		"a normal entity's core keeps the authored GIMBAL — core_halo_style default is a no-op")


# ── Clearing is a permanent latch ─────────────────────────────────────────

func test_clearing_hides_boulder_permanently() -> void:
	var sn := _nodes[0]
	var visual := _visual(sn)
	await _spawn_blocker()
	await get_tree().process_frame
	assert_true(visual.visible, "boulder shows while blocked")

	_alloc.force_deallocate(sn)
	await get_tree().process_frame  # BlockerVisual's owner_changed handler is deferred
	assert_false(visual.visible, "boulder hides once the blocker is stripped")
	var CoreHalosScript := preload("res://skill_node/visuals/core_halos.gd")
	var halos = sn.get_node("Visuals/NodeVisualsComposite/ShaderStack/CorePresence/CoreHalos")
	assert_eq(
		halos.halo_style, CoreHalosScript.CoreHaloStyle.GIMBAL,
		"clearing restores core_halo_style to Default (-1), which reads back as GIMBAL")

	# A normal entity re-allocating the cleared node must never re-show the
	# boulder — the latch is permanent, not re-derived from current ownership.
	var player := await _spawn_normal_entity()
	_alloc.force_allocate(player, sn)
	player.core_location = sn
	await get_tree().process_frame
	assert_false(visual.visible, "boulder stays hidden after re-allocation by a normal entity")


# ── Procgen wiring ─────────────────────────────────────────────────────────

func _build_config(node_count: int, seed: int) -> GraphProcgenConfig:
	var cfg := GraphProcgenConfig.new()
	cfg.node_count = node_count
	cfg.seed = seed
	cfg.shape_mask = CircularShapeMask.new()
	return cfg


func test_procgen_instantiates_blocker_scene_only_for_blocked_nodes() -> void:
	var cfg := _build_config(60, 2468)
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)

	var blockers: Array = result.get("blockers", [])
	assert_gt(blockers.size(), 0, "expected default blocker density to place some")
	var blocked_ids := {}
	for placement in blockers:
		var node: SkillNode = placement.get("node")
		blocked_ids[node.get_instance_id()] = true
		assert_eq(
			node.scene_file_path, _BLOCKER_NODE_SCENE.resource_path,
			"a placed blocker must be a blocker_node.tscn instance")

	var nodes: Array = result.get("nodes", [])
	assert_gt(nodes.size(), blockers.size(), "expect some non-blocked nodes too")
	for node: SkillNode in nodes:
		if blocked_ids.has(node.get_instance_id()):
			continue
		assert_eq(
			node.scene_file_path, _SKILL_NODE_SCENE.resource_path,
			"a non-blocked node must be a plain skill_node.tscn instance")

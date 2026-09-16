extends GutTest
## v4 #321 D8 / #929: the hand-authored landmark SkillNode scenes each carry
## their own StatEffect on [member SkillNode.effects] (a SubResource of the
## .tscn) that grants the headline modifier — no Keystone resource in between.
const _WARD    := preload("res://entity/keystone/instances/mythic_ward_node.tscn")
const _FARSIGHT:= preload("res://entity/keystone/instances/farsight_node.tscn")
const _TITAN   := preload("res://entity/keystone/instances/titan_node.tscn")
const _ARCHMAGE:= preload("res://entity/keystone/instances/archmage_node.tscn")
const _NATURAL_XP := preload("res://entity/keystone/instances/natural_xp_node.tscn")
const _BASE := preload("res://entity/keystone/keystone_skill_node.tscn")

const _BASE_PATH := "res://entity/keystone/keystone_skill_node.tscn"
const _SKILL_NODE_PATH := "res://skill_node/skill_node.tscn"
func _check(scene: PackedScene, stat_id: StringName, op: int, value: float, label: String, index: int = 0) -> void:
	var n: SkillNode = autofree(scene.instantiate()) as SkillNode
	add_child(n)
	assert_true(n.effects.size() >= 1, "%s: the scene should carry >=1 effect on SkillNode.effects" % label)
	if n.effects.is_empty():
		return
	var fx = n.effects[0]
	assert_true(fx is StatEffect, "%s: effect[0] should be a StatEffect" % label)
	assert_true((fx as StatEffect).modifiers.size() > index, "%s: StatEffect should carry >%d modifier(s)" % [label, index])
	if (fx as StatEffect).modifiers.size() <= index:
		return
	var m = (fx as StatEffect).modifiers[index] as StatModifier
	assert_eq(m.stat_id, stat_id, "%s: stat_id" % label)
	assert_eq(int(m.operation), op, "%s: operation" % label)
	assert_almost_eq(float(m.value), value, 0.001, "%s: value" % label)
func test_mythic_ward_grants_minus_one_min_damage_taken() -> void:
	_check(_WARD, &"min_damage_taken", StatModifier.Operation.ADD_BASE, -1.0, "mythic_ward")
func test_farsight_grants_plus_100_vision_range() -> void:
	_check(_FARSIGHT, &"vision_range", StatModifier.Operation.ADD_BASE, 100.0, "farsight")
func test_titan_grants_x2_strength() -> void:
	_check(_TITAN, &"strength", StatModifier.Operation.MULTIPLY, 2.0, "titan")
func test_archmage_grants_x2_intelligence() -> void:
	_check(_ARCHMAGE, &"intelligence", StatModifier.Operation.MULTIPLY, 2.0, "archmage")
func test_natural_xp_grants_plus_10_xp_per_turn_and_plus_10_wisdom() -> void:
	_check(_NATURAL_XP, &"xp_per_turn", StatModifier.Operation.ADD_BASE, 10.0, "natural_xp", 0)
	_check(_NATURAL_XP, &"wisdom", StatModifier.Operation.ADD_BASE, 10.0, "natural_xp", 1)


## #929: the grant reaches a hand-built board on allocate, read off
## [member SkillNode.effects] by [AllocationSystem] — the same door every
## node-carried effect goes through, no Keystone in between.
func test_landmark_grants_reach_the_allocating_entity_via_effects() -> void:
	var alloc := autofree(AllocationSystem.new()) as AllocationSystem
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "T"
	ent.stat_board = (preload("res://entity/default_entity_board.tres") as EntityStatBoard).duplicate(true)
	var n: SkillNode = autofree(_TITAN.instantiate()) as SkillNode
	add_child(alloc)
	add_child(ent)
	add_child(n)
	await get_tree().process_frame
	var base: float = ent.stat_board.get_value(&"strength")
	assert_gt(base, 0.0, "the default board's strength is non-zero, so x2 is visible")
	alloc.force_allocate(ent, n)
	assert_almost_eq(float(ent.stat_board.get_value(&"strength")), base * 2.0, 0.001,
		"titan's x2 strength lands on allocate")
	assert_eq(ent.get_effects().size(), 1, "exactly the scene's one StatEffect is granted")
	alloc.force_deallocate(n)
	assert_almost_eq(float(ent.stat_board.get_value(&"strength")), base, 0.001,
		"deallocate revokes it")
	assert_eq(ent.get_effects().size(), 0)


## Fork ① regression (#336, settled 2026-08-01): the landmark scenes set no
## archetype and no longer claim a KEYSTONE-priority carve, so their emblem
## contributions stay empty across the deletion of `SkillNode.keystone`.
func test_landmarks_contribute_no_emblem() -> void:
	var scenes := {
		"mythic_ward": _WARD,
		"farsight": _FARSIGHT,
		"titan": _TITAN,
		"archmage": _ARCHMAGE,
		"natural_xp": _NATURAL_XP,
	}
	for label in scenes:
		var n: SkillNode = autofree(scenes[label].instantiate()) as SkillNode
		add_child(n)
		assert_eq(n.get_emblem_contributions().size(), 0, "%s: no emblem contribution" % label)


# ── #927: every keystone scene inherits the base's 40/32 radius ────────────

func test_base_and_landmarks_share_the_authored_radius() -> void:
	var scenes := {
		"base": _BASE,
		"mythic_ward": _WARD,
		"farsight": _FARSIGHT,
		"titan": _TITAN,
		"archmage": _ARCHMAGE,
		"natural_xp": _NATURAL_XP,
	}
	for label in scenes:
		var n: SkillNode = autofree(scenes[label].instantiate()) as SkillNode
		assert_eq(n.base_radius, 40.0, "%s: base_radius" % label)
		assert_eq(n.base_inner_radius, 32.0, "%s: base_inner_radius" % label)


## The family rule: every scene under entity/keystone/ inherits the base —
## none instances skill_node.tscn directly. A sixth keystone authored off the
## wrong base is the original defect returning, so this walks the actual
## files on disk rather than the preloaded consts above.
func test_keystone_family_scenes_all_inherit_the_base() -> void:
	var offenders: PackedStringArray = []
	for path in _find_tscn_files("res://entity/keystone"):
		if path == _BASE_PATH:
			continue
		var text := FileAccess.get_file_as_string(path)
		var references_base := text.find(_BASE_PATH) != -1
		var references_skill_node := text.find(_SKILL_NODE_PATH) != -1
		if not references_base or references_skill_node:
			offenders.append(path)
	assert_eq(offenders, PackedStringArray(),
		"every entity/keystone/ scene must ext_resource the keystone base, never skill_node.tscn directly")


## #179: each landmark authors its own display_name directly on the node —
## no keystone fallback survives this unit.
func test_landmarks_carry_a_non_empty_display_name() -> void:
	var scenes := {
		"mythic_ward": _WARD,
		"farsight": _FARSIGHT,
		"titan": _TITAN,
		"archmage": _ARCHMAGE,
		"natural_xp": _NATURAL_XP,
	}
	for label in scenes:
		var n: SkillNode = autofree(scenes[label].instantiate()) as SkillNode
		assert_false(n.get_display_name().is_empty(), "%s: get_display_name() must not be empty" % label)


static func _find_tscn_files(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry in [".", ".."]:
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			out.append_array(_find_tscn_files(full))
		elif entry.ends_with(".tscn"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


## #330: the first_level preset places every landmark whose ScenePlacement
## authors min_count >= 1 — reads the preset's counts, never pins them.
func test_first_level_places_every_landmark_with_a_min_count() -> void:
	var cfg_src: GraphProcgenConfig = load("res://procgen/presets/first_level/first_level.tres")
	var cfg: GraphProcgenConfig = cfg_src.duplicate(true)
	cfg.camp_sizes = [1]
	cfg.seed = 330
	var expected: Dictionary = {}
	for p in cfg.content.guaranteed_placements:
		if p is ScenePlacement and p.node_scene != null and p.min_count >= 1:
			expected[p.node_scene.resource_path] = p.min_count
	assert_gt(expected.size(), 0, "first_level authors at least one ScenePlacement with min_count >= 1")
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	var counts: Dictionary = {}
	for sn: SkillNode in result.get("nodes", []):
		counts[sn.scene_file_path] = counts.get(sn.scene_file_path, 0) + 1
	for path in expected:
		assert_gte(counts.get(path, 0), expected[path],
			"%s: at least min_count copies placed" % path)

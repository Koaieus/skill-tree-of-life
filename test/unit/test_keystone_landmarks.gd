extends GutTest
## v4 #321 D8: the 4 hand-authored landmark SkillNode scenes each carry a
## Keystone whose baked StatEffect grants the headline modifier.
const _WARD    := preload("res://entity/keystone/instances/mythic_ward_node.tscn")
const _FARSIGHT:= preload("res://entity/keystone/instances/farsight_node.tscn")
const _TITAN   := preload("res://entity/keystone/instances/titan_node.tscn")
const _ARCHMAGE:= preload("res://entity/keystone/instances/archmage_node.tscn")
const _NATURAL_XP := preload("res://entity/keystone/natural_xp_node.tscn")
const _BASE := preload("res://entity/keystone/keystone_skill_node.tscn")

const _BASE_PATH := "res://entity/keystone/keystone_skill_node.tscn"
const _SKILL_NODE_PATH := "res://skill_node/skill_node.tscn"
func _check(scene: PackedScene, stat_id: StringName, op: int, value: float, label: String) -> void:
	var n: SkillNode = autofree(scene.instantiate()) as SkillNode
	add_child(n)
	assert_not_null(n.keystone, "%s: keystone should be set on the node" % label)
	assert_true(n.keystone.effects.size() >= 1, "%s: keystone should carry >=1 effect" % label)
	var fx = n.keystone.effects[0]
	assert_true(fx is StatEffect, "%s: effect[0] should be a StatEffect" % label)
	assert_true((fx as StatEffect).modifiers.size() >= 1, "%s: StatEffect should carry >=1 modifier" % label)
	var m = (fx as StatEffect).modifiers[0] as StatModifier
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

extends GutTest

## Aspect spirits are placed by the first_level preset's own ScenePlacements:
## the same seed places the same spirits with the same aspects, and the
## placements consume the scene stream only after every landmark, so a preset
## without them places every other landmark identically.

const _PRESET := "res://procgen/presets/first_level/first_level.tres"
const _SPIRIT_PATHS: Array[String] = [
	"res://skill_node/keystone/instances/spirit_node.tscn",
	"res://skill_node/keystone/instances/mystery_spirit_node.tscn",
]
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


func _cfg(with_spirits: bool) -> GraphProcgenConfig:
	var src: GraphProcgenConfig = load(_PRESET)
	var cfg: GraphProcgenConfig = src.duplicate(true)
	cfg.camp_sizes = [1]
	cfg.seed = 1655
	cfg.topology.node_count = 200  # spirits only need room, not a full board
	if not with_spirits:
		var kept: Array[Resource] = []
		for p in cfg.content.guaranteed_placements:
			if not (p is ScenePlacement and p.node_scene != null and p.node_scene.resource_path in _SPIRIT_PATHS):
				kept.append(p)
		cfg.content.guaranteed_placements = kept
	return cfg


## [scene path, position, aspect id] per landmark node, in node order.
func _landmarks(cfg: GraphProcgenConfig) -> Array:
	var graph := autofree(_GRAPH_SCENE.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	var out: Array = []
	for sn: SkillNode in result.get("nodes", []):
		if sn.scene_file_path.begins_with("res://skill_node/keystone/"):
			var aspect_id: StringName = (sn as SpiritNode).aspect.id if sn is SpiritNode else &""
			out.append([sn.scene_file_path, sn.position, aspect_id])
	return out


func _spirits(landmarks: Array) -> Array:
	return landmarks.filter(func(l: Array) -> bool: return l[0] in _SPIRIT_PATHS)


func test_the_same_seed_places_the_same_spirits() -> void:
	var a: Array = await _landmarks(_cfg(true))
	var b: Array = await _landmarks(_cfg(true))
	var spirits := _spirits(a)
	assert_gte(spirits.size(), 3, "at least sp_spirit's min_count spirits")
	assert_eq(spirits, _spirits(b), "same count, positions and aspects")
	for s in spirits:
		assert_ne(s[2], &"", "every spirit rolled an aspect")


func test_without_the_placements_every_other_landmark_is_unchanged() -> void:
	var with_spirits: Array = await _landmarks(_cfg(true))
	var without: Array = await _landmarks(_cfg(false))
	var others := with_spirits.filter(func(l: Array) -> bool: return not (l[0] in _SPIRIT_PATHS))
	assert_gt(others.size(), 0)
	assert_eq(others, without, "the spirit draws come after every other landmark's")
	assert_eq(_spirits(without).size(), 0)

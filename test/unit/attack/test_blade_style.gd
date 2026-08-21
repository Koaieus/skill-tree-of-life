extends GutTest

## The blade's look layer (#256): identity tint off the wielder, and the interim
## "pop" — a dead vertex reads DE-LIT (below the bloom threshold, desaturated)
## rather than vanishing. Pins the two claims that are easy to break silently,
## since neither shows up in a headless render: that a lit part clears the HDR
## threshold and a disabled one does not, and that the blade never invents its
## own answer to "who died" (it reads BladePopResolver's).

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _STYLE := preload("res://attack/melee/default_blade_style.tres")


## Peak LINEAR channel — what the glow pass actually thresholds against
## (`docs/domain/hdr-color.md`), not the sRGB float you see in the picker.
func _linear_peak(c: Color) -> float:
	var lin := c.srgb_to_linear()
	return maxf(lin.r, maxf(lin.g, lin.b))


func _style() -> BladeStyle:
	return _STYLE.duplicate(true) as BladeStyle


# ── Tint ─────────────────────────────────────────────────────────────────────

func test_entity_colour_is_blended_into_the_base() -> void:
	var s := _style()
	s.entity_tint = 1.0
	var wielder := Color(0.2, 0.5, 1.0)
	assert_almost_eq(s.base_for(false, wielder).b, wielder.b, 0.001,
			"at full tint the blade is the wielder's colour")
	s.entity_tint = 0.0
	assert_almost_eq(s.base_for(false, wielder).b, s.member_base.b, 0.001,
			"at zero tint the authored base survives untouched")


func test_ownerless_blade_keeps_the_authored_base() -> void:
	var s := _style()
	assert_almost_eq(s.base_for(true, Color.TRANSPARENT).r, s.pivot_base.r, 0.001,
			"a transparent tint means 'no owner', not 'blend toward transparent'")


# ── Lit vs de-lit ────────────────────────────────────────────────────────────

func test_lit_rim_blooms_and_a_disabled_one_does_not() -> void:
	var s := _style()
	var tint := Color(0.9, 0.3, 0.25)
	assert_gt(_linear_peak(s.rim_color(false, tint, false)), 1.0,
			"a lit rim must clear the glow threshold, or nothing glows")
	assert_lt(_linear_peak(s.rim_color(false, tint, true)), 1.0,
			"a popped part must fall BELOW the threshold — that de-lighting is the whole interim pop")


func test_disabled_part_loses_saturation() -> void:
	var s := _style()
	var tint := Color(0.9, 0.3, 0.25)
	assert_lt(s.rim_color(false, tint, true).s, s.rim_color(false, tint, false).s,
			"HDR → SDR reads as grey, not merely dim")


# ── The blade wires both through ─────────────────────────────────────────────

func test_blade_takes_its_tint_from_the_wielder() -> void:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = _BOARD.duplicate(true)
	entity.color = Color(0.1, 0.8, 0.4)
	graph.add_child(entity)
	var pivot := _SKILL_NODE_SCENE.instantiate() as SkillNode
	var member := _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(pivot)
	graph.skill_nodes_container.add_child(member)
	member.position = Vector2(80.0, 0.0)
	await get_tree().process_frame

	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	add_child_autofree(blade)
	var nodes: Array[SkillNode] = [pivot, member]
	blade.build_from_skill_nodes(nodes, pivot, [[pivot, member]], entity)

	assert_eq(blade.entity_tint(), entity.color,
			"the blade is a copy of the wielder's nodes and must carry its colour")
	var visuals := blade.get_node_visuals()
	assert_eq(visuals.size(), 2, "one visual per vertex")
	for v in visuals:
		assert_eq(v.tint, entity.color, "every vertex gets the same identity tint")
		assert_false(v.disabled, "a fresh blade has nothing dead on it")


func test_a_rebuild_clears_a_previous_swings_deaths() -> void:
	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	add_child_autofree(blade)
	blade.pop_result = BladePopResolver.Result.new()
	blade.pop_result.dead_at[1] = 0.0
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var pivot := _SKILL_NODE_SCENE.instantiate() as SkillNode
	var member := _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(pivot)
	graph.skill_nodes_container.add_child(member)
	member.position = Vector2(80.0, 0.0)
	await get_tree().process_frame
	var nodes: Array[SkillNode] = [pivot, member]
	blade.build_from_skill_nodes(nodes, pivot, [[pivot, member]], null)

	assert_null(blade.pop_result,
			"a rebuilt blade must not inherit the last swing's dead set")

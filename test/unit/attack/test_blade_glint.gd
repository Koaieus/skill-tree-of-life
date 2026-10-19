extends GutTest

## The melee wind-up's BLING: one straight band swept once across the whole
## formed blade, replacing the ignition flare. The band is one fact on
## [SkillBlade] — a direction from [member BladeStyle.glint_angle_deg] and an
## offset along it — pushed down to each [BladeNode] as its `glint` (how far
## the band's centre has passed it, in band widths). Parameterised on the
## style knobs; the look itself is judged in the melee sandbox.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _POSITIONS: Array[Vector2] = [
	Vector2(0, 0), Vector2(80, 10), Vector2(30, 90), Vector2(-50, 40)]
const _PARAMS: Array = [[45.0, 28.0], [-30.0, 12.0], [0.0, 60.0], [80.0, 20.0]]


func _build_blade(angle: float, width: float) -> SkillBlade:
	var graph := TestWorld.create(self).graph
	var nodes: Array[SkillNode] = []
	for p in _POSITIONS:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		graph.skill_nodes_container.add_child(sn)
		sn.position = p
		nodes.append(sn)
	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	add_child_autofree(blade)
	var style: BladeStyle = BladeNode.DEFAULT_STYLE.duplicate(true) as BladeStyle
	style.glint_angle_deg = angle
	style.glint_width = width
	blade.style = style
	blade.build_from_skill_nodes(nodes, nodes[0],
			[[nodes[0], nodes[1]], [nodes[1], nodes[2]], [nodes[2], nodes[3]]],
			null, BladeVertexFill.new())
	return blade


func _proj(blade: SkillBlade, bn: BladeNode) -> float:
	return bn.global_position.dot(blade.style.glint_dir())


func _glints(blade: SkillBlade, progress: float) -> PackedFloat32Array:
	blade.glint_progress = progress
	var out := PackedFloat32Array()
	for bn in blade.get_node_visuals():
		out.append(bn.glint)
	return out


func _assert_unlit(blade: SkillBlade, why: String) -> void:
	for bn in blade.get_node_visuals():
		assert_gt(absf(bn.glint), 1.0, "%s: no vertex stays lit (glint %f)" % [why, bn.glint])


func test_band_starts_fully_before_and_ends_fully_past_every_vertex() -> void:
	for p in _PARAMS:
		var blade := _build_blade(p[0], p[1])
		assert_eq(blade.get_node_visuals().size(), _POSITIONS.size(), "built")
		for g in _glints(blade, 0.0):
			assert_lt(g, -1.0, "%s: at progress 0 the band has not reached a vertex" % [p])
		for g in _glints(blade, 1.0):
			assert_gt(g, 1.0, "%s: at progress 1 the band is past every vertex" % [p])


func test_each_vertex_glint_is_monotonic_in_progress() -> void:
	for p in _PARAMS:
		var blade := _build_blade(p[0], p[1])
		var prev := _glints(blade, 0.0)
		for k in range(1, 21):
			var cur := _glints(blade, k / 20.0)
			for i in cur.size():
				assert_gt(cur[i], prev[i], "%s: vertex %d's glint rises with progress" % [p, i])
			prev = cur


func test_vertices_cross_in_order_of_their_projection_on_the_band_normal() -> void:
	for p in _PARAMS:
		var blade := _build_blade(p[0], p[1])
		var visuals := blade.get_node_visuals()
		for k in range(0, 21):
			var g := _glints(blade, k / 20.0)
			for i in visuals.size():
				for j in visuals.size():
					if _proj(blade, visuals[i]) < _proj(blade, visuals[j]) - 0.01:
						assert_gt(g[i], g[j],
								"%s: the band reaches vertex %d before %d" % [p, i, j])


func test_form_in_sweeps_the_glint_and_leaves_nothing_lit_and_never_flares_modulate() -> void:
	var blade := _build_blade(45.0, 28.0)
	var total := blade.form_in(0.0, 0.0, 0.0, 0.0, 0.3)
	assert_almost_eq(total, 0.3, 0.0001, "the bling is the whole wind-up here")
	var lit_seen := false
	var peak := 0.0
	for k in 40:
		blade._form_tween.custom_step(0.01)
		peak = maxf(peak, blade.modulate.r)
		for bn in blade.get_node_visuals():
			if absf(bn.glint) <= 1.0:
				lit_seen = true
	assert_true(lit_seen, "the sweep lights each vertex as it crosses")
	assert_lte(peak, 1.0, "form_in no longer overshoots the blade's modulate")
	_assert_unlit(blade, "after form_in")


func test_stop_mid_sweep_clears_the_band() -> void:
	var blade := _build_blade(45.0, 28.0)
	blade.form_in(0.0, 0.0, 0.0, 0.0, 0.3)
	blade._form_tween.custom_step(0.15)
	blade.stop()
	_assert_unlit(blade, "after stop")
	blade.form_in(0.0, 0.0, 0.0, 0.0, 0.3)
	blade._form_tween.custom_step(0.15)
	blade.form_instantly()
	_assert_unlit(blade, "after form_instantly")


func test_melee_windup_seconds_sums_the_bling_as_the_last_beat() -> void:
	var t := PresentationTempo.new()
	t.melee_windup_pivot_focus = 0.2
	t.melee_windup_form_span = 0.3
	t.melee_windup_stamp_time = 0.5
	t.melee_windup_glow_ramp = 0.7
	t.melee_windup_bling = 1.1
	var lead := t.windup_lead(BattleSystem.AttackMode.MELEE)
	assert_almost_eq(t.melee_windup_seconds(true), lead + 0.3 + 0.5 + 0.7 + 1.1, 0.0001)
	assert_almost_eq(t.melee_windup_seconds(false), lead + 0.3 + 0.7 + 1.1, 0.0001)
	assert_false("melee_windup_flare" in t, "the flare knob is gone, renamed to the bling")

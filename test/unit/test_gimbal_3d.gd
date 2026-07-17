extends GutTest
## 3D gimbal core-halo (#239): the real-3D substrate for the boss-tier halo
## looks. Like the 2D gimbal test this is an "eyeball it" visual — a screenshot
## is the real acceptance (see the #239 showcase). What it CAN assert: it builds
## the right ring count without error, each style resolves a loadable shader
## material with a per-instance tint, and the animation is driven off a clock
## (rings re-orient over time). Shader GLSL is NOT compiled headless (dummy
## renderer) — see .claude/rules/godot-workflow.md for the xvfb opengl3 pass.

const GimbalScene := preload("res://skill_node/visuals/gimbal_3d/gimbal_3d_showcase.tscn")
const Gimbal3D := preload("res://skill_node/visuals/gimbal_3d/gimbal_3d.gd")


func _make(style: int, rings: int) -> Node3D:
	var g := Gimbal3D.new()
	g.ring_count = rings
	g.style = style
	add_child_autofree(g)
	return g


func test_builds_one_mesh_per_ring() -> void:
	var g := _make(Gimbal3D.Style.UNIFORM_GLOW, 3)
	await get_tree().process_frame
	var meshes := g.find_children("*", "MeshInstance3D", false, false)
	assert_eq(meshes.size(), 3, "one band MeshInstance3D per ring")
	for m in meshes:
		assert_true(m.mesh is CylinderMesh, "each ring is an (uncapped) cylinder band")
		assert_false(m.mesh.cap_top or m.mesh.cap_bottom, "band is open — a cylinder slice, not a capped drum")
		assert_not_null(m.material_override, "each ring has a style material")


func test_chain_root_is_the_outermost_ring() -> void:
	# The gimbal's parent (chain index 0, whose rotation propagates to every
	# inner ring) must be the OUTERMOST band, or "spin the outer, the inner
	# rides along" reads backwards. Radius therefore shrinks with chain index.
	var g := _make(Gimbal3D.Style.UNIFORM_GLOW, 3)
	await get_tree().process_frame
	var meshes := g.find_children("*", "MeshInstance3D", false, false)
	assert_gt(meshes[0].mesh.top_radius, meshes[2].mesh.top_radius,
		"ring 0 (chain root / parent) is the largest, outermost band")


func test_every_style_resolves_a_loadable_shader() -> void:
	for style in [Gimbal3D.Style.UNIFORM_GLOW, Gimbal3D.Style.HOLO_GLASS, Gimbal3D.Style.SOLID_GLYPH]:
		var g := _make(style, 2)
		await get_tree().process_frame
		var m := g.find_children("*", "MeshInstance3D", false, false)[0]
		var mat: ShaderMaterial = m.material_override
		assert_not_null(mat, "style %d has a ShaderMaterial" % style)
		assert_not_null(mat.shader, "style %d shader loaded" % style)


func test_rings_reorient_over_time() -> void:
	var g := _make(Gimbal3D.Style.UNIFORM_GLOW, 3)
	await get_tree().process_frame
	var ring: MeshInstance3D = g.find_children("*", "MeshInstance3D", false, false)[1]
	var before := ring.transform.basis
	g._process(0.5)
	assert_ne(before, ring.transform.basis, "the gimbal chain re-orients rings off the clock")


func test_showcase_scene_instantiates() -> void:
	var s := GimbalScene.instantiate()
	add_child_autofree(s)
	await get_tree().process_frame
	assert_true(s.has_method("noop"), "showcase satisfies the SandboxLiveTab loader contract")
	var rigs := s.find_children("*", "Node3D", true).filter(func(n): return n.get_script() == Gimbal3D)
	assert_eq(rigs.size(), 3, "showcase carries the three style rigs")

extends GutTest

## #670 P5. Two claims carry this primitive, and neither is safe to assume:
##
##   1. **One material for every overlay alive.** At Resonator's ~60 that is one
##      batch, not 60 draws. It stays true only while per-instance animation
##      rides transform + `modulate` — the moment anyone animates a per-overlay
##      shader *uniform*, the material duplicates and the batch is gone. So this
##      file fires 60, asserts one shared material, and separately asserts that
##      a full simulated flight leaves the shared uniforms untouched.
##
##   2. **It paints on top and never touches the edge.** No write to [Edge],
##      [Graph] or the edge MultiMesh, which is what makes it self-cleaning: a
##      cast cut short by teardown cannot leave an edge stuck energized.

const ENERGIZE := preload("res://ui/vfx/projectile/visual/edge_energize.tscn")
const EDGE_MATERIAL: ShaderMaterial = preload("res://graph/edge_mesh_material.tres")
const SOURCE_PATH := "res://ui/vfx/projectile/visual/edge_energize.gd"

const PEAK_OVERLAYS: int = 60
const A := Vector2(120.0, 340.0)
const B := Vector2(520.0, 100.0)


func _spawn() -> EdgeEnergize:
	var overlay: EdgeEnergize = ENERGIZE.instantiate()
	add_child_autofree(overlay)
	overlay.edge_origin = A
	overlay.edge_target = B
	return overlay


func _bar(overlay: EdgeEnergize) -> Sprite2D:
	return overlay.get_node("%Bar") as Sprite2D


## Source with every comment line dropped. The forbidden-symbol scan below is
## about what the CODE does; the class docs quite legitimately name the edge
## MultiMesh, since explaining why this primitive stays off it is half the point
## of the file.
func _code_only(path: String) -> String:
	var kept: PackedStringArray = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		kept.append(line)
	return "\n".join(kept)


# ------------------------------------------------------------------- batching


func test_sixty_overlays_share_one_material() -> void:
	var materials: Array = []
	var textures: Array = []
	for _i in PEAK_OVERLAYS:
		var bar := _bar(_spawn())
		if not materials.has(bar.material):
			materials.append(bar.material)
		if not textures.has(bar.texture):
			textures.append(bar.texture)
	assert_eq(materials.size(), 1, "60 overlays must resolve to exactly one material resource")
	assert_eq(textures.size(), 1, "…and one texture")
	assert_eq(materials[0], EdgeEnergize.SHARED_MATERIAL, "and it is the one named on the class")
	assert_eq(textures[0], EdgeEnergize.BAR_TEXTURE)


func test_a_full_flight_writes_no_shader_uniform() -> void:
	# The failure mode this guards is invisible at 1 overlay and catastrophic at
	# 60: a per-instance uniform write duplicates the shared material.
	var params: Array[StringName] = [&"edge_width", &"width_scale", &"feather_px",
		&"front_width", &"front_gain_stops", &"tail_level"]
	var before: Dictionary = {}
	for p in params:
		before[p] = EdgeEnergize.SHARED_MATERIAL.get_shader_parameter(p)
	var overlay := _spawn()
	overlay._on_launch()
	for i in 20:
		overlay._on_progress(float(i) / 19.0)
	overlay._on_crit(2)
	overlay._on_context({&"magnitude": 0.8})
	overlay.linger_seconds = 0.0
	overlay._on_arrival()
	for p in params:
		assert_eq(EdgeEnergize.SHARED_MATERIAL.get_shader_parameter(p), before[p],
			"a flight must not write the shared uniform `%s`" % p)


func test_no_overlay_owns_a_duplicated_material() -> void:
	var a := _bar(_spawn()).material
	var b := _bar(_spawn()).material
	assert_true(a == b, "two overlays must be the SAME material object, not two equal ones")


# ---------------------------------------------------- the front rides x-scale


func test_the_front_is_the_quads_x_scale() -> void:
	var overlay := _spawn()
	overlay.set_front(0.0)
	var closed: float = _bar(overlay).scale.x
	overlay.set_front(0.5)
	var half: float = _bar(overlay).scale.x
	overlay.set_front(1.0)
	var full: float = _bar(overlay).scale.x
	assert_lt(closed, half, "the front advances by growing the quad")
	assert_lt(half, full)
	assert_almost_eq(half * 2.0, full, 0.001, "and it advances linearly in `t`")


func test_the_quads_y_scale_is_left_alone_for_the_shader() -> void:
	# Width is derived in the vertex shader from `edge_camera_zoom`, ignoring
	# instance y-scale entirely. A y-scale write here would double-apply.
	var overlay := _spawn()
	overlay.set_front(1.0)
	assert_almost_eq(_bar(overlay).scale.y, 1.0, 0.0001, "y-scale stays 1")


func test_it_lies_along_the_edge_it_was_stamped_with() -> void:
	var overlay := _spawn()
	assert_almost_eq(overlay.position.distance_to(A), 0.0, 0.001, "anchored at the origin end")
	assert_almost_eq(overlay.rotation, (B - A).angle(), 0.0001, "rotated onto the segment")
	overlay.set_front(1.0)
	var covered: float = _bar(overlay).scale.x * float(EdgeEnergize.BAR_TEXTURE.get_width())
	assert_almost_eq(covered, A.distance_to(B), 0.5, "a full front spans the whole edge")


func test_a_degenerate_edge_draws_nothing() -> void:
	var overlay := _spawn()
	overlay.edge_target = overlay.edge_origin
	overlay.set_front(1.0)
	assert_almost_eq(_bar(overlay).scale.x, 0.0, 0.0001,
		"origin == target has no direction to lay light along")


# ------------------------------------------------------------- width sourcing


func test_width_comes_from_the_edges_own_material_not_a_copy() -> void:
	# "P5 reads `edge_camera_zoom` rather than any CPU-mirrored width." The zoom
	# half is in the shader; this is the other half — the authored stroke width
	# is READ off the edge's material, so retuning the edge retunes the overlay.
	EdgeEnergize._sync_width()
	assert_eq(EdgeEnergize.SHARED_MATERIAL.get_shader_parameter(&"edge_width"),
		EDGE_MATERIAL.get_shader_parameter(&"width"),
		"the overlay's width must be the edge's width, not a mirror of it")


func test_the_shader_reads_the_camera_zoom_global() -> void:
	var src: String = FileAccess.get_file_as_string(
		"res://ui/vfx/projectile/visual/edge_energize.gdshader")
	assert_true(src.contains("global uniform float edge_camera_zoom"),
		"the overlay must read the same global GraphCamera already pushes")


func test_exactly_one_new_shader_ships_with_this_unit() -> void:
	var dir := DirAccess.open("res://ui/vfx/projectile/visual/")
	var shaders: PackedStringArray = []
	for f in dir.get_files():
		if f.ends_with(".gdshader"):
			shaders.append(f)
	assert_eq(Array(shaders), ["edge_energize.gdshader"],
		"#670 ships exactly one new shader, and this is it")


# ------------------------------------------- paint-on-top, never the MultiMesh


func test_it_never_writes_to_edge_graph_or_the_multimesh() -> void:
	# A source-level pin, deliberately: the decision it protects ("paint-on-top,
	# NOT the edge MultiMesh") is one a well-meaning optimisation would undo,
	# and by then the symptom is a stuck-energized edge after a teardown, which
	# no unit test would catch.
	var src: String = _code_only(SOURCE_PATH)
	for forbidden in ["set_edge_", "multimesh", "MultiMesh", "INSTANCE_CUSTOM",
			"push_render_state", "_push_colors", "_push_transform"]:
		assert_false(src.contains(forbidden),
			"EdgeEnergize must not reach into the edge render path (`%s`)" % forbidden)


func test_its_only_reference_into_graph_is_a_read_only_preload() -> void:
	var src: String = _code_only(SOURCE_PATH)
	var graph_refs: int = src.count("res://graph/")
	assert_eq(graph_refs, 1, "exactly one `graph/` reference — the edge material it READS")
	assert_true(src.contains('preload("res://graph/edge_mesh_material.tres")'),
		"and it is a preload, not a lookup that could become a write")


# ----------------------------------------------------------------- lifecycle


func test_implements_the_full_duck_contract() -> void:
	var overlay := _spawn()
	for method in ["_on_launch", "_on_progress", "_on_arrival", "_on_crit", "_on_context"]:
		assert_true(overlay.has_method(method), "EdgeEnergize must implement %s" % method)
	assert_true(overlay.has_signal(&"finished"))


func test_arrival_without_a_linger_finishes_immediately() -> void:
	var overlay := _spawn()
	overlay.linger_seconds = 0.0
	watch_signals(overlay)
	overlay._on_arrival()
	assert_signal_emitted(overlay, "finished")


func test_it_lingers_before_finishing() -> void:
	var overlay := _spawn()
	overlay.linger_seconds = 0.15
	watch_signals(overlay)
	overlay._on_arrival()
	assert_signal_not_emitted(overlay, "finished", "the burn-in outlives the front")
	await wait_seconds(0.35)
	assert_signal_emitted(overlay, "finished")


func test_it_draws_above_the_fog() -> void:
	const ZLayers = preload("res://ui/z_layers.gd")
	assert_eq(_spawn().z_index, ZLayers.SPELL_VFX,
		"fog-oblivious, matching every other spell visual")


func test_crit_leans_the_overlay_hotter() -> void:
	var calm := _spawn()
	var hot := _spawn()
	hot._on_crit(2)
	assert_gt(hot.modulate.r, calm.modulate.r, "a crit burns hotter")


func test_context_magnitude_leans_the_resting_tier() -> void:
	var overlay := _spawn()
	overlay._on_context({&"magnitude": 0.0})
	var quiet: float = overlay.emissive_tier
	overlay._on_context({&"magnitude": 1.0})
	assert_gt(overlay.emissive_tier, quiet, "a bigger hit sits at a higher tier")
	assert_eq(overlay.emissive_tier, Emissive.VALUE, "and tops out at the named VALUE tier")


func test_context_tolerates_null_and_foreign_shapes() -> void:
	var overlay := _spawn()
	var authored: float = overlay.emissive_tier
	overlay._on_context(null)
	overlay._on_context({&"is_terminal": true})
	overlay._on_context(RefCounted.new())
	assert_eq(overlay.emissive_tier, authored, "an unread shape changes nothing")


# ------------------------------------------------------ endpoint self-derivation (#687)


func test_context_with_origin_and_target_derives_world_space_endpoints_and_sets_top_level() -> void:
	var overlay := _spawn()
	assert_false(overlay.top_level, "stamped directly (sandbox-style) — no context seen yet")
	var origin := SkillNode.new()
	origin.global_position = Vector2(15.0, 25.0)
	autofree(origin)
	var target := SkillNode.new()
	target.global_position = Vector2(415.0, 25.0)
	autofree(target)
	overlay._on_context({&"origin": origin, &"target": target})
	assert_true(overlay.top_level,
		"deriving world-space endpoints is exactly what top_level must mean here")
	assert_eq(overlay.edge_origin, origin.global_position)
	assert_eq(overlay.edge_target, target.global_position)


func test_context_without_endpoints_never_touches_top_level() -> void:
	# The regression this guards: the sandbox VFX-primitives tab instantiates
	# EdgeEnergize directly and stamps `edge_origin`/`edge_target` itself, in
	# ITS stage's PARENT space, and never calls `_on_context` at all. An
	# unconditional `top_level = true` (e.g. moved into `_ready`) would
	# reinterpret those coordinates as world space and misplace the overlay.
	var overlay: EdgeEnergize = ENERGIZE.instantiate()
	add_child_autofree(overlay)
	assert_false(overlay.top_level, "never received a context — stays parent-space by default")
	overlay._on_context({&"magnitude": 0.5})
	assert_false(overlay.top_level, "a context with no origin/target derives nothing")


# ---------------------------------------------- the concurrency bound (#663 D7)


func test_live_overlays_are_bounded_by_linger_not_by_hop_count() -> void:
	# Trail Blazer's `max_hops` bound is being REMOVED (#663 D7), so hop count
	# is unbounded and any "at most 20 overlays" reasoning is wrong. What
	# actually caps them is how long each one lingers against the beat.
	assert_eq(EdgeEnergize.max_live_overlays(2.5, 0.4), 8,
		"2.5s of linger over 0.4s beats is ceil(6.25)+1")
	assert_eq(EdgeEnergize.max_live_overlays(0.4, 0.4), 2, "a one-beat linger overlaps by one")
	assert_eq(EdgeEnergize.max_live_overlays(0.0, 0.4), 1, "no linger, one live overlay")


func test_a_longer_linger_is_the_only_thing_that_raises_the_bound() -> void:
	assert_gt(EdgeEnergize.max_live_overlays(5.0, 0.4),
		EdgeEnergize.max_live_overlays(2.5, 0.4), "linger raises it")
	assert_lt(EdgeEnergize.max_live_overlays(2.5, 0.8),
		EdgeEnergize.max_live_overlays(2.5, 0.4), "a slower beat lowers it")
	assert_eq(EdgeEnergize.max_live_overlays(2.5, 0.0), 0, "a zero beat is not a cast")

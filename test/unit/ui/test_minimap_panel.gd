extends GutTest

## [MinimapPanel]'s mapping and its redraw cadence (#453).
##
## Two things are pinned here, both of which fail SILENTLY in the running game:
##
##  1. **The fog rect and the dot transform must agree.** The fog quad is
##     full-bleed and its `UV` spans the whole map area, while the board is
##     letterboxed inside that area — so `_fog_world_rect` is the world bounds
##     expanded to the area's aspect, NOT the world bounds. Feeding the shader
##     the wrong one of the two offsets the fog by exactly the letterbox bars,
##     which looks almost right.
##  2. **The dot layer's self-shading mapping must agree with the dots.** The
##     dots are placed on the CPU by `_world_to_map`; the shader that erases
##     the fogged ones un-maps each fragment with two pushed uniforms. If those
##     drift, the fog cut-out lands somewhere other than where the dots are —
##     and nothing errors.
##  3. **A camera move must not redraw the graph layer.** That split is the
##     whole reason the minimap is affordable at 500–2500 nodes, and nothing in
##     the engine enforces it — a stray `queue_redraw` in the wrong handler
##     would just cost frames, quietly.

const _PANEL_SCENE := preload("res://ui/hud/minimap_panel/minimap_panel.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")

var _panel: MinimapPanel


func before_each() -> void:
	_panel = _PANEL_SCENE.instantiate()
	add_child_autofree(_panel)
	await get_tree().process_frame


# ------------------------------------------------------------- mapping ---

func test_world_to_map_round_trips() -> void:
	_panel._fit(Rect2(-500.0, -200.0, 1000.0, 400.0), Vector2(220.0, 220.0))
	for world in [Vector2(-500.0, -200.0), Vector2.ZERO, Vector2(123.0, -45.0)]:
		var back: Vector2 = _panel._map_to_world(_panel._world_to_map(world))
		assert_almost_eq(back.x, world.x, 0.001, "x round-trip for %s" % world)
		assert_almost_eq(back.y, world.y, 0.001, "y round-trip for %s" % world)


func test_aspect_fit_letterboxes_a_wide_graph() -> void:
	# 1000x400 world into a 220x220 area: the width binds, scale = 0.22, the
	# board draws 220x88 and is centred vertically with 66px bars.
	_panel._fit(Rect2(0.0, 0.0, 1000.0, 400.0), Vector2(220.0, 220.0))
	assert_almost_eq(_panel._map_scale, 0.22, 0.0001, "scale is the binding axis")
	var top_left: Vector2 = _panel._world_to_map(Vector2.ZERO)
	assert_almost_eq(top_left.x, 0.0, 0.001, "no horizontal bar")
	assert_almost_eq(top_left.y, 66.0, 0.001, "letterbox bar height")


func test_world_bounds_centre_maps_to_area_centre() -> void:
	_panel._fit(Rect2(-500.0, -200.0, 1000.0, 400.0), Vector2(220.0, 220.0))
	var centre: Vector2 = _panel._world_to_map(Vector2.ZERO)
	assert_almost_eq(centre.x, 110.0, 0.001, "centre x")
	assert_almost_eq(centre.y, 110.0, 0.001, "centre y")


func test_a_click_at_area_centre_lands_on_the_world_centre() -> void:
	var bounds := Rect2(-500.0, -200.0, 1000.0, 400.0)
	_panel._fit(bounds, Vector2(220.0, 220.0))
	var world: Vector2 = _panel._map_to_world(Vector2(110.0, 110.0))
	assert_almost_eq(world.x, bounds.get_center().x, 0.001, "world x")
	assert_almost_eq(world.y, bounds.get_center().y, 0.001, "world y")


func test_fog_rect_spans_the_full_area_not_the_letterboxed_board() -> void:
	# The drift guard: the fog rect's corners must land on the AREA's corners,
	# because that is what the shader's UV 0..1 covers.
	_panel._fit(Rect2(-500.0, -200.0, 1000.0, 400.0), Vector2(220.0, 220.0))
	var fog: Rect2 = _panel._fog_world_rect
	var near: Vector2 = _panel._world_to_map(fog.position)
	var far: Vector2 = _panel._world_to_map(fog.end)
	assert_almost_eq(near.x, 0.0, 0.001, "fog top-left x")
	assert_almost_eq(near.y, 0.0, 0.001, "fog top-left y")
	assert_almost_eq(far.x, 220.0, 0.001, "fog bottom-right x")
	assert_almost_eq(far.y, 220.0, 0.001, "fog bottom-right y")
	assert_gt(fog.size.y, 400.0, "the non-binding axis is EXPANDED, not clipped")


func test_graph_fog_uniforms_invert_the_dot_mapping() -> void:
	# The shader computes `world = origin + local_px * per_pixel`. That must be
	# exactly `_map_to_world`, i.e. the inverse of where the dots were placed.
	_panel._fit(Rect2(-500.0, -200.0, 1000.0, 400.0), Vector2(220.0, 220.0))
	_panel._push_graph_fog_mapping()
	var mat := _panel.graph_layer.material as ShaderMaterial
	assert_not_null(mat, "GraphLayer carries the self-shading material")
	var origin: Vector2 = mat.get_shader_parameter(&"minimap_world_origin")
	var per_pixel: float = mat.get_shader_parameter(&"minimap_world_per_pixel")
	for world in [Vector2(-500.0, -200.0), Vector2.ZERO, Vector2(123.0, -45.0)]:
		var local: Vector2 = _panel._world_to_map(world)
		var shaded: Vector2 = origin + local * per_pixel
		assert_almost_eq(shaded.x, world.x, 0.001, "shader un-maps x at %s" % world)
		assert_almost_eq(shaded.y, world.y, 0.001, "shader un-maps y at %s" % world)


func test_a_degenerate_fit_disables_the_mapping_instead_of_dividing_by_zero() -> void:
	_panel._fit(Rect2(), Vector2(220.0, 220.0))
	assert_eq(_panel._map_scale, 0.0, "no scale from an empty graph")
	# _map_to_world must still answer something finite — a click can arrive
	# before any node exists.
	var world: Vector2 = _panel._map_to_world(Vector2(110.0, 110.0))
	assert_false(is_nan(world.x), "no NaN out of a degenerate mapping")


# ------------------------------------------------------- redraw cadence ---

func test_a_camera_move_redraws_the_outline_but_not_the_graph() -> void:
	var camera := GraphCamera.new()
	add_child_autofree(camera)
	camera.set_graph_bounds(Rect2(-500.0, -500.0, 1000.0, 1000.0), 400.0)
	_panel.bind(null, camera, null)
	await get_tree().process_frame
	await get_tree().process_frame

	var graph_draws: int = _panel.graph_layer.draw_count
	camera.global_position += Vector2(120.0, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(_panel.graph_layer.draw_count, graph_draws,
			"a pan must not re-walk the board")


func test_an_unchanged_camera_does_not_redraw_the_outline() -> void:
	var layer := MinimapViewportRectLayer.new()
	add_child_autofree(layer)
	layer.set_view_rect(Rect2(0.0, 0.0, 10.0, 10.0))
	await get_tree().process_frame
	await get_tree().process_frame
	var before: int = layer.draw_count

	# The panel polls the camera every frame and re-pushes the rect it read.
	# Most frames it has not moved, and re-pushing an equal rect must not cost
	# a redraw — otherwise the whole "redraw only on change" split is a fiction
	# for the layer that redraws most often.
	for i in 3:
		layer.set_view_rect(Rect2(0.0, 0.0, 10.0, 10.0))
		await get_tree().process_frame
	assert_eq(layer.draw_count, before, "an equal rect must not queue a redraw")

	layer.set_view_rect(Rect2(1.0, 0.0, 10.0, 10.0))
	await get_tree().process_frame
	assert_gt(layer.draw_count, before, "but a moved rect must")


func test_the_outline_draws_all_four_sides_as_filled_spans() -> void:
	# The bug this replaces: a CENTRED hairline stroke rasterises to nothing at
	# some coordinates, and snapping to whole LOCAL pixels does not save it
	# because `canvas_items` stretch scales the whole HUD by a non-integer
	# factor. Filled spans always cover area.
	var edges: Array[Rect2] = MinimapViewportRectLayer._edge_rects(
			Rect2(10.0, 20.0, 40.0, 30.0), 1.0)
	assert_eq(edges.size(), 4, "all four sides present")
	for edge in edges:
		assert_gt(edge.size.x, 0.0, "side %s has width" % edge)
		assert_gt(edge.size.y, 0.0, "side %s has height" % edge)


func test_the_outline_sides_stay_inside_the_box_and_do_not_overlap() -> void:
	var box := Rect2(10.0, 20.0, 40.0, 30.0)
	var edges: Array[Rect2] = MinimapViewportRectLayer._edge_rects(box, 1.0)
	for edge in edges:
		assert_true(box.encloses(edge), "side %s escapes the box" % edge)
	# Top and bottom run the full width; the sides fill only between them, so
	# no corner is drawn twice (a double-drawn corner reads visibly brighter).
	assert_false(edges[0].intersects(edges[2]), "top and left overlap")
	assert_false(edges[1].intersects(edges[3]), "bottom and right overlap")


func test_a_thin_box_still_draws_rather_than_collapsing() -> void:
	# Zoomed far in, the view can be narrower than the stroke. The width caps
	# at half the shorter axis instead of producing inverted spans.
	var edges: Array[Rect2] = MinimapViewportRectLayer._edge_rects(
			Rect2(0.0, 0.0, 3.0, 1.0), 1.0)
	assert_eq(edges.size(), 4, "still four sides")
	for edge in edges:
		assert_gte(edge.size.x, 0.0, "no negative width")
		assert_gte(edge.size.y, 0.0, "no negative height")


func test_the_snapped_box_lands_on_whole_local_pixels() -> void:
	var layer := MinimapViewportRectLayer.new()
	add_child_autofree(layer)
	layer.set_view_rect(Rect2(10.4, 19.6, 40.2, 29.7))
	var r: Rect2 = layer._rect
	for value in [r.position.x, r.position.y, r.size.x, r.size.y]:
		assert_almost_eq(fposmod(value, 1.0), 0.0, 0.001,
				"%s is not a whole pixel" % value)


func test_a_degenerate_box_does_not_invert() -> void:
	var layer := MinimapViewportRectLayer.new()
	add_child_autofree(layer)
	layer.set_view_rect(Rect2(10.0, 20.0, 0.0, 0.0))
	assert_gte(layer._rect.size.x, 0.0, "no negative width")
	assert_gte(layer._rect.size.y, 0.0, "no negative height")
	assert_eq(MinimapViewportRectLayer._edge_rects(layer._rect, 1.0), [] as Array[Rect2],
			"a zero-area box draws nothing rather than inverted spans")


# ------------------------------------------------------------- geometry ---

func test_an_unowned_node_takes_the_neutral_tint() -> void:
	var node: SkillNode = _SKILL_NODE_SCENE.instantiate()
	add_child_autofree(node)
	assert_eq(_panel._node_color(node), _panel.neutral_node_color)


func test_an_owned_node_takes_its_owners_colour() -> void:
	var entity: Entity = _ENTITY_SCENE.instantiate()
	entity.color = Color(0.1, 0.8, 0.3)
	add_child_autofree(entity)
	var node: SkillNode = _SKILL_NODE_SCENE.instantiate()
	add_child_autofree(node)
	node.owned_by = entity
	assert_eq(_panel._node_color(node), entity.color)


func test_an_edge_is_owner_tinted_only_when_BOTH_ends_are_that_owners() -> void:
	var entity: Entity = _ENTITY_SCENE.instantiate()
	entity.color = Color(0.1, 0.8, 0.3)
	add_child_autofree(entity)
	var a: SkillNode = _SKILL_NODE_SCENE.instantiate()
	var b: SkillNode = _SKILL_NODE_SCENE.instantiate()
	add_child_autofree(a)
	add_child_autofree(b)
	var edge := Edge.new()
	edge.from = a
	edge.to = b
	add_child_autofree(edge)

	assert_eq(_panel._edge_color(edge), _panel.neutral_edge_color,
			"neither end owned")
	a.owned_by = entity
	assert_eq(_panel._edge_color(edge), _panel.neutral_edge_color,
			"a contested edge is not territory")
	b.owned_by = entity
	assert_almost_eq(_panel._edge_color(edge).g, entity.color.g, 0.001,
			"both ends owned takes the owner's hue")

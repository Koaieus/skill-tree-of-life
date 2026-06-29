extends GutTest

## #79 — the FloaterDirector translate/render seam. Covers: the director scene
## wires its renderer child; the renderer's pure FloaterRequest contract; and a
## domain fact on the bus (skill_node_damaged) routing through the director into
## a spawned floater. The modifier-binding bus shape is covered end-to-end by
## test_modifier_pulse_integration.

const _DIRECTOR_SCENE := preload("res://ui/floating_number_layer/floater_director.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _director: FloaterDirector
var _renderer: FloatingNumberLayer


func before_each() -> void:
	_director = _DIRECTOR_SCENE.instantiate() as FloaterDirector
	_director.vision_system = null  # no fog gating in the test
	add_child_autofree(_director)
	_renderer = _director.renderer


func _floater_children() -> Array:
	return _renderer.get_children().filter(func(c): return c is Floater)


func test_scene_wires_renderer() -> void:
	assert_not_null(_renderer, "director scene resolves its renderer child")
	assert_true(_renderer is FloatingNumberLayer)


func test_renderer_spawns_at_target() -> void:
	var node := Node2D.new()
	add_child_autofree(node)
	node.global_position = Vector2(123, 45)
	var req := FloaterRequest.new()
	req.target = node
	req.text = "+5"
	req.style = FloaterStyle.new()
	_renderer.spawn(req)
	var floaters := _floater_children()
	assert_eq(floaters.size(), 1, "exactly one floater spawned")
	assert_eq((floaters[0] as Floater).global_position, Vector2(123, 45), "anchored at target")


func test_renderer_ignores_empty_and_null() -> void:
	_renderer.spawn(null)
	var req := FloaterRequest.new()
	req.text = ""
	_renderer.spawn(req)
	assert_eq(_floater_children().size(), 0, "no floater for null request or empty text")


func test_damage_event_routes_through_director() -> void:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	await get_tree().process_frame
	Events.skill_node_damaged.emit(node, 7.0, null)
	var floaters := _floater_children()
	assert_eq(floaters.size(), 1, "a damage fact becomes one floater")
	assert_eq((floaters[0] as Floater).text, "7", "rounded damage amount")


func test_zero_damage_makes_no_floater() -> void:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	await get_tree().process_frame
	Events.skill_node_damaged.emit(node, 0.0, null)
	assert_eq(_floater_children().size(), 0, "non-positive damage is suppressed")


# --- Toaster ---

func test_burst_staggers_by_target() -> void:
	var target := Node2D.new()
	add_child_autofree(target)
	for i in 3:
		var req := FloaterRequest.new()
		req.target = target
		req.text = "+%d" % i
		_renderer.spawn(req)
	assert_eq(_floater_children().size(), 1, "first fires immediately; 2 queued")
	await get_tree().create_timer(_renderer.stagger_seconds * 2.2).timeout
	assert_eq(_floater_children().size(), 3, "all 3 fired after stagger intervals")


func test_ungrouped_bypasses_queue() -> void:
	for i in 2:
		var req := FloaterRequest.new()
		req.target = null
		req.anchor = Vector2(i * 10.0, 0.0)
		req.text = "x"
		_renderer.spawn(req)
	assert_eq(_floater_children().size(), 2, "ungrouped (key==0) requests bypass buffer")


func test_max_stack_drops_oldest() -> void:
	_renderer.max_stack_size = 2
	var target := Node2D.new()
	add_child_autofree(target)
	for i in 4:
		var req := FloaterRequest.new()
		req.target = target
		req.text = "t%d" % i
		_renderer.spawn(req)
	# First fires immediately; queue held 3 then was capped to 2 (oldest dropped).
	await get_tree().create_timer(_renderer.stagger_seconds * 2.5).timeout
	assert_eq(_floater_children().size(), 3, "capped at first + 2 queued; oldest dropped")

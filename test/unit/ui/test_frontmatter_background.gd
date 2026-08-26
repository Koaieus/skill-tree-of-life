extends GutTest

## #602 — a real background for the frontmatter menu instead of the engine's
## default gray.
##
## What is decidable here is the mechanism [code]FrontmatterBackground[/code]
## promises, not the picture: three shader layers exist and are wired up, the
## whole thing sits behind everything else via a negative
## [member CanvasLayer.layer], and [member GameSettings.reduce_motion] freezes
## the shader-driven animation clock without touching anything else. "Does it
## look good" is the owner's call per #602's brief, not this suite's.

const _SCENE := preload("res://ui/frontmatter/background/frontmatter_background.tscn")

var _bg: FrontmatterBackground


func before_each() -> void:
	_bg = _SCENE.instantiate()
	add_child_autofree(_bg)


func _layer_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for name in ["BaseLayer", "MidLayer", "NearLayer"]:
		out.append((_bg.get_node("%" + name) as Sprite2D).material as ShaderMaterial)
	return out


# --- composition --------------------------------------------------------

func test_it_instantiates_with_three_distinct_shader_layers() -> void:
	var mats := _layer_materials()
	assert_eq(mats.size(), 3)
	for mat in mats:
		assert_not_null(mat, "every layer must carry a ShaderMaterial")
		assert_not_null(mat.shader, "every layer's material must have a shader assigned")
	# Distinct materials/shaders, not one shared resource copy-pasted three
	# times — the base layer is the opaque colour-wave pass, the other two are
	# the additive line-streak pass reused at different depths.
	assert_ne(mats[0].shader, mats[1].shader,
			"base layer and streak layers are different shaders")
	assert_eq(mats[1].shader, mats[2].shader,
			"mid and near are the same streak shader reused, like starfield.gdshader's 3x reuse")
	assert_ne(mats[1], mats[2], "reused shader, but distinct material instances/uniforms")


func test_layer_draws_behind_everything_via_negative_canvas_layer() -> void:
	# Anything at the default CanvasLayer (layer 0) — the frontmatter's
	# %GraphLayer and %PanelLayer included — draws in FRONT of a negative
	# layer regardless of node order, so this is what "behind %GraphLayer"
	# actually cashes out to once mounted (see NOTES in the report / this
	# file's header for the intended mount point).
	assert_lt(_bg.layer, 0)


func test_the_three_layers_parallax_at_different_depths() -> void:
	var scrolls: Array[Vector2] = []
	for name in ["Base", "Mid", "Near"]:
		scrolls.append((_bg.get_node(name) as Parallax2D).scroll_scale)
	assert_ne(scrolls[0], scrolls[1])
	assert_ne(scrolls[1], scrolls[2])
	# Nearer layers scroll faster against the camera than farther ones — the
	# actual depth cue.
	assert_lt(scrolls[0].x, scrolls[1].x)
	assert_lt(scrolls[1].x, scrolls[2].x)


# --- reduce_motion --------------------------------------------------------

func test_shader_time_advances_by_default() -> void:
	_bg.reduce_motion = false
	_bg._process(0.5)
	for mat in _layer_materials():
		assert_almost_eq(float(mat.get_shader_parameter("shader_time")), 0.5, 0.0001)


func test_reduce_motion_freezes_the_shared_animation_clock() -> void:
	_bg.reduce_motion = true
	_bg._process(0.5)
	_bg._process(0.5)
	for mat in _layer_materials():
		assert_almost_eq(float(mat.get_shader_parameter("shader_time")), 0.0, 0.0001,
				"reduce_motion must freeze the shader clock, not just slow it")


func test_reduce_motion_does_not_touch_parallax_scroll_scale() -> void:
	# The camera-driven positional scroll is deliberately out of this script's
	# hands — FrontmatterRoot's own navigation travel already collapses under
	# reduce_motion, so this node must not also zero scroll_scale (that would
	# double-gate the same concern in two places).
	var before: Array[Vector2] = []
	for name in ["Base", "Mid", "Near"]:
		before.append((_bg.get_node(name) as Parallax2D).scroll_scale)
	_bg.reduce_motion = true
	_bg._process(1.0)
	var i := 0
	for name in ["Base", "Mid", "Near"]:
		assert_eq((_bg.get_node(name) as Parallax2D).scroll_scale, before[i])
		i += 1


# --- enabled toggle --------------------------------------------------------

func test_enabled_false_hides_the_whole_background() -> void:
	_bg.enabled = false
	assert_false(_bg.visible)


func test_enabled_true_is_the_default() -> void:
	assert_true(_bg.enabled)
	assert_true(_bg.visible)

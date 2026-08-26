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
##
## #605 adds two structural pins on top: the composite additive worst case
## (base clamp + both streak [code]line_strength[/code]s) stays under the
## bloom threshold, and the noise texture stays [code]seamless[/code] — plus
## confirms the mount into [code]frontmatter_root.tscn[/code] landed without
## breaking [code]%GraphLayer[/code] / [code]%PanelLayer[/code]. "No visible
## tile seam" and "captions are legible" are still a screenshot call, not
## this suite's.

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


# --- #605 dark mode + seam fix ---------------------------------------------

func test_composite_worst_case_stays_under_bloom_threshold() -> void:
	# frontmatter_plasma_base.gdshader clamps its output to 0.40 per channel
	# (#605) — not a uniform, so pinned here as a literal matching the shader.
	# The two additive streak layers sit on top of that opaque base
	# (blend_add), so the worst case is a straight sum of the base clamp and
	# both line_strengths; it must stay under 1.0 or the background clears
	# glow_hdr_threshold and blooms under default_game_env.tres.
	const BASE_CLAMP := 0.40
	var mats := _layer_materials()
	var mid_strength := float(mats[1].get_shader_parameter("line_strength"))
	var near_strength := float(mats[2].get_shader_parameter("line_strength"))
	var worst_case: float = BASE_CLAMP + mid_strength + near_strength
	assert_lt(worst_case, 1.0,
			"base + mid + near must stay under 1.0 or the background blooms (#605)")


func test_noise_texture_is_seamless() -> void:
	# Problem 1 (#605): a NoiseTexture2D with seamless = true is what
	# eliminates the four-quadrant tiling seam that a blank GradientTexture2D
	# + procedural fbm() left behind. This flag silently reverting is exactly
	# how the quadrants come back, so pin it structurally.
	for layer_name in ["BaseLayer", "MidLayer", "NearLayer"]:
		var tex := (_bg.get_node("%" + layer_name) as Sprite2D).texture
		assert_true(tex is NoiseTexture2D, "%s must sample a NoiseTexture2D" % layer_name)
		if tex is NoiseTexture2D:
			assert_true((tex as NoiseTexture2D).seamless,
					"%s's noise texture must be seamless" % layer_name)


# --- mount (#605) -----------------------------------------------------------

func test_frontmatter_root_mounts_the_background() -> void:
	# #605's other half: the background was built by #602 but deliberately
	# left unmounted until this issue landed. Confirm the mount happened and
	# that it did not disturb the layers the rest of the shell depends on.
	var root: Node2D = load("res://ui/frontmatter/frontmatter_root.tscn").instantiate()
	add_child_autofree(root)
	var mounted := root.get_node_or_null("FrontmatterBackground")
	assert_not_null(mounted, "frontmatter_root.tscn must mount FrontmatterBackground")
	assert_true(mounted is FrontmatterBackground)
	assert_not_null(root.get_node_or_null("%GraphLayer"), "%GraphLayer must still resolve")
	assert_not_null(root.get_node_or_null("%PanelLayer"), "%PanelLayer must still resolve")

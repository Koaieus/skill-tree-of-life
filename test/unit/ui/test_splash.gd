extends GutTest

## The attract state (#574) — the splash as the camera parked on the root node,
## not as a screen in front of one.
##
## [b]What is asserted is the camera and the allocation, not the pixels.[/b]
## #567's testing contract sends glow, easing and "does it look good" to the
## sandbox tab and the owner's eye. What is decidable here is where the camera
## sits before and after, whether the root reads allocated, and that a second
## press during the travel does nothing — which is the one behaviour #574 calls
## out by name.

const _SPLASH := preload("res://ui/frontmatter/splash_screen.tscn")
const _FRONTMATTER := preload("res://ui/frontmatter/frontmatter_root.tscn")

var _frontmatter: FrontmatterRoot
var _splash: SplashScreen


func before_each() -> void:
	_frontmatter = _FRONTMATTER.instantiate()
	add_child_autofree(_frontmatter)
	# reduce_motion so a focus lands in one frame — #574's own acceptance names
	# that as the test path, and it is the setting the accessibility knob feeds.
	_frontmatter.reduce_motion = true
	_splash = _SPLASH.instantiate()
	# Absolute, and set BEFORE entering the tree: `_ready` is what parks the
	# camera, and `get_path_to` from a node that is not in the tree yet does not
	# resolve. `meta_root.tscn` wires the same export as a relative sibling path.
	_splash.frontmatter_path = _frontmatter.get_path()
	add_child_autofree(_splash)


func _root() -> StringName:
	return _frontmatter.tree.root


func _camera_origin() -> Vector2:
	return (_frontmatter.get_node("%Camera") as Camera2D).position


# --- the parked state --------------------------------------------------------

func test_the_camera_starts_parked_on_the_splash_pose_not_the_tree_pose() -> void:
	# `FrontmatterRoot.build()` ends on `focus(root, true)`, so the camera is at
	# the ROOT's own tree pose until the splash takes it back. If this ever reads
	# that pose, the ordering in `meta_root.tscn` has been changed and the splash
	# no longer runs after the frontmatter.
	var expected := FrontmatterLayout.splash_camera(_frontmatter.tree)
	assert_eq(_camera_origin(), expected.origin)
	assert_almost_eq(FrontmatterLayout.zoom_of(expected).x,
			FrontmatterLayout.SPLASH_ZOOM, 0.0001)
	# Re-pointed by #593. The splash's neighbour is the ROOT pose, not the
	# generic tree zoom — the root menu authors its own zoom now, so comparing
	# against `TREE_ZOOM` would go on passing while having quietly stopped
	# testing "the same picture, closer in", which is the whole conceit.
	assert_gt(FrontmatterLayout.SPLASH_ZOOM,
			FrontmatterLayout.zoom_for(_frontmatter.tree, _root()),
			"the splash is the SAME picture, closer in — that is the whole conceit")


func test_the_root_is_not_allocated_while_the_prompt_is_still_asking() -> void:
	# The root is the node the player is ABOUT to allocate. Reading as allocated
	# before any key is pressed would give away the whole conceit.
	assert_false(_frontmatter.view_for(_root()).allocated)


func test_the_splash_is_visible_before_anything_is_pressed() -> void:
	assert_true(_splash.visible)
	assert_false(_splash.is_advanced())


func test_the_splash_paints_no_background_over_the_tree() -> void:
	# The tree is meant to show through, hugely magnified — that IS the effect.
	# The opaque ColorRect this replaced existed because the old splash was a
	# curtain in front of a menu that had not been built yet.
	for child in _splash.get_children():
		assert_false(child is ColorRect,
				"a full-screen fill would hide the root node the splash is OF")


# --- advancing is allocating the root ----------------------------------------

func test_advancing_travels_the_camera_out_to_the_tree_pose() -> void:
	_splash.advance()

	var expected := FrontmatterLayout.camera_for(_frontmatter.tree, _root())
	assert_eq(_camera_origin(), expected.origin)
	# Re-pointed by #593: the pose the splash pulls back to is whatever
	# `root_menu.tscn` authors, read off the scene rather than restated here.
	assert_almost_eq(FrontmatterLayout.zoom_of(expected).x,
			FrontmatterLayout.zoom_for(_frontmatter.tree, _root()), 0.0001)


func test_advancing_allocates_the_root() -> void:
	_splash.advance()
	assert_true(_frontmatter.view_for(_root()).allocated,
			"press any key IS allocating the first node")


func test_advancing_focuses_the_root_rather_than_cutting_to_it() -> void:
	_splash.advance()
	assert_eq(_frontmatter.focus_id, _root())


func test_advancing_takes_the_prompt_off_screen_and_emits_once() -> void:
	var seen: Array[int] = []
	_splash.advanced.connect(func(): seen.append(1))

	_splash.advance()

	assert_false(_splash.visible)
	assert_true(_splash.is_advanced())
	assert_eq(seen.size(), 1)


# --- the latch ---------------------------------------------------------------

func test_a_second_press_during_the_travel_does_not_re_trigger() -> void:
	# #574 names this: a held key or a double click must not restart the travel
	# from wherever it had got to.
	var seen: Array[int] = []
	_splash.advanced.connect(func(): seen.append(1))

	_splash.advance()
	_splash.advance()
	_splash.advance()

	assert_eq(seen.size(), 1, "advancing is one-way and happens once")


func test_the_latch_does_not_drag_the_camera_back_off_a_later_focus() -> void:
	# The scenario the latch actually protects: the player advances, navigates
	# on, and something presses again. Without the latch the second advance
	# would re-focus the root and yank them back to the top of the tree.
	_splash.advance()
	_frontmatter.focus(MenuGraph.ID_SINGLE_PLAYER, true)

	_splash.advance()

	assert_eq(_frontmatter.focus_id, MenuGraph.ID_SINGLE_PLAYER,
			"a stray press after advancing is not a route home")


# --- reduce motion -----------------------------------------------------------

func test_reduce_motion_lands_the_travel_in_one_frame() -> void:
	# Asserted by there being no tween left to drive: the camera is already at
	# the destination the moment `advance()` returns, which is what every other
	# test here relies on.
	_splash.advance()
	var expected := FrontmatterLayout.camera_for(_frontmatter.tree, _root())
	assert_eq(_camera_origin(), expected.origin)

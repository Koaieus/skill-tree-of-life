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


# --- the hold ----------------------------------------------------------------

func _polygons_under(node: Node) -> int:
	var found := 0
	for child in node.get_children():
		if child is Polygon2D:
			found += 1
		found += _polygons_under(child)
	return found


func test_the_root_lights_up_before_the_camera_sets_off() -> void:
	# The beat the splash exists for: allocating the first node has to be
	# visible AS an allocation, not as the first frame of a camera move. Before
	# the split these were one call, so the two happened in the same frame.
	_frontmatter.reduce_motion = false
	_splash.allocation_hold = 0.6
	var set_off: Array[int] = []
	_frontmatter.focus_started.connect(func(_id): set_off.append(1))

	_splash.advance()

	assert_true(_frontmatter.view_for(_root()).allocated,
			"the root is allocated on the spot")
	assert_eq(set_off.size(), 0,
			"and the camera has not set off — `focus_started` is what says it did")
	assert_eq(_camera_origin(), FrontmatterLayout.splash_camera(_frontmatter.tree).origin)


func test_advancing_drops_the_games_own_allocation_spike_on_the_root() -> void:
	# `AllocationVFX.spawn_alloc_spike` builds its needle as a Polygon2D, so one
	# appearing under the root view is the reuse itself — the menu has no
	# AllocationSystem to fire it and never will.
	var before := _polygons_under(_frontmatter.view_for(_root()))

	_splash.advance()

	assert_gt(_polygons_under(_frontmatter.view_for(_root())), before,
			"press any button plays the same VFX every other allocation plays")


## The defect this file's `spike_lead` answers, as arithmetic rather than as
## pixels: the needle is 6x the node radius in WORLD units and the splash parks
## at 3.2x, so a spike fired while the camera is still parked is `44 * 6 * 3.2`
## = 845px tall on a 960px screen whose root sits 422px down — half of it off
## the top, which is what shipped.
##
## Asserted at the instant the spike is SPAWNED, which is the strictest moment
## available: `AllocationVFX` ramps `scale.y` from 0 to 1 over the first half of
## `SPIKE_DURATION`, so the needle reaches full height 0.2s later still, by which
## point the camera has zoomed out further. Nothing here renders — the transform
## is rebuilt from the same public statics `FrontmatterCamera` interpolates, so
## this stays a decidable claim about the geometry and not a look-at-it test.
##
## It fails if anyone retunes SPLASH_ZOOM, the root's authored radius,
## SPIKE_HEIGHT_FACTOR or `spike_lead` back into the clipping range.
func test_the_needle_is_wholly_on_screen_by_the_time_it_drops() -> void:
	var tree := _frontmatter.tree
	var parked := FrontmatterLayout.splash_camera(tree)
	var arrived := FrontmatterLayout.camera_for(tree, _root())
	# Exactly what `FrontmatterCamera.transform_at` does with the clock the
	# splash schedules the needle on.
	var at_drop := parked.interpolate_with(
			arrived, FrontmatterCamera.ease_travel(_splash.spike_lead))
	var zoom := FrontmatterLayout.zoom_of(at_drop).y
	var view := FrontmatterLayout.viewport_size()
	var world := FrontmatterLayout.solve(tree)[_root()] as Vector2
	var screen_y := (world.y - at_drop.origin.y) * zoom + view.y * 0.5

	var radius := FrontmatterLayout.look_of(_root()).radius
	var needle := radius * AllocationVFX.SPIKE_HEIGHT_FACTOR * zoom

	assert_lte(needle, screen_y,
			"the needle (%.0fpx at zoom %.2f) overshoots the %.0fpx above the root"
					% [needle, zoom, screen_y])


func test_the_needle_does_not_drop_until_the_camera_has_set_off() -> void:
	# The whole of `spike_lead`: the flag is written on the press so
	# `_sync_allocation` stays a no-op re-assert, and the VFX is scheduled apart
	# from it. If the two are ever recombined, the spike lands at 3.2x again and
	# this catches it without anyone having to look at the screen.
	_frontmatter.reduce_motion = false
	_splash.allocation_hold = 0.05
	_splash.spike_lead = 0.5
	_frontmatter.travel_duration = 0.4
	var before := _polygons_under(_frontmatter.view_for(_root()))

	_splash.advance()

	assert_true(_frontmatter.view_for(_root()).allocated,
			"the root still reads allocated on the spot — only the VFX is delayed")
	assert_eq(_polygons_under(_frontmatter.view_for(_root())), before,
			"and no needle yet: the camera has not even set off")

	# Past the hold, into the travel, but short of the lead (0.5 * 0.4 = 0.2).
	await get_tree().create_timer(0.15).timeout
	assert_eq(_polygons_under(_frontmatter.view_for(_root())), before,
			"still none — the camera is travelling and the lead has not elapsed")

	await get_tree().create_timer(0.2).timeout
	assert_gt(_polygons_under(_frontmatter.view_for(_root())), before,
			"and there it is, dropped into the travel rather than before it")


func test_the_camera_really_does_set_off_once_the_hold_is_up() -> void:
	# The hold is a deferred call, and nothing else here waits on the timer —
	# if it ever stopped firing, the game's entry point would softlock on a
	# magnified root node with the prompt already gone.
	_frontmatter.reduce_motion = false
	_splash.allocation_hold = 0.1

	_splash.advance()
	await get_tree().create_timer(0.3).timeout

	assert_eq(_frontmatter.focus_id, _root())
	assert_true(_frontmatter.view_for(_root()).allocated)


func test_pressing_on_through_the_hold_is_not_dragged_back_to_the_root() -> void:
	# "PRESS ANY BUTTON" invites mashing. The latch stops the SECOND press
	# re-focusing the root; before the guard in `_travel`, the FIRST press did
	# it — the player navigated on during the hold and the timer yanked them
	# home a beat later.
	_frontmatter.reduce_motion = false
	_splash.allocation_hold = 0.1

	_splash.advance()
	_frontmatter.focus(MenuGraph.ID_SINGLE_PLAYER, true)
	await get_tree().create_timer(0.3).timeout

	assert_eq(_frontmatter.focus_id, MenuGraph.ID_SINGLE_PLAYER,
			"the hold expiring is not a route home either")


func test_a_zero_hold_sets_off_in_the_same_frame() -> void:
	# The authored escape hatch, and the same branch `reduce_motion` takes. It
	# removes the WAIT, not the travel — with motion on, the camera then tweens
	# out as usual, which is why this asserts the departure and not the arrival.
	_frontmatter.reduce_motion = false
	_splash.allocation_hold = 0.0
	var set_off: Array[int] = []
	_frontmatter.focus_started.connect(func(_id): set_off.append(1))

	_splash.advance()

	assert_eq(set_off.size(), 1)


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

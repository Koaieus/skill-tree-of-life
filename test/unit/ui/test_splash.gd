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


# --- the charge and the BOOM -------------------------------------------------

func _polygons_under(node: Node) -> int:
	var found := 0
	for child in node.get_children():
		if child is Polygon2D:
			found += 1
		found += _polygons_under(child)
	return found


## Where the root lands horizontally, in viewport pixels, under a given camera.
## The forward of [method FrontmatterLayout.screen_to_world], written out so a
## test can say "it did not drift sideways" as arithmetic.
func _screen_x(xform: Transform2D, world: Vector2) -> float:
	var zoom := FrontmatterLayout.zoom_of(xform).x
	return (world.x - xform.origin.x) * zoom + FrontmatterLayout.viewport_size().x * 0.5


## Where the root lands vertically, in viewport pixels, under a given camera.
func _screen_y(xform: Transform2D, world: Vector2) -> float:
	var zoom := FrontmatterLayout.zoom_of(xform).y
	return (world.y - xform.origin.y) * zoom + FrontmatterLayout.viewport_size().y * 0.5


func _root_world() -> Vector2:
	return FrontmatterLayout.solve(_frontmatter.tree)[_root()] as Vector2


func test_the_charge_sets_off_at_once_with_the_root_still_unlit() -> void:
	# The beat the splash exists for, INVERTED by #734. It used to be that the
	# root lit up on the press and the camera waited; the owner's complaint was
	# exactly that — "i see no 'glowing up'. i see the ring light up (like
	# identical to final lit state), then a sudden allocation vfx". Now the
	# camera leaves on the spot and the ring stays dark while the charge builds.
	#
	# Leg 1 is asserted through `charge_pose`, its pure half, rather than by
	# reading the live camera a wall-clock delay in. Sampling the tween would be
	# asserting the harness's frame delivery — a Tween stops advancing while the
	# SceneTree is paused while a SceneTreeTimer goes on firing, so a mid-flight
	# read is answerable by something no part of this file decides.
	_frontmatter.reduce_motion = false
	_splash.charge_duration = 0.5

	var set_off: Array[int] = []
	_frontmatter.focus_started.connect(func(_id): set_off.append(1))

	_splash.advance()

	assert_false(_frontmatter.view_for(_root()).allocated,
			"the root is NOT lit on the press — the charge is what is happening")
	assert_eq(set_off.size(), 0,
			"and `focus_started` has not fired: that is leg 2, which the BOOM starts")

	var parked := FrontmatterLayout.splash_camera(_frontmatter.tree)
	var charged := FrontmatterLayout.charged_camera(
			_frontmatter.tree, _splash.charge_end_zoom)
	assert_almost_eq(_splash.charge_pose(0.0).origin, parked.origin, Vector2(0.01, 0.01),
			"leg 1 departs from the parked pose")
	assert_ne(_splash.charge_pose(0.5).origin, parked.origin,
			"and it is a MOVE — the camera does not sit still through the charge")
	assert_almost_eq(_splash.charge_pose(1.0).origin, charged.origin, Vector2(0.01, 0.01),
			"landing on the charged pose, which is where the BOOM happens")


func test_advancing_drops_the_games_own_allocation_spike_on_the_root() -> void:
	# `AllocationVFX.spawn_alloc_spike` builds its needle as a Polygon2D, so one
	# appearing under the root view is the reuse itself — the menu has no
	# AllocationSystem to fire it and never will.
	var before := _polygons_under(_frontmatter.view_for(_root()))

	_splash.advance()

	assert_gt(_polygons_under(_frontmatter.view_for(_root())), before,
			"press any button plays the same VFX every other allocation plays")


## The clipping defect the retired `spike_lead` used to dodge, re-asserted at the
## pose the BOOM actually happens at — and now the guard on
## [member SplashScreen.charge_end_zoom]'s cap as well (#734).
##
## The needle is 6x the node radius in WORLD units: `44 * 6` = 264. Fired while
## the camera was still parked at `SPLASH_ZOOM` 3.2 that was 845px of needle on a
## 960px screen whose root sat 422px down — half of it off the top, which is what
## shipped. `spike_lead` answered it by delaying the needle into the travel.
##
## The BOOM now happens at the CHARGED pose: the root at `hero_slot()`'s y, which
## is 480px of headroom, and the zoom the owner tunes. At the authored 1.6 that
## is `264 * 1.6` = 422px against 480px — 58px of clearance. The knob's range
## tops out at 1.8, below the `480 / 264` = 1.81 at which clipping resumes, so
## this passes for EVERY value the inspector can produce; it is read off the
## splash rather than restated so it tracks whatever the owner dials.
##
## Nothing here renders — the transform is rebuilt from the same public statics
## the splash itself uses, so this stays a decidable claim about the geometry.
func test_the_needle_is_wholly_on_screen_by_the_time_it_drops() -> void:
	var tree := _frontmatter.tree
	var at_drop := FrontmatterLayout.charged_camera(tree, _splash.charge_end_zoom)
	var zoom := FrontmatterLayout.zoom_of(at_drop).y
	var view := FrontmatterLayout.viewport_size()
	var world := _root_world()
	var screen_y := (world.y - at_drop.origin.y) * zoom + view.y * 0.5

	var radius := FrontmatterLayout.look_of(_root()).radius
	var needle := radius * AllocationVFX.SPIKE_HEIGHT_FACTOR * zoom

	assert_lte(needle, screen_y,
			"the needle (%.0fpx at zoom %.2f) overshoots the %.0fpx above the root"
					% [needle, zoom, screen_y])


func test_the_charge_end_zoom_cannot_be_tuned_into_the_clipping_defect() -> void:
	# The cap is the guard, so it is asserted as a cap rather than trusted. Every
	# value the `@export_range` can produce must keep the needle on screen — that
	# is what makes this knob safe to hand to the owner.
	var ceiling := FrontmatterLayout.hero_slot().y \
			/ (FrontmatterLayout.look_of(_root()).radius * AllocationVFX.SPIKE_HEIGHT_FACTOR)
	assert_lt(_splash.charge_end_zoom, ceiling,
			"the authored default keeps the needle whole")
	assert_lte(1.8, ceiling,
			"and so does the top of its range — the inspector cannot reach the defect")


func test_leg_one_stops_short_of_tree_zoom_so_leg_two_finishes_the_opening() -> void:
	# The owner's correction: "the camera zooms out FAST and A LOT by the time
	# the alloc vfx hits". Leg 1 ending at TREE_ZOOM is what caused that, and no
	# easing can fix it — the flash would still land on a parked camera. So leg 1
	# stops short and leg 2 carries the rest of the zoom out with its slide.
	var tree := _frontmatter.tree
	var charged := FrontmatterLayout.charged_camera(tree, _splash.charge_end_zoom)
	var arrived := FrontmatterLayout.camera_for(tree, _root())

	assert_gt(FrontmatterLayout.zoom_of(charged).x, FrontmatterLayout.TREE_ZOOM,
			"the BOOM happens closer in than the tree pose — still opening")
	assert_lt(FrontmatterLayout.zoom_of(charged).x, FrontmatterLayout.SPLASH_ZOOM,
			"but leg 1 really did zoom out; it is a move, not a hold")
	assert_gt(FrontmatterLayout.zoom_of(charged).x, FrontmatterLayout.zoom_of(arrived).x,
			"so leg 2 still has zoom left to travel, which is what it rides its pan on")


func test_the_needle_does_not_drop_until_the_charge_has_finished() -> void:
	# The whole of the charge: the flag and the needle both belong to the BOOM,
	# and neither may leak forward into leg 1. If they are ever pulled back onto
	# the press, the root snaps lit at 3.2x again with a needle over it and this
	# catches it without anyone having to look at the screen.
	_frontmatter.reduce_motion = false
	_splash.charge_duration = 0.25
	var before := _polygons_under(_frontmatter.view_for(_root()))

	_splash.advance()

	assert_false(_frontmatter.view_for(_root()).allocated,
			"nothing is allocated yet — the charge is still building")
	assert_eq(_polygons_under(_frontmatter.view_for(_root())), before,
			"and no needle: the BOOM has not happened")

	# Into the charge, but short of its end.
	await get_tree().create_timer(0.15).timeout
	assert_eq(_polygons_under(_frontmatter.view_for(_root())), before,
			"still none — the charge is running and has not detonated")

	await get_tree().create_timer(0.2).timeout
	assert_true(_frontmatter.view_for(_root()).allocated,
			"and now the root reads lit — the BOOM is where that lands")
	assert_gt(_polygons_under(_frontmatter.view_for(_root())), before,
			"and there is the needle, at the seam between the two legs")


func test_the_boom_lands_once_the_charge_is_up() -> void:
	# The charge ends on a deferred call, and nothing else here waits on the
	# timer — if it ever stopped firing, the game's entry point would softlock on
	# a magnified root node with the prompt already gone AND navigation locked.
	_frontmatter.reduce_motion = false
	_splash.charge_duration = 0.1

	_splash.advance()
	await get_tree().create_timer(0.3).timeout

	assert_eq(_frontmatter.focus_id, _root())
	assert_true(_frontmatter.view_for(_root()).allocated)
	assert_false(_frontmatter.navigation_locked,
			"and the menu is steerable again — a lock left raised is a softlock")


func test_leg_two_departs_from_the_charged_pose_whichever_clock_wins() -> void:
	# The charge runs on two clocks — a Tween for the camera, a SceneTreeTimer
	# for the BOOM — and they finish on different frames. `_end_charge` writes
	# the charged pose explicitly so leg 2's ORIGIN never depends on which won.
	# `transform_at(0.0)` is that origin, read as a value rather than chased
	# across tween frames.
	_frontmatter.reduce_motion = false
	_splash.charge_duration = 0.05
	_frontmatter.travel_duration = 2.0

	_splash.advance()
	await get_tree().create_timer(0.25).timeout

	var charged := FrontmatterLayout.charged_camera(
			_frontmatter.tree, _splash.charge_end_zoom)
	assert_almost_eq(_frontmatter.camera.transform_at(0.0).origin, charged.origin,
			Vector2(0.01, 0.01),
			"leg 2 must pan from the pose leg 1 was aiming at, not from wherever "
					+ "the tween happened to have got to")


func test_navigation_is_locked_for_the_length_of_the_charge() -> void:
	# "PRESS ANY BUTTON" invites mashing, and leg 1 is a live camera writer for
	# the whole charge — a second navigation would start `_transition` driving
	# the SAME camera and the two would fight. Owner call 2026-09-03: lock input
	# for the charge.
	#
	# Asserted by calling `focus` DIRECTLY, which is honest only because the gate
	# is on `focus` itself: this covers the keyboard path and the mouse path at
	# once, where a test driving `_unhandled_input` would miss the click entirely
	# (GUI picking runs before `_unhandled_input`).
	_frontmatter.reduce_motion = false
	_splash.charge_duration = 0.2

	_splash.advance()
	assert_true(_frontmatter.navigation_locked, "the charge raises the gate")

	_frontmatter.focus(MenuGraph.ID_SINGLE_PLAYER, true)
	assert_eq(_frontmatter.focus_id, _root(),
			"you cannot steer during the charge")

	await get_tree().create_timer(0.4).timeout
	assert_false(_frontmatter.navigation_locked, "and the BOOM releases it")
	assert_eq(_frontmatter.focus_id, _root(),
			"the charge finishing lands on the root, which is where it was aimed")


func test_a_zero_charge_booms_in_the_same_frame() -> void:
	# The authored escape hatch, and the same branch `reduce_motion` takes. It
	# removes the CHARGE, not the travel — with motion on, leg 2 then pans out as
	# usual, which is why this asserts the departure and not the arrival.
	_frontmatter.reduce_motion = false
	_splash.charge_duration = 0.0
	var set_off: Array[int] = []
	_frontmatter.focus_started.connect(func(_id): set_off.append(1))

	_splash.advance()

	assert_eq(set_off.size(), 1)


# --- leg 1 makes room NORTH, and nothing else --------------------------------

func test_leg_one_takes_the_vertical_without_drifting_sideways() -> void:
	# The whole claim of the split: leg 1 zooms out and takes the 58px drop with
	# the root still horizontally centred, so leg 2 is left a PURE horizontal
	# pan. Both halves are true by construction — `charged_camera` reads its x
	# from the parked pose and its y from `hero_slot()` — and this is what would
	# catch someone "tidying" those reads into literals.
	var tree := _frontmatter.tree
	var parked := FrontmatterLayout.splash_camera(tree)
	var charged := FrontmatterLayout.charged_camera(tree, _splash.charge_end_zoom)
	var arrived := FrontmatterLayout.camera_for(tree, _root())
	var world := _root_world()

	assert_almost_eq(_screen_x(charged, world), _screen_x(parked, world), 0.01,
			"leg 1 must not move the root sideways — that is leg 2's whole job")
	assert_almost_eq(_screen_x(charged, world),
			FrontmatterLayout.slot(FrontmatterLayout.SPLASH_SLOT_RATIO).x, 0.01,
			"and the slot it holds is the parked pose's own")
	assert_almost_eq(_screen_y(charged, world), _screen_y(arrived, world), 0.01,
			"and the root holds its screen HEIGHT from the BOOM onward, so leg 2 "
					+ "reads as a clean zoom-and-slide rather than a second drop")


func test_reduce_motion_collapses_the_charge_as_well_as_the_travel() -> void:
	# D10, asserted directly rather than left implied. `reduce_motion` collapses
	# leg 1 exactly as it collapses `travel_duration` — a player who asked for no
	# motion is not asking for a half-second stare at an unlit root.
	_frontmatter.reduce_motion = true
	_splash.charge_duration = 0.5

	_splash.advance()

	assert_true(_frontmatter.view_for(_root()).allocated,
			"the BOOM is immediate — the charge collapsed with the travel")
	assert_eq(_frontmatter.focus_id, _root())
	assert_false(_frontmatter.navigation_locked,
			"and no lock outlives an advance that took no time")


# --- the charge glow ---------------------------------------------------------

func _charge() -> ChargeGlow:
	return (_frontmatter.view_for(_root()) as SplashRootView).charge


func test_the_root_view_is_the_only_one_that_can_charge_up() -> void:
	# "Bespoke, just for this one" (owner, 2026-09-03). The charge is an added
	# child on an INHERITED view scene, so every other node in the menu is the
	# ordinary `menu_node_view.tscn` with no glow anywhere in it.
	assert_not_null(_frontmatter.view_for(_root()) as SplashRootView,
			"the root's view carries the charge")
	var other := _frontmatter.view_for(MenuGraph.ID_SINGLE_PLAYER)
	assert_null(other as SplashRootView,
			"and no other node does — the effect is not part of the regular ones")


func test_the_charge_ramps_between_named_emissive_tiers() -> void:
	# `.claude/rules/hdr-color.md`: the endpoints are NAMED tiers and only the
	# interpolant between them is computed. INERT sits exactly at the bloom
	# threshold, so an idle charge cannot glow.
	var glow := _charge()

	glow.set_progress(0.0)
	assert_almost_eq(glow.charge_stops(), Emissive.INERT, 0.0001)

	glow.set_progress(1.0)
	assert_almost_eq(glow.charge_stops(), Emissive.PEAK, 0.0001)


func test_detonating_takes_the_charge_away_again() -> void:
	# The load-bearing half of the BOOM. Left at PEAK the ring would sit
	# permanently brighter than anything else on screen, behind the root's
	# ordinary lit state — a worse artifact than the instant-lit snap #734
	# replaced. The composite underneath takes over from here.
	var glow := _charge()
	glow.set_progress(1.0)

	glow.detonate(true)

	assert_lte(glow.charge_stops(), Emissive.VALUE,
			"the charge is dismissed — it does not outlive its own detonation")


# --- the dev reload key (F5) -------------------------------------------------

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


func test_the_reload_key_is_not_a_press_any_button() -> void:
	# The splash sees `_unhandled_input` BEFORE FrontmatterInput — it is ordered
	# after the frontmatter in `meta_root.tscn` — and "PRESS ANY BUTTON" takes
	# the raw event kind, so every InputEventKey advances it. Without the
	# exclusion F5 would skip the beat it exists to replay and be consumed before
	# anything could reload.
	assert_false(SplashScreen.is_any_button(_key(FrontmatterInput.RELOAD_KEY)),
			"F5 is the dev key, not a press")
	assert_true(SplashScreen.is_any_button(_key(KEY_SPACE)),
			"but an ordinary key still means it — the prompt says ANY button")


func test_the_reload_key_is_recognised_by_one_shared_constant() -> void:
	# Asserted through the same predicate the splash excludes on, so the dev key
	# and its exclusion cannot drift apart into two different keycodes.
	assert_true(FrontmatterInput.is_reload(_key(FrontmatterInput.RELOAD_KEY)))
	assert_false(FrontmatterInput.is_reload(_key(KEY_SPACE)))
	assert_false(FrontmatterInput.is_reload(InputEventJoypadButton.new()),
			"a gamepad button is never the reload key")


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

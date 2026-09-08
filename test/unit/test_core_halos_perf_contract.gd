extends GutTest
## Core-halos perf contract (#802). The halos measured 8.09ms of a 12.21ms idle
## frame on a 2000-node board with ONE of 307 on screen, and every millisecond
## of it was per-frame REBUILD, not draw. The fix is structural — rigid styles
## rotate instead of redrawing, invisible halos stop entirely, and the gimbal's
## two halves share one computation.
##
## These tests exist because that fix is invisible to the eye: a refactor that
## silently reverted any of it would still LOOK correct and would still pass
## every other test in the suite, while putting the 8ms back. So each test pins
## the negative — "and it did NOT rebuild" — not just that the picture is right.
## See test_core_halos_gimbal.gd for the geometry half of the contract (#138).

const HalosScene := preload("res://skill_node/visuals/core_halos.tscn")
## CoreHalos declares no `class_name` (every leaf in this family is duck-typed,
## see skill-node-visuals.md), so the enum is reached through the script.
const HalosScript := preload("res://skill_node/visuals/core_halos.gd")


func _make(style: int) -> Node2D:
	var halos := HalosScene.instantiate()
	add_child_autofree(halos)
	halos.halo_style = style
	await get_tree().process_frame
	await get_tree().process_frame
	return halos


# — 1. rotate, don't redraw ————————————————————————————————————————————————————

func test_rigid_styles_get_one_spin_layer_per_independently_spinning_ring() -> void:
	var cog := await _make(HalosScript.CoreHaloStyle.COG)
	assert_eq(cog._spin_layers.size(), 1, "COG is one rigid ring")
	assert_almost_eq(float(cog._spin_layers[0].spin_rate), 0.3, 0.0001,
			"COG's teeth advanced at _spin() * 0.3 before the split; the rate moved, the picture didn't")

	var rings := await _make(HalosScript.CoreHaloStyle.RINGS)
	assert_eq(rings._spin_layers.size(), 3, "RINGS' three rings spin at different rates, so they cannot share one item")
	var rates: Array[float] = []
	for layer in rings._spin_layers:
		rates.append(float(layer.spin_rate))
	assert_eq(rates, [1.0, 1.5, 2.0] as Array[float], "the old 1.0 + i * 0.5 rates, now as transforms")

	var orbit := await _make(HalosScript.CoreHaloStyle.ORBIT)
	assert_eq(orbit._spin_layers.size(), 1, "ORBIT's beads ride one track")


func test_gimbal_and_none_get_no_spin_layers() -> void:
	# GIMBAL's projected silhouette genuinely changes every frame — a nested
	# 3D rotation is NOT a 2D transform, which is why it is the one style left
	# rebuilding (and why #804 exists).
	var gimbal := await _make(HalosScript.CoreHaloStyle.GIMBAL)
	assert_eq(gimbal._spin_layers.size(), 0, "GIMBAL cannot be reduced to a rotation")
	var none := await _make(HalosScript.CoreHaloStyle.NONE)
	assert_eq(none._spin_layers.size(), 0, "NONE draws nothing to rotate")


func test_a_clock_tick_writes_rotation_and_never_re_enters_draw() -> void:
	# THE perf contract. Godot does not re-run _draw() for a transform change,
	# so this is what makes an animating COG cost a float write instead of a
	# rebuilt circle + ten teeth.
	var halos := await _make(HalosScript.CoreHaloStyle.COG)
	var layer: Node2D = halos._spin_layers[0]
	var draws := [0]
	layer.draw.connect(func() -> void: draws[0] += 1)

	# Positive control FIRST: prove this harness can observe a redraw at all,
	# or the assertion below cannot tell "correctly gated" from "never draws".
	layer.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	var baseline: int = draws[0]
	assert_gt(baseline, 0, "positive control: an explicit queue_redraw DOES re-enter _draw")

	for i in 5:
		halos.anim_time += 0.1
		halos._on_anim_tick()
		await get_tree().process_frame
	assert_eq(draws[0], baseline, "ticking the shared clock rotates the layer and never re-enters _draw (#802)")
	assert_almost_eq(layer.rotation, halos._spin() * float(layer.spin_rate), 0.0001,
			"...and the tick did write the rotation, so the halo is animating rather than frozen")


# — 2. the gate ————————————————————————————————————————————————————————————————

func test_on_screen_defaults_closed() -> void:
	# Fail-OPEN is precisely the bug: every off-screen halo would animate
	# forever. The notifier reports one frame late and emits `screen_entered`
	# on its first served frame when it really is visible, so "assume not" is
	# both safe and self-correcting.
	var halos := HalosScene.instantiate()
	assert_false(halos._on_screen, "a halo does not assume it is on screen")
	halos.free()


func test_an_unseen_halo_stops_processing_and_resumes_when_seen() -> void:
	var halos := await _make(HalosScript.CoreHaloStyle.COG)
	assert_true(halos.is_processing(), "a revealed halo animates")

	halos.halo_revealed = false
	assert_false(halos.is_processing(),
			"neither revealed nor on screen — nobody can see it, so it must not rebuild (this is the fogged-node case)")

	halos.halo_revealed = true
	assert_true(halos.is_processing(), "resumes when the fog lifts")

	halos.halo_revealed = false
	halos._on_screen_changed(true)
	assert_true(halos.is_processing(), "on screen alone is enough — the two conditions are OR'd, not AND'ed")


func test_a_hidden_halo_never_animates_however_visible_it_claims_to_be() -> void:
	# visible-in-tree is AND'ed, not OR'ed: the composite hides CorePresence
	# for every non-core node, which is ~1700 of 2000 on a real board.
	var halos := await _make(HalosScript.CoreHaloStyle.COG)
	halos.halo_revealed = true
	halos._on_screen_changed(true)
	assert_true(halos.is_processing(), "control: it is animating before we hide it")

	halos.visible = false
	await get_tree().process_frame
	assert_false(halos.is_processing(), "hidden outranks both revealed and on-screen")


# — 3. one gimbal computation per frame ————————————————————————————————————————

func test_both_gimbal_halves_are_the_same_computation_not_two_that_agree() -> void:
	# Agreement was already true before #802 — both halves ran the full
	# projection and each threw the other's result away. So assert SHARING:
	# move the clock between the two calls and require the second to ignore it.
	var halos := await _make(HalosScript.CoreHaloStyle.GIMBAL)
	halos.anim_time = 0.0
	halos._redraw_all()
	var front: Dictionary = halos.gimbal_layer_batch(true)
	halos.anim_time = 5.0
	var back: Dictionary = halos.gimbal_layer_batch(false)

	var at_zero: Dictionary = halos._gimbal_batch(_runs_at(halos, 0.0)["back"])
	var at_five: Dictionary = halos._gimbal_batch(_runs_at(halos, 5.0)["back"])
	assert_ne(at_zero["points"], at_five["points"], "control: those two clock values really do give different geometry")
	assert_gt(front["points"].size(), 0, "the front half has geometry")
	assert_eq(back["points"], at_zero["points"],
			"the back half is the front half's computation, memoised — not a second run")
	assert_ne(back["points"], at_five["points"], "...it did not recompute at the moved clock")


func test_the_gimbal_memo_is_stamped_per_frame_and_dropped_on_invalidation() -> void:
	var halos := await _make(HalosScript.CoreHaloStyle.GIMBAL)
	halos._redraw_all()
	assert_eq(halos._gimbal_frame, -1, "_redraw_all drops the memo, so a changed input is never served stale")

	halos.gimbal_layer_batch(true)
	assert_eq(halos._gimbal_frame, Engine.get_process_frames(),
			"the memo is stamped with the process frame it was computed on, so the next frame recomputes")


# — 4. the idempotent seams ————————————————————————————————————————————————————
#
# The layers are painted ONCE. The composite loop-sets all three identity
# values into every child whenever any one changes, and SkillNode._sync_visuals
# re-pushes configure(radius) wholesale; neither runs per frame today, but an
# unguarded repaint here would silently undo the whole fix the day one did.
# `_gimbal_frame` is the probe: _redraw_all() — the repaint — always resets it.

const _MEMO_SENTINEL := 123456


func test_re_pushing_an_unchanged_identity_does_not_repaint() -> void:
	var halos := await _make(HalosScript.CoreHaloStyle.COG)
	halos.entity_tint = Color(0.2, 0.6, 1.0)
	halos._gimbal_frame = _MEMO_SENTINEL

	halos.entity_tint = Color(0.2, 0.6, 1.0)
	assert_eq(halos._gimbal_frame, _MEMO_SENTINEL, "the same colour again is not a repaint")
	# archetype_tint and `allocated` are not inputs to anything CoreHalos draws.
	halos.archetype_tint = Color(1.0, 0.0, 0.0)
	halos.allocated = not halos.allocated
	assert_eq(halos._gimbal_frame, _MEMO_SENTINEL, "identities this component does not draw with cannot dirty it")

	halos.entity_tint = Color(1.0, 0.1, 0.1)
	assert_eq(halos._gimbal_frame, -1, "a genuinely different colour DOES repaint")


func test_re_pushing_an_unchanged_radius_does_not_repaint() -> void:
	var halos := await _make(HalosScript.CoreHaloStyle.COG)
	halos.configure(40.0)
	halos._gimbal_frame = _MEMO_SENTINEL

	halos.configure(40.0)
	assert_eq(halos._gimbal_frame, _MEMO_SENTINEL, "the same radius again is not a repaint")

	halos.configure(48.0)
	assert_eq(halos._gimbal_frame, -1, "a genuinely different radius DOES repaint")


func _runs_at(halos: Node2D, t: float) -> Dictionary:
	halos.anim_time = t
	return halos._gimbal_runs(halos.radius * halos.halo_scale, halos._halo_color)

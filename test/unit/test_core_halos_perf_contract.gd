extends GutTest
## Core-halos perf contract (#802). The halos measured 8.09ms of a 12.21ms idle
## frame on a 2000-node board with ONE of 307 on screen, and every millisecond
## of it was per-frame REBUILD, not draw. The fix is structural — rigid styles
## rotate instead of redrawing and invisible halos stop entirely.
##
## These tests exist because that fix is invisible to the eye: a refactor that
## silently reverted any of it would still LOOK correct and would still pass
## every other test in the suite, while putting the 8ms back. So each test pins
## the negative — "and it did NOT rebuild" — not just that the picture is right.
## [b]This file must never be gated on an idle machine.[/b] Every assertion here
## is STRUCTURAL — draw counts, rotation deltas, process flags, memo stamps —
## and not one of them is a wall-clock timing, so a co-tenant Godot process is
## not a confound. Verified empirically: the whole file goes green with the
## user's editor up and another worktree's GUT suite running alongside it.
##
## Naming the trap, because it is a deadlock rather than a slowdown: this repo
## is worked on with `godot --editor` open as a standing fixture, not a
## transient. So `pgrep -x godot` — which matches the process NAME and ignores
## the flags — can never go false, and any "wait for the machine to be quiet"
## loop built on it hangs until its timeout and then runs anyway, late. If you
## must serialise something, match the runner (`pgrep -f gut_cmdln`), and never
## `pkill -f`: that pattern matches your own command line and kills your shell.
##
## The standard: if an assertion in this file ever genuinely needs an idle
## machine, that assertion is flaky in normal use — fix it, don't wait it out.

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


func test_none_gets_no_spin_layers() -> void:
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


func test_the_on_screen_notifier_never_paints_its_editor_debug_rect() -> void:
	# The notifier is an engine node with an editor-only debug overlay: under
	# `Engine.is_editor_hint()` it draws its rect in translucent magenta, and the
	# sandbox tabs run INSIDE the editor process — so every core in the Spell
	# tab grew a purple AABB (#892). `show_rect` is the engine's off switch;
	# alpha-0 modulate is NOT an alternative (the cull pass bails on alpha before
	# it ever evaluates the visibility notifier, which would kill the #802 gate).
	var halos := await _make(HalosScript.CoreHaloStyle.COG)
	assert_not_null(halos._notifier, "a live halo owns its on-screen notifier")
	assert_false(halos._notifier.show_rect,
			"the notifier is an internal gate, never an editor overlay")


func test_an_unseen_halo_stops_processing_and_resumes_when_seen() -> void:
	var halos := await _make(HalosScript.CoreHaloStyle.COG)
	assert_true(halos.is_processing(), "a revealed halo animates")

	halos.revealed = false
	assert_false(halos.is_processing(),
			"neither revealed nor on screen — nobody can see it, so it must not rebuild (this is the fogged-node case)")

	halos.revealed = true
	assert_true(halos.is_processing(), "resumes when the fog lifts")

	halos.revealed = false
	halos._on_screen_changed(true)
	assert_true(halos.is_processing(), "on screen alone is enough — the two conditions are OR'd, not AND'ed")


func test_a_hidden_halo_never_animates_however_visible_it_claims_to_be() -> void:
	# visible-in-tree is AND'ed, not OR'ed: the composite hides CorePresence
	# for every non-core node, which is ~1700 of 2000 on a real board.
	var halos := await _make(HalosScript.CoreHaloStyle.COG)
	halos.revealed = true
	halos._on_screen_changed(true)
	assert_true(halos.is_processing(), "control: it is animating before we hide it")

	halos.visible = false
	await get_tree().process_frame
	assert_false(halos.is_processing(), "hidden outranks both revealed and on-screen")


# — 4. the idempotent seams ————————————————————————————————————————————————————
#
# The layers are painted ONCE. The composite loop-sets all three identity
# values into every child whenever any one changes, and SkillNode._sync_visuals
# re-pushes configure(radius) wholesale; neither runs per frame today, but an
# unguarded repaint here would silently undo the whole fix the day one did.
# The probe counts the spin layer's `draw` signal: a repaint re-enters _draw.


## Awaits two frames and returns how many times `layer` drew in them.
func _draws_after(layer: CanvasItem, change: Callable) -> int:
	var draws := [0]
	var count := func() -> void: draws[0] += 1
	layer.draw.connect(count)
	change.call()
	await get_tree().process_frame
	await get_tree().process_frame
	layer.draw.disconnect(count)
	return draws[0]


func test_re_pushing_an_unchanged_identity_does_not_repaint() -> void:
	var halos := await _make(HalosScript.CoreHaloStyle.COG)
	halos.entity_tint = Color(0.2, 0.6, 1.0)
	await get_tree().process_frame
	var layer: Node2D = halos._spin_layers[0]

	assert_eq(await _draws_after(layer, func() -> void: halos.entity_tint = Color(0.2, 0.6, 1.0)), 0,
		"the same colour again is not a repaint")
	# archetype_tint and `allocated` are not inputs to anything CoreHalos draws.
	assert_eq(await _draws_after(layer, func() -> void:
		halos.archetype_tint = Color(1.0, 0.0, 0.0)
		halos.allocated = not halos.allocated), 0,
		"identities this component does not draw with cannot dirty it")
	assert_gt(await _draws_after(layer, func() -> void: halos.entity_tint = Color(1.0, 0.1, 0.1)), 0,
		"a genuinely different colour DOES repaint")


func test_re_pushing_an_unchanged_radius_does_not_repaint() -> void:
	var halos := await _make(HalosScript.CoreHaloStyle.COG)
	halos.configure(40.0)
	await get_tree().process_frame
	var layer: Node2D = halos._spin_layers[0]

	assert_eq(await _draws_after(layer, func() -> void: halos.configure(40.0)), 0,
		"the same radius again is not a repaint")
	assert_gt(await _draws_after(layer, func() -> void: halos.configure(48.0)), 0,
		"a genuinely different radius DOES repaint")

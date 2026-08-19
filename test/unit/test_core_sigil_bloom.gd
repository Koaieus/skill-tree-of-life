extends GutTest
## The core-presence BLOOM component: additive blend + the animate gate. Draw
## quality is tuned in-editor; this pins the load-bearing wiring.

const BloomScene = preload("res://skill_node/visuals/emblem/core_sigil_bloom.tscn")
@warning_ignore("shadowed_global_identifier")
const StarSigil = preload("res://entity/core/sigil/star_sigil.gd")


func test_bloom_glows_additively() -> void:
	var b = BloomScene.instantiate()
	add_child_autofree(b)
	assert_not_null(b.material, "bloom binds a material")
	assert_eq(b.material.blend_mode, CanvasItemMaterial.BLEND_MODE_ADD, "bloom glows additively")


func test_bloom_animates_only_with_sigil_and_pulse() -> void:
	var b = BloomScene.instantiate()
	add_child_autofree(b)
	b.pulse_depth = 0.1
	assert_false(b.is_processing(), "no sigil → no animation clock")
	b.sigil = StarSigil.new()
	assert_true(b.is_processing(), "a pulsing bloom with a sigil runs its clock")
	b.pulse_depth = 0.0
	assert_false(b.is_processing(), "a steady (zero-pulse) beacon needs no clock")


func test_bloom_without_sigil_draws_nothing_safely() -> void:
	var b = BloomScene.instantiate()
	add_child_autofree(b)
	b.queue_redraw()
	assert_null(b.sigil, "default bloom is empty and must not crash on draw")

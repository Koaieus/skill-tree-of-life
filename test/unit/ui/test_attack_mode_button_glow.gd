extends GutTest

## Probe: does `active_strength` actually reach the Label's material?
##
## The text shader mixes toward `emissive_at(tint, TIER)` weighted by
## `color_t = active_strength * 0.8 + glow_strength * 0.35`. If the label
## renders as flat off-white in game, `color_t` is 0 — i.e. the push never
## landed on the material the Label is actually wearing.

const BUTTON := preload("res://ui/attack_mode_bar/attack_mode_button.tscn")


func _make() -> AttackModeButton:
	var b: AttackModeButton = BUTTON.instantiate()
	b.attack_mode = BattleSystem.AttackMode.RANGED
	add_child_autofree(b)
	return b


func test_active_reaches_the_label_material() -> void:
	var b := _make()
	await wait_frames(2)

	var lbl: Label = b.get_node("%Label")
	var mat: ShaderMaterial = lbl.material as ShaderMaterial
	assert_not_null(mat, "Label must wear a ShaderMaterial")
	gut.p("shader = %s" % [mat.shader])
	gut.p("tint (rest) = %s" % [mat.get_shader_parameter("tint")])
	gut.p("active (rest) = %s" % [mat.get_shader_parameter("active_strength")])

	b.override_toggle(true)
	await wait_seconds(0.4)

	var active_after: Variant = mat.get_shader_parameter("active_strength")
	gut.p("active (toggled) = %s" % [active_after])
	gut.p("tint (toggled) = %s" % [mat.get_shader_parameter("tint")])
	gut.p("bg active = %s" % [(b.get_node("ColorRect").material as ShaderMaterial)
			.get_shader_parameter("active_strength")])

	assert_eq(active_after, 1.0,
			"a toggled-on tab must push active_strength onto the LABEL's material")

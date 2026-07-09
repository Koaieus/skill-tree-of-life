extends GutTest

## `_MAX_CIRCLES` in the overlay scripts must equal `MAX_CIRCLES` in their
## shaders. The scripts pad the uniform array to their own constant; the shaders
## declare the array with theirs. If the script's is LARGER, `set_shader_parameter`
## silently drops the overflow. If it's SMALLER, the tail of the array is never
## written and reads as garbage from the previous frame.
##
## Neither failure raises an error, so nothing catches a desync but this.

const _AURA_SHADER_PATH := "res://ui/aura_overlay/aura.gdshader"
const _FOG_SHADER_PATH := "res://ui/fog_overlay/fog.gdshader"

const _AURA_SCENE := preload("res://ui/aura_overlay/aura_overlay.tscn")
const _FOG_SCENE := preload("res://ui/fog_overlay/fog_overlay.tscn")


## Pull `const int NAME = <int>;` out of a .gdshader's source text.
func _shader_const(path: String, name: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "shader source is readable at %s" % path)
	var src := f.get_as_text()
	var re := RegEx.new()
	re.compile("const\\s+int\\s+%s\\s*=\\s*(\\d+)\\s*;" % name)
	var m := re.search(src)
	assert_not_null(m, "%s declares `const int %s`" % [path, name])
	return int(m.get_string(1))


func test_aura_circle_cap_matches_its_shader() -> void:
	var overlay: AuraOverlay = _AURA_SCENE.instantiate()
	autofree(overlay)
	assert_eq(overlay._MAX_CIRCLES, _shader_const(_AURA_SHADER_PATH, "MAX_CIRCLES"),
		"AuraOverlay._MAX_CIRCLES must equal aura.gdshader's MAX_CIRCLES")


func test_aura_entity_cap_matches_its_shader() -> void:
	var overlay: AuraOverlay = _AURA_SCENE.instantiate()
	autofree(overlay)
	assert_eq(overlay._MAX_ENTITIES, _shader_const(_AURA_SHADER_PATH, "MAX_ENTITIES"),
		"AuraOverlay._MAX_ENTITIES must equal aura.gdshader's MAX_ENTITIES")


func test_fog_circle_cap_matches_its_shader() -> void:
	var overlay: FogOverlay = _FOG_SCENE.instantiate()
	autofree(overlay)
	assert_eq(overlay._MAX_CIRCLES, _shader_const(_FOG_SHADER_PATH, "MAX_CIRCLES"),
		"FogOverlay._MAX_CIRCLES must equal fog.gdshader's MAX_CIRCLES")


func test_caps_cover_a_realistic_late_game_board() -> void:
	# #133: the old 256 cap silently dropped territory once a few entities each
	# owned ~60 nodes. Planned scale is 50–100 owned nodes per entity.
	var fog: FogOverlay = _FOG_SCENE.instantiate()
	autofree(fog)
	assert_gte(fog._MAX_CIRCLES, 4 * 100,
		"four entities at 100 owned nodes must not truncate")


## `set_field` / `set_sources` are the entry points both the game and
## `scenes/overlay_perf_harness.tscn` drive (#133). They must pad the uniform
## arrays to the shader's declared length: a short array leaves the tail reading
## whatever the previous frame wrote, with no error.

func test_aura_set_field_pads_to_the_shader_array_length() -> void:
	var overlay: AuraOverlay = _AURA_SCENE.instantiate()
	autofree(overlay)
	overlay.set_field([Vector4(1.0, 2.0, 3.0, 0.0)], [Color.RED])
	var mat: ShaderMaterial = overlay.material
	assert_eq((mat.get_shader_parameter(&"circles") as Array).size(), overlay._MAX_CIRCLES,
		"circles must be padded to MAX_CIRCLES")
	assert_eq((mat.get_shader_parameter(&"entity_colors") as Array).size(), overlay._MAX_ENTITIES,
		"entity_colors must be padded to MAX_ENTITIES")
	assert_eq(mat.get_shader_parameter(&"circle_count"), 1)
	assert_eq(mat.get_shader_parameter(&"entity_count"), 1)


func test_aura_set_field_pads_with_transparent_black() -> void:
	# resize() on a typed Array[Color] yields OPAQUE black. If that leaks into
	# the padding, an unused entity slot is a solid colour waiting to render.
	var overlay: AuraOverlay = _AURA_SCENE.instantiate()
	autofree(overlay)
	overlay.set_field([Vector4(1.0, 2.0, 3.0, 0.0)], [Color.RED])
	var colors: Array = (overlay.material as ShaderMaterial).get_shader_parameter(&"entity_colors")
	assert_eq(colors[1], Color(0.0, 0.0, 0.0, 0.0), "padding must be fully transparent")


func test_aura_set_field_clamps_an_oversized_field() -> void:
	var overlay: AuraOverlay = _AURA_SCENE.instantiate()
	autofree(overlay)
	var circles: Array = []
	for i in overlay._MAX_CIRCLES + 50:
		circles.append(Vector4(float(i), 0.0, 10.0, 0.0))
	overlay.set_field(circles, [Color.RED])
	var mat: ShaderMaterial = overlay.material
	assert_eq((mat.get_shader_parameter(&"circles") as Array).size(), overlay._MAX_CIRCLES)
	assert_eq(mat.get_shader_parameter(&"circle_count"), overlay._MAX_CIRCLES,
		"count must never exceed the shader's array bound")


func test_fog_set_sources_pads_to_the_shader_array_length() -> void:
	var overlay: FogOverlay = _FOG_SCENE.instantiate()
	autofree(overlay)
	overlay.set_sources([{"pos": Vector2.ZERO, "radius": 100.0, "motion": 0.0}])
	var mat: ShaderMaterial = overlay.material
	assert_eq((mat.get_shader_parameter(&"circles") as Array).size(), overlay._MAX_CIRCLES)
	assert_eq(mat.get_shader_parameter(&"circle_count"), 1)

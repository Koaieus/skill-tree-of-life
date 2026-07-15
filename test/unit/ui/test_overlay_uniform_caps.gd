extends GutTest

## `_MAX_ENTITIES` in aura_overlay.gd must equal `MAX_ENTITIES` in aura.gdshader.
## `entity_colors` is still a plain uniform array (small — one Color per owning
## entity), so a desync there is the same silent-drop/stale-tail failure mode
## #133 originally guarded against.
##
## Circles moved off a fixed-size uniform array onto data textures in #177
## (see OverlayFieldTileIndex) specifically to remove this class of cap — there
## is no more `MAX_CIRCLES` shader const to desync against. `_MAX_CIRCLES` on
## both overlay scripts is now a sanity ceiling, not an array bound; the tests
## below check its loud-or-none truncation behaviour instead of a padded shape.

const _AURA_SHADER_PATH := "res://ui/aura_overlay/aura.gdshader"

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


func test_aura_entity_cap_matches_its_shader() -> void:
	var overlay: AuraOverlay = _AURA_SCENE.instantiate()
	autofree(overlay)
	assert_eq(overlay._MAX_ENTITIES, _shader_const(_AURA_SHADER_PATH, "MAX_ENTITIES"),
		"AuraOverlay._MAX_ENTITIES must equal aura.gdshader's MAX_ENTITIES")


func test_caps_cover_a_realistic_late_game_board() -> void:
	# #133 / #177: target scale is 20 entities owning up to 200 nodes each —
	# up to 4000 circles. The sanity ceiling must not truncate that.
	var fog: FogOverlay = _FOG_SCENE.instantiate()
	autofree(fog)
	assert_gte(fog._MAX_CIRCLES, 20 * 200,
		"20 entities at 200 owned nodes must not truncate")


func test_aura_entity_colors_pads_to_the_shader_array_length() -> void:
	var overlay: AuraOverlay = _AURA_SCENE.instantiate()
	autofree(overlay)
	overlay.set_field([Vector4(1.0, 2.0, 3.0, 0.0)], [Color.RED])
	var mat: ShaderMaterial = overlay.material
	assert_eq((mat.get_shader_parameter(&"entity_colors") as Array).size(), overlay._MAX_ENTITIES,
		"entity_colors must be padded to MAX_ENTITIES")
	assert_eq(mat.get_shader_parameter(&"circle_count"), 1)
	assert_eq(mat.get_shader_parameter(&"entity_count"), 1)


func test_aura_entity_colors_pads_with_transparent_black() -> void:
	# resize() on a typed Array[Color] yields OPAQUE black. If that leaks into
	# the padding, an unused entity slot is a solid colour waiting to render.
	var overlay: AuraOverlay = _AURA_SCENE.instantiate()
	autofree(overlay)
	overlay.set_field([Vector4(1.0, 2.0, 3.0, 0.0)], [Color.RED])
	var colors: Array = (overlay.material as ShaderMaterial).get_shader_parameter(&"entity_colors")
	assert_eq(colors[1], Color(0.0, 0.0, 0.0, 0.0), "padding must be fully transparent")


## Circles no longer live in a fixed-size uniform array (#177), so there is no
## shape to pad — `circle_count` just reports the true count and the tile index
## textures carry exactly that many circles.
func test_aura_set_field_uploads_the_full_circle_count() -> void:
	var overlay: AuraOverlay = _AURA_SCENE.instantiate()
	autofree(overlay)
	var circles: Array = []
	for i in 30:
		circles.append(Vector4(float(i) * 10.0, 0.0, 10.0, 0.0))
	overlay.set_field(circles, [Color.RED])
	var mat: ShaderMaterial = overlay.material
	assert_eq(mat.get_shader_parameter(&"circle_count"), 30,
		"count must not be clamped to any array bound below the sanity ceiling")
	assert_not_null(mat.get_shader_parameter(&"circles_tex"))
	assert_not_null(mat.get_shader_parameter(&"tile_index_tex"))
	assert_not_null(mat.get_shader_parameter(&"tile_indices_tex"))


func test_aura_set_field_clamps_only_at_the_sanity_ceiling() -> void:
	var overlay: AuraOverlay = _AURA_SCENE.instantiate()
	autofree(overlay)
	var circles: Array = []
	for i in overlay._MAX_CIRCLES + 50:
		circles.append(Vector4(float(i), 0.0, 10.0, 0.0))
	overlay.set_field(circles, [Color.RED])
	var mat: ShaderMaterial = overlay.material
	assert_eq(mat.get_shader_parameter(&"circle_count"), overlay._MAX_CIRCLES,
		"count must never exceed the sanity ceiling")


func test_fog_set_sources_uploads_the_full_circle_count() -> void:
	var overlay: FogOverlay = _FOG_SCENE.instantiate()
	autofree(overlay)
	overlay.set_sources([{"pos": Vector2.ZERO, "radius": 100.0, "motion": 0.0}])
	var mat: ShaderMaterial = overlay.material
	assert_eq(mat.get_shader_parameter(&"circle_count"), 1)
	assert_not_null(mat.get_shader_parameter(&"circles_tex"))
	assert_not_null(mat.get_shader_parameter(&"tile_index_tex"))
	assert_not_null(mat.get_shader_parameter(&"tile_indices_tex"))

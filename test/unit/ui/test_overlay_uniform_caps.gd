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

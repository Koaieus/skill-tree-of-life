extends GutTest

## #899 — the aura's per-entity tint must route through
## `Emissive.tint_damped`, not raw `Entity.color`, so a low-luminance hue
## (STR-red) doesn't wash out relative to a high-luminance one (INT-blue) at
## the same `intensity`.
##
## Asserts the *effect* (packed luminances end up closer together than the
## raw inputs' luminances) rather than a specific tier — the owner tunes the
## tier afterwards in the Bloom sandbox tab (Decisions, #899).

const _AURA_SCENE := preload("res://ui/aura_overlay/aura_overlay.tscn")

const _RED := Color(0.9, 0.2, 0.2)
const _BLUE := Color(0.25, 0.45, 0.95)

# Rec.709 luminance coefficients — same weights AuraOverlay's shader-facing
# colour pipeline is judged against (see Emissive._LUMA).
const _LUMA := Vector3(0.2126, 0.7152, 0.0722)


static func _luminance(c: Color) -> float:
	var lin := c.srgb_to_linear()
	return lin.r * _LUMA.x + lin.g * _LUMA.y + lin.b * _LUMA.z


func test_aura_tint_evens_out_luminance_across_hues() -> void:
	var world := TestWorld.create(self)
	var graph := world.graph
	var red_entity := world.add_entity("", null, null, _RED)
	var blue_entity := world.add_entity("", null, null, _BLUE)
	world.add_node().owned_by = red_entity
	world.add_node().owned_by = blue_entity

	var overlay: AuraOverlay = _AURA_SCENE.instantiate()
	add_child_autofree(overlay)
	overlay.graph = graph

	var mat: ShaderMaterial = overlay.material
	var packed: Array = mat.get_shader_parameter(&"entity_colors")
	var packed_red: Color = packed[0]
	var packed_blue: Color = packed[1]

	assert_ne(packed_red, _RED, "packed colour must not be the raw entity colour")
	assert_ne(packed_blue, _BLUE, "packed colour must not be the raw entity colour")

	# For the dev-sandbox colours the raw luminances already sit within ~2% of
	# each other (0.1935 vs 0.1971) — both below the 0.25 crossover where
	# `tint_damped`'s sqrt correction widens rather than narrows an ABSOLUTE
	# gap (sqrt's slope > 1 below 0.25; `packed = sqrt(raw) × 2^stops`, and
	# `2^stops` scales both sides equally so no tier choice fixes this). The
	# ratio (equivalently, distance in EV stops) is what `tint_damped` halves
	# exactly, tier-independent — that's the invariant to assert.
	var raw_lo := minf(_luminance(_RED), _luminance(_BLUE))
	var raw_hi := maxf(_luminance(_RED), _luminance(_BLUE))
	var packed_lo := minf(_luminance(packed_red), _luminance(packed_blue))
	var packed_hi := maxf(_luminance(packed_red), _luminance(packed_blue))
	var raw_ratio := raw_hi / raw_lo
	var packed_ratio := packed_hi / packed_lo
	assert_lt(packed_ratio, raw_ratio,
		"tint_damped must pull the two hues' luminances closer together (as a ratio) than the raw inputs")

extends GutTest

## Archetype (#310) — identity resources for the six hand-authored territories.
## Purely additive: nothing consumes Archetype yet, this is the lint for the
## six .tres files themselves.
##
## Doubles as a `.tres` strip lint (see `.claude/rules/godot-workflow.md`'s
## "Hand-authoring .tres" sections) — a wrong ext_resource uid silently
## resolves carve_shape to null with no parse error, so asserting non-null
## here is the only signal before it surfaces in gameplay.

const _ARCHETYPES: Array[String] = [
	"res://archetypes/strength.tres",
	"res://archetypes/dexterity.tres",
	"res://archetypes/intelligence.tres",
	"res://archetypes/wisdom.tres",
	"res://archetypes/perception.tres",
	"res://archetypes/constitution.tres",
]

## Expected shape per file, keyed the same order as _ARCHETYPES.
const _EXPECTED_SHAPE: Array[Dictionary] = [
	{"sides": 3, "squish_x": 1.0},
	{"sides": 4, "squish_x": 0.62},
	{"sides": 5, "squish_x": 1.0},
	{"sides": 6, "squish_x": 1.0},
	{"sides": 8, "squish_x": 1.0},
	{"sides": 12, "squish_x": 1.0},
]

## Colour separation threshold. The tightest legitimate pair among the six
## authored archetypes is intelligence vs perception at ≈0.44 RGB-euclidean;
## the pair that MUST be rejected — crit_chance Color(0.3, 0.8, 0.25) vs
## dexterity Color(0.319, 0.777, 0.448) — sits at ≈0.20. 0.30 sits cleanly
## between them.
const _MIN_TINT_SEPARATION: float = 0.30


func _load_all() -> Array[Archetype]:
	var out: Array[Archetype] = []
	for path in _ARCHETYPES:
		out.append(load(path) as Archetype)
	return out


func _rgb_distance(a: Color, b: Color) -> float:
	var dr := a.r - b.r
	var dg := a.g - b.g
	var db := a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)


func test_each_archetype_loads_with_a_non_null_carve_shape() -> void:
	for i in _ARCHETYPES.size():
		var arch: Archetype = load(_ARCHETYPES[i]) as Archetype
		assert_not_null(arch, "%s should load as an Archetype" % _ARCHETYPES[i])
		assert_not_null(arch.carve_shape, "%s: carve_shape must not be null (uid lint)" % _ARCHETYPES[i])
		var shape := arch.carve_shape as PolygonCarveShape
		assert_not_null(shape, "%s: carve_shape must be a PolygonCarveShape" % _ARCHETYPES[i])
		var expected: Dictionary = _EXPECTED_SHAPE[i]
		assert_eq(shape.sides, expected["sides"], "%s: unexpected sides" % _ARCHETYPES[i])
		assert_almost_eq(shape.squish_x, float(expected["squish_x"]), 0.001, "%s: unexpected squish_x" % _ARCHETYPES[i])


func test_color_is_derived_from_primary_stat_tint() -> void:
	for arch in _load_all():
		var def := StatRegistry.get_def(arch.primary_stat)
		assert_not_null(def, "%s: primary_stat %s must resolve in StatRegistry" % [arch.id, arch.primary_stat])
		assert_eq(arch.color, def.tint_color, "%s: color must equal its primary stat's tint_color" % arch.id)


func test_primary_stat_is_non_empty_and_resolves() -> void:
	for arch in _load_all():
		assert_ne(arch.primary_stat, &"", "%s: primary_stat must not be empty" % arch.id)
		assert_not_null(StatRegistry.get_def(arch.primary_stat), "%s: primary_stat %s unresolved" % [arch.id, arch.primary_stat])


func test_exactly_one_archetype_per_primary_stat() -> void:
	var seen_stats: Dictionary = {}
	for arch in _load_all():
		assert_false(seen_stats.has(arch.primary_stat), "duplicate primary_stat: %s" % arch.primary_stat)
		seen_stats[arch.primary_stat] = true
	assert_eq(seen_stats.size(), _ARCHETYPES.size())


func test_no_duplicate_ids() -> void:
	var seen_ids: Dictionary = {}
	for arch in _load_all():
		assert_false(seen_ids.has(arch.id), "duplicate id: %s" % arch.id)
		seen_ids[arch.id] = true


func test_tints_are_pairwise_distinguishable() -> void:
	var archetypes := _load_all()
	for i in archetypes.size():
		for j in range(i + 1, archetypes.size()):
			var a := archetypes[i]
			var b := archetypes[j]
			var dist := _rgb_distance(a.color, b.color)
			assert_true(dist >= _MIN_TINT_SEPARATION,
					"%s vs %s: tint separation %.3f below threshold %.2f (crit_chance/dexterity collide at ≈0.20 — this guards against that shape of bug)" % [a.id, b.id, dist, _MIN_TINT_SEPARATION])

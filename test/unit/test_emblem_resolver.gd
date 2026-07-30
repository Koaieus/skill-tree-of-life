extends GutTest
## Emblem contribution → resolution: the priority ladder and register split that
## let a SkillNode show one central carve (keystone > loot > spell > archetype)
## while core-presence blooms ride alongside it. See docs/domain/skillnode-emblem.md.

const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")
const EmblemResolver = preload("res://skill_node/visuals/emblem/emblem_resolver.gd")
const PolygonCarveShape = preload("res://skill_node/visuals/emblem/polygon_carve_shape.gd")
const GemCarveShape = preload("res://skill_node/visuals/emblem/gem_carve_shape.gd")


## A shapeless CARVE at a rung — what a keystone/spell with no `carve_shape`
## authored contributes. The ladder is about rungs, not about having a shape.
func _shapeless(prio: int, source: StringName) -> EmblemSpec:
	return EmblemSpec.carve(null, prio, source)


func _polygon(sides: int, prio: int, source: StringName) -> EmblemSpec:
	var shape := PolygonCarveShape.new()
	shape.sides = sides
	return shape.carve(prio, source)


func test_keystone_outranks_everything() -> void:
	var arch := _polygon(3, EmblemSpec.Priority.ARCHETYPE, &"archetype")
	var spell := _shapeless(EmblemSpec.Priority.SPELL, &"spell")
	var loot := _shapeless(EmblemSpec.Priority.LOOT, &"loot")
	var keystone := _shapeless(EmblemSpec.Priority.KEYSTONE, &"keystone")
	var res := EmblemResolver.resolve([arch, spell, loot, keystone])
	assert_eq(res.carve.source_kind, &"keystone", "keystone (bespoke) wins the carve")


func test_loot_overrides_spell() -> void:
	var spell := _shapeless(EmblemSpec.Priority.SPELL, &"spell")
	var loot := _shapeless(EmblemSpec.Priority.LOOT, &"loot")
	var res := EmblemResolver.resolve([spell, loot])
	assert_eq(res.carve.source_kind, &"loot", "a consumed one-off loot glyph overrides a spell grant")


func test_archetype_is_the_fallback() -> void:
	var arch := _polygon(4, EmblemSpec.Priority.ARCHETYPE, &"archetype")
	var res := EmblemResolver.resolve([arch])
	assert_eq(res.carve.source_kind, &"archetype", "archetype shows when nothing else claims the carve")


func test_empty_dome_when_no_carve() -> void:
	var res := EmblemResolver.resolve([])
	assert_null(res.carve, "no contributions → empty dome (the #131 default)")


func test_co_priority_spells_collected_for_combine() -> void:
	var a := _shapeless(EmblemSpec.Priority.SPELL, &"spell")
	var b := _shapeless(EmblemSpec.Priority.SPELL, &"spell")
	var res := EmblemResolver.resolve([a, b])
	assert_eq(res.carve_ties.size(), 2, "tied spells collected so the renderer can combine/alternate")


func test_bloom_rides_alongside_carve() -> void:
	var arch := _polygon(3, EmblemSpec.Priority.ARCHETYPE, &"archetype")
	var bloom := EmblemSpec.sigil_bloom(null, &"core")
	var res := EmblemResolver.resolve([bloom, arch])
	assert_eq(res.carve.source_kind, &"archetype", "bloom is a separate register, never wins the carve")
	assert_eq(res.blooms.size(), 1, "core bloom rendered additively over the carve")


func test_null_contributions_ignored() -> void:
	var arch := _polygon(6, EmblemSpec.Priority.ARCHETYPE, &"archetype")
	var res := EmblemResolver.resolve([null, arch, null])
	assert_eq(res.carve.source_kind, &"archetype", "null contributions are skipped, not fatal")


func test_archetype_shape_owns_its_sides() -> void:
	var str_arch: Archetype = load("res://archetypes/strength.tres")
	var str_carve := str_arch.carve_shape.carve(EmblemSpec.Priority.ARCHETYPE, &"archetype")
	assert_eq(str_carve.shape.sides, 3, "STR is a triangle")
	var con_arch: Archetype = load("res://archetypes/constitution.tres")
	var con_carve := con_arch.carve_shape.carve(EmblemSpec.Priority.ARCHETYPE, &"archetype")
	assert_eq(con_carve.shape.sides, 12, "CON is a dodecagon")
	assert_eq(str_carve.priority, EmblemSpec.Priority.ARCHETYPE, "archetype carve sits at the fallback priority")


func test_dex_shape_is_a_squished_diamond() -> void:
	var dex_arch: Archetype = load("res://archetypes/dexterity.tres")
	var dex_carve := dex_arch.carve_shape.carve(EmblemSpec.Priority.ARCHETYPE, &"archetype")
	assert_eq(dex_carve.shape.sides, 4, "DEX is a diamond (a squished 4-gon)")
	assert_lt(dex_carve.shape.squish_x, 1.0, "squished from the sides, not a plain square")


func test_gem_carve_carries_the_gem_shape() -> void:
	var gem := GemCarveShape.SHARED.carve(EmblemSpec.Priority.LOOT, &"loot")
	assert_true(gem.shape is GemCarveShape, "the spec IS the shape, not an enum naming it")
	var res := EmblemResolver.resolve([gem])
	assert_eq(res.carve.source_kind, &"loot")


## D5's non-1:1 case: source_kind and priority are two independent fields, so
## two different sources can legitimately share one rung. node_visuals_composite
## contributes &"authored" at ARCHETYPE priority — the same rung the archetype
## fallback itself uses. Collapsing the ladder into source_kind would break this.
func test_priority_rung_is_shareable_across_source_kinds() -> void:
	var authored := _polygon(5, EmblemSpec.Priority.ARCHETYPE, &"authored")
	var archetype := _polygon(3, EmblemSpec.Priority.ARCHETYPE, &"archetype")
	assert_eq(authored.priority, archetype.priority, "one rung, two source kinds")
	assert_ne(authored.source_kind, archetype.source_kind)
	var res := EmblemResolver.resolve([authored, archetype])
	assert_eq(res.carve_ties.size(), 2, "a shared rung ties rather than one silently winning")

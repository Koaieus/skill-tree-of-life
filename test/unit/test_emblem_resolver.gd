extends GutTest
## Emblem contribution → resolution: the priority ladder and register split that
## let a SkillNode show one central carve (keystone > loot > spell > archetype)
## while core-presence blooms ride alongside it. See SKILLNODE_EMBLEM_HANDOFF.md.

const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")
const EmblemResolver = preload("res://skill_node/visuals/emblem/emblem_resolver.gd")
const ArchetypeShape = preload("res://skill_node/visuals/emblem/archetype_shape.gd")


func test_keystone_outranks_everything() -> void:
	var arch := EmblemSpec.polygon_carve(3, EmblemSpec.PRIORITY_ARCHETYPE, &"archetype")
	var spell := EmblemSpec.texture_carve(null, EmblemSpec.PRIORITY_SPELL, &"spell")
	var loot := EmblemSpec.texture_carve(null, EmblemSpec.PRIORITY_LOOT, &"loot")
	var keystone := EmblemSpec.texture_carve(null, EmblemSpec.PRIORITY_KEYSTONE, &"keystone")
	var res := EmblemResolver.resolve([arch, spell, loot, keystone])
	assert_eq(res.carve.source_kind, &"keystone", "keystone (bespoke) wins the carve")


func test_loot_overrides_spell() -> void:
	var spell := EmblemSpec.texture_carve(null, EmblemSpec.PRIORITY_SPELL, &"spell")
	var loot := EmblemSpec.texture_carve(null, EmblemSpec.PRIORITY_LOOT, &"loot")
	var res := EmblemResolver.resolve([spell, loot])
	assert_eq(res.carve.source_kind, &"loot", "a consumed one-off loot glyph overrides a spell grant")


func test_archetype_is_the_fallback() -> void:
	var arch := EmblemSpec.polygon_carve(4, EmblemSpec.PRIORITY_ARCHETYPE, &"archetype")
	var res := EmblemResolver.resolve([arch])
	assert_eq(res.carve.source_kind, &"archetype", "archetype shows when nothing else claims the carve")


func test_empty_dome_when_no_carve() -> void:
	var res := EmblemResolver.resolve([])
	assert_null(res.carve, "no contributions → empty dome (the #131 default)")


func test_co_priority_spells_collected_for_combine() -> void:
	var a := EmblemSpec.texture_carve(null, EmblemSpec.PRIORITY_SPELL, &"spell")
	var b := EmblemSpec.texture_carve(null, EmblemSpec.PRIORITY_SPELL, &"spell")
	var res := EmblemResolver.resolve([a, b])
	assert_eq(res.carve_ties.size(), 2, "tied spells collected so the renderer can combine/alternate")


func test_bloom_rides_alongside_carve() -> void:
	var arch := EmblemSpec.polygon_carve(3, EmblemSpec.PRIORITY_ARCHETYPE, &"archetype")
	var bloom := EmblemSpec.sigil_bloom(null, &"core")
	var res := EmblemResolver.resolve([bloom, arch])
	assert_eq(res.carve.source_kind, &"archetype", "bloom is a separate register, never wins the carve")
	assert_eq(res.blooms.size(), 1, "core bloom rendered additively over the carve")


func test_null_contributions_ignored() -> void:
	var arch := EmblemSpec.polygon_carve(6, EmblemSpec.PRIORITY_ARCHETYPE, &"archetype")
	var res := EmblemResolver.resolve([null, arch, null])
	assert_eq(res.carve.source_kind, &"archetype", "null contributions are skipped, not fatal")


func test_archetype_shape_owns_its_sides() -> void:
	var str_carve := ArchetypeShape.carve(ArchetypeShape.Archetype.STR)
	assert_eq(str_carve.polygon_sides, 3, "STR is a triangle")
	var con_carve := ArchetypeShape.carve(ArchetypeShape.Archetype.CON)
	assert_eq(con_carve.polygon_sides, 12, "CON is a dodecagon")
	assert_eq(str_carve.priority, EmblemSpec.PRIORITY_ARCHETYPE, "archetype carve sits at the fallback priority")

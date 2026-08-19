extends GutTest

## CON territory exists in the shipped level preset (#299).
##
## #269 authored CON's StatDef, board wiring and `procgen/pools/constitution.tres`,
## but neither bundled the pack into `specimen_pool_set.tres` nor gave CON an
## `ArchetypePolicy` — so no generated node ever had `primary_stat = constitution`
## and CON content was unreachable. Both halves are fixed; this is the guard.
##
## Doubles as a `.tres` strip lint. Per `.claude/rules/godot-workflow.md` an
## editor round-trip can silently drop sub-resources from a `.tres` with no parse
## error — the symptom is a null field or a short array, not a crash. Asserting
## on the loaded resource is the only signal before it surfaces in gameplay.

const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")

## CON is "a full fifth attribute, alongside STR/DEX/INT" (D-11), so it belongs
## to the combat-peer regime rather than the far smaller specialist share WIS/PER
## use. Its exact share is a balance knob still in flight, so we guard the
## regime boundary (clearly above the specialists) instead of pinning a number.
## Ratios are NORMALISED at read time (GraphProcgen "target counts per archetype
## (normalised target_ratio)" and ArchetypeBalancer.pick's `/ total_target`), so
## this is a relative share, not an absolute one — the peers summing past 1.0 is
## fine and expected.
const _PEER_RATIO := 0.3


func _archetypes() -> Array[ArchetypePolicy]:
	var cfg: GraphProcgenConfig = _PRESET.duplicate(true) as GraphProcgenConfig
	return cfg.archetypes


func _policy_for(stat: StringName) -> ArchetypePolicy:
	for a in _archetypes():
		if a != null and a.primary_stat == stat:
			return a
	return null


func test_preset_carries_a_constitution_archetype() -> void:
	var con := _policy_for(&"constitution")
	assert_not_null(con, "first_level.tres must carry an ArchetypePolicy with primary_stat = constitution")
	assert_eq(con.id, &"white", "CON's archetype is the white territory")


func test_constitution_shares_the_combat_peer_regime() -> void:
	var con := _policy_for(&"constitution")
	assert_not_null(con)
	# CON sits in the full-attribute regime, not the specialist one: its share
	# must clearly exceed the largest WIS/PER specialist share. The exact value
	# is a balance knob (still in flight), so this only pins the boundary.
	var specialist_max := 0.0
	for a in _archetypes():
		if a != null and a.primary_stat in [&"wisdom", &"perception"]:
			specialist_max = max(specialist_max, a.target_ratio)
	assert_gt(con.target_ratio, specialist_max,
			"CON's share must sit in the combat-peer regime, above the WIS/PER specialist shares")
	for peer in [&"strength", &"dexterity", &"intelligence"]:
		var p := _policy_for(peer)
		assert_not_null(p, "combat peer %s should still have a policy" % peer)
		assert_almost_eq(p.target_ratio, _PEER_RATIO, 0.001,
				"%s's share must not have been disturbed by adding CON" % peer)


func test_every_attribute_has_exactly_one_archetype() -> void:
	# Strip lint: a dropped sub_resource shows up here as a missing attribute,
	# and a duplicated ext_resource id as a count > 1.
	for stat in [&"strength", &"dexterity", &"intelligence", &"constitution", &"wisdom", &"perception"]:
		var matches := 0
		for a in _archetypes():
			if a != null and a.primary_stat == stat:
				matches += 1
		assert_eq(matches, 1, "expected exactly one archetype for %s" % stat)


func test_no_archetype_is_null_or_statless() -> void:
	var list := _archetypes()
	assert_eq(list.size(), 6, "six archetypes: STR/DEX/INT/CON combat peers + WIS/PER specialists")
	for a in list:
		assert_not_null(a, "a null entry means a sub_resource was stripped from the preset")
		assert_not_null(a.archetype, "every policy must carry its Archetype resource (a stripped ext_resource shows up here)")
		assert_ne(String(a.primary_stat), "", "every archetype must name a primary_stat")
		assert_not_null(StatRegistry.get_def(a.primary_stat),
				"primary_stat %s must resolve in StatRegistry, not just be non-empty" % a.primary_stat)

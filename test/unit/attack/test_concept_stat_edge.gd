extends GutTest
## The concept→stat edge is read off StatDef.role (ADR 0054), never spelled.

const _STATUSES := preload("res://effects/status_roster.tres")


func test_status_ids_derive_from_the_facets() -> void:
	for d in _STATUSES.statuses:
		if d.identity == null:
			continue
		var res := StatRegistry.facet_def(d.identity.id, StatDef.Role.RESISTANCE)
		var stk := StatRegistry.facet_def(d.identity.id, StatDef.Role.STACKS_PER_HIT)
		assert_eq(d.resistance_stat_id(), res.id if res != null else &"", d.id)
		assert_eq(d.stacks_stat_id(), stk.id if stk != null else &"", d.id)


func test_poison_has_both_and_scout_only_stacks() -> void:
	var poison := load("res://effects/status/poison.tres") as StatusDef
	assert_eq(poison.resistance_stat_id(), &"poison_resistance")
	assert_eq(poison.stacks_stat_id(), &"poison_stacks_per_hit")
	var scout := load("res://effects/status/scouted.tres") as StatusDef
	assert_eq(scout.resistance_stat_id(), &"")
	assert_eq(scout.stacks_stat_id(), &"scout_stacks_per_hit")


func test_ammo_per_reload_ids() -> void:
	var roster := load("res://attack/ammo/ammo_type_roster.tres") as AmmoTypeRoster
	for t in roster.types:
		if t.id == AmmoTypeRoster.BASE_ID:
			assert_eq(t.per_reload_stat_id(), &"arrows_per_reload")
		else:
			assert_eq(t.per_reload_stat_id(), StatRegistry.facet_def(t.id, StatDef.Role.ASPECT).id, t.id)


func test_aspect_currency_stat_of() -> void:
	assert_eq(AspectCurrency.stat_of(&"poison"), &"poison_aspect")
	assert_eq(AspectCurrency.stat_of(&"nonesuch"), &"")
	assert_eq(AspectCurrency.cap_of(null, AspectCurrency.stat_of(&"nonesuch")), 0)

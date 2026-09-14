extends GutTest

## StatusDef (#872) — a shared, stateless resource: enums, defaults and the
## derived description. Behaviour lives on NodeCombat's slice, tested in
## test_node_combat_status.gd.


func test_defaults() -> void:
	var d := StatusDef.new()
	assert_eq(d.reapply, StatusDef.Reapply.REFRESH)
	assert_eq(d.on_dealloc, StatusDef.OnDealloc.CLEAR)
	assert_eq(d.power_max, 1.0)
	assert_eq(d.decay_per_tick, 1.0)
	assert_eq(d.cure_per_hp, 0.0)
	assert_null(d.icon)
	assert_eq(d.tint, Color.WHITE)


func test_description_prefers_authored_prose() -> void:
	var d := StatusDef.new()
	d.description = "Rots the node."
	assert_eq(d.get_description(), "Rots the node.")


func test_description_derives_from_numbers_when_blank() -> void:
	var d := StatusDef.new()
	d.id = &"poison"
	d.display_name = "Poison"
	d.power_max = 5.0
	d.decay_per_tick = 1.0
	assert_eq(d.get_description(), "Poison (max 5, -1 per turn)")


func test_description_falls_back_to_id_without_display_name() -> void:
	var d := StatusDef.new()
	d.id = &"blind"
	assert_true(d.get_description().begins_with("blind"), d.get_description())


func test_base_hooks_are_inert() -> void:
	var d := StatusDef.new()
	var n := NodeCombat.new()
	d._on_applied(n, 1.0)
	d._on_tick(n, 1.0, 0.0)
	d._on_removed(n)
	pass_test("base hooks are no-ops")

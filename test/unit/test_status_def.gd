extends GutTest

## StatusDef (#872) — a shared, stateless resource: enums, defaults and the
## derived description. Behaviour lives on NodeCombat's slice, tested in
## test_node_combat_status.gd.


func test_defaults() -> void:
	var d := StatusDef.new()
	assert_eq(d.reapply, StatusDef.Reapply.REFRESH)
	assert_eq(d.on_dealloc, StatusDef.OnDealloc.CLEAR)
	assert_eq(d.power_max, 1.0)
	assert_eq((d.decay as FlatDecay).per_tick, 1.0, "flat 1 by default")
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
	d.decay = FlatDecay.new(1.0)
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


## A duck-typed [StatusHost] owner: the slice contract a restore touches.
class StubOwner:
	extends RefCounted
	func is_allocated() -> bool:
		return true
	func get_local_value(_id: StringName) -> Variant:
		return null
	func _on_first_status() -> void:
		pass
	func _on_statuses_changed() -> void:
		pass
	func _on_pile_rose(_def, _key) -> void:
		pass


## Journals `_on_applied` only: a restore falls back to it.
class AppliedSpy:
	extends StatusDef
	var applied: int = 0
	func _on_applied(_host, _power: float) -> void:
		applied += 1


## Overrides `_on_restored`: a restore calls it INSTEAD of `_on_applied`.
class RestoredSpy:
	extends AppliedSpy
	var restored: int = 0
	func _on_restored(_host, _power: float) -> void:
		restored += 1


func test_on_restored_is_a_base_virtual() -> void:
	assert_true(StatusDef.new().has_method(&"_on_restored"), "StatusDef declares _on_restored")


func test_restore_calls_an_overriding_defs_on_restored_instead_of_on_applied() -> void:
	var o := StubOwner.new()
	var d := RestoredSpy.new()
	d.id = &"spy_restored"
	StatusHost.new(o).restore_row(d, 1.0, true)
	assert_eq(d.restored, 1, "_on_restored ran once")
	assert_eq(d.applied, 0, "_on_applied did not run")


func test_restore_hands_a_plain_def_to_on_applied() -> void:
	var o := StubOwner.new()
	var d := AppliedSpy.new()
	d.id = &"spy_applied"
	StatusHost.new(o).restore_row(d, 1.0, true)
	assert_eq(d.applied, 1, "_on_applied ran once")


func test_base_on_restored_reaches_on_applied() -> void:
	var d := AppliedSpy.new()
	d._on_restored(null, 1.0)
	assert_eq(d.applied, 1, "the default _on_restored is _on_applied")

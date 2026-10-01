extends GutTest

## The spread slot's shared machinery (#1259): [method StatusHost.adjust_power]
## is the one primitive the three callers and [SpreadApplier] land through;
## [SpreadApplier] debits every `from` then credits every `to`, conserving
## all but the burned (null-`to`) amounts; [StackField] filters neighbours by
## [member StatusSpread.ownership_mask] as seen by the HOST node's owner.


## A def that counts its hooks per host.
class CountingDef:
	extends StatusDef
	var applied: Dictionary = {}
	var removed: Dictionary = {}

	func _on_applied(host, _power: float) -> void:
		applied[host] = int(applied.get(host, 0)) + 1

	func _on_removed(host) -> void:
		removed[host] = int(removed.get(host, 0)) + 1

	func reset() -> void:
		applied.clear()
		removed.clear()


class InertSpread:
	extends StatusSpread


var _me: Entity
var _ally: Entity
var _foe: Entity


func before_each() -> void:
	_me = autofree(Entity.new())
	_ally = autofree(Entity.new())  # same default faction → ALLIED
	_foe = autofree(Entity.new())
	var rogue := Faction.new()
	rogue.id = &"rogue"
	_foe.faction = rogue


func _node(owner: Entity) -> NodeCombat:
	var sn: SkillNode = autofree(SkillNode.new())
	sn.owned_by = owner
	return sn.get_combat()


func _def(power_max: float = 0.0) -> CountingDef:
	var d := CountingDef.new()
	d.id = &"spready"
	d.power_max = power_max
	d.reapply = StatusDef.Reapply.ACCUMULATE
	return d


# ── adjust_power ────────────────────────────────────────────────────────────

func test_adjust_power_creates_an_absent_row_and_runs_on_applied() -> void:
	var d := _def(5.0)
	var n := _node(_me)
	n.adjust_status_power(d, 3.0)
	assert_eq(n.get_status_power(d.id), 3.0, "row created at +3")
	assert_eq(d.applied.get(n, 0), 1, "_on_applied ran once")


func test_adjust_power_clamps_to_power_max() -> void:
	var d := _def(5.0)
	var n := _node(_me)
	n.adjust_status_power(d, 3.0)
	n.adjust_status_power(d, 10.0)
	assert_eq(n.get_status_power(d.id), 5.0, "clamped to power_max")


func test_adjust_power_down_to_zero_removes_the_row() -> void:
	var d := _def(5.0)
	var n := _node(_me)
	n.adjust_status_power(d, 3.0)
	d.reset()
	n.adjust_status_power(d, -3.0)
	assert_eq(n.get_statuses().size(), 0, "row removed")
	assert_eq(d.removed.get(n, 0), 1, "_on_removed ran once")
	assert_eq(d.applied.get(n, 0), 0, "no _on_applied on removal")


func test_adjust_power_negative_on_absent_row_is_a_no_op() -> void:
	var d := _def()
	var n := _node(_me)
	n.adjust_status_power(d, -2.0)
	assert_eq(n.get_statuses().size(), 0, "nothing created")
	assert_eq(d.removed.get(n, 0), 0, "nothing removed")


# ── SpreadApplier ───────────────────────────────────────────────────────────

func test_applier_conserves_all_but_burned_stacks() -> void:
	var d := _def()
	var a := _node(_me)
	var b := _node(_me)
	var c := _node(_me)
	var e := _node(_me)
	a.apply_status(d, 10.0)
	b.apply_status(d, 6.0)
	d.reset()
	var transfers: Array[StackTransfer] = [
		StackTransfer.new(a, b, 3.0),
		StackTransfer.new(a, c, 2.0),
		StackTransfer.new(b, null, 1.0),
		StackTransfer.new(b, e, 4.0),
		StackTransfer.new(a, e, 1.0),
	]
	SpreadApplier.apply(d, transfers, CombatWorld.live())
	var total := 0.0
	for n in [a, b, c, e]:
		total += n.get_status_power(d.id)
	assert_eq(total, 15.0, "16 stacks less the 1 burned")
	assert_eq(a.get_status_power(d.id), 4.0, "a debited 6")
	assert_eq(b.get_status_power(d.id), 4.0, "b: 6 - 5 + 3")
	assert_eq(c.get_status_power(d.id), 2.0, "c credited 2")
	assert_eq(e.get_status_power(d.id), 5.0, "e credited 4 + 1")
	assert_eq(d.applied.get(c, 0), 1, "c: one _on_applied for one transfer")
	assert_eq(d.applied.get(e, 0), 2, "e: one _on_applied per transfer")


func test_applier_debits_before_crediting() -> void:
	# Simultaneous moves, not a chain: b's own 2 leave before a's 4 arrive, so
	# b's row is removed and recreated rather than passed through.
	var d := _def()
	var a := _node(_me)
	var b := _node(_me)
	var c := _node(_me)
	a.apply_status(d, 4.0)
	b.apply_status(d, 2.0)
	var transfers: Array[StackTransfer] = [
		StackTransfer.new(a, b, 4.0),
		StackTransfer.new(b, c, 2.0),
	]
	SpreadApplier.apply(d, transfers, CombatWorld.live())
	assert_eq(a.get_status_power(d.id), 0.0, "a emptied")
	assert_eq(b.get_status_power(d.id), 4.0, "b emptied, then credited 4")
	assert_eq(c.get_status_power(d.id), 2.0, "c credited 2")
	assert_eq(d.removed.get(b, 0), 1, "b's row left before the credit recreated it")


func test_a_credit_onto_an_unallocated_host_is_voided_for_a_clear_def() -> void:
	var d := _def()
	var a := _node(_me)
	var loose := _node(null)
	a.apply_status(d, 4.0)
	var transfers: Array[StackTransfer] = [StackTransfer.new(a, loose, 3.0)]
	SpreadApplier.apply(d, transfers, CombatWorld.live())
	assert_eq(a.get_status_power(d.id), 1.0, "a debited")
	assert_eq(loose.get_statuses().size(), 0, "CLEAR gate: no row on an unallocated host")


# ── StackField ──────────────────────────────────────────────────────────────

func _star(center_owner: Entity) -> Dictionary:
	var centre := _node(center_owner)
	var mine := _node(_me)
	var ally := _node(_ally)
	var foe := _node(_foe)
	var neutral := _node(null)
	return {
		"centre": centre, "mine": mine, "ally": ally, "foe": foe, "neutral": neutral,
		"adjacency": {centre: [mine, ally, foe, neutral]},
	}


func _masked(star: Dictionary, mask: int) -> Array:
	var field := StackField.new(_def(), mask, star["adjacency"])
	var names: Array = []
	for n in field.masked_neighbours(star["centre"]):
		for k in ["mine", "ally", "foe", "neutral"]:
			if star[k] == n:
				names.append(k)
	names.sort()
	return names


func test_masked_neighbours_honours_each_mask_from_the_hosts_owner() -> void:
	var star := _star(_me)
	assert_eq(_masked(star, SkillNode.Ownership.MINE), ["mine"], "Mine")
	assert_eq(_masked(star, SkillNode.Ownership.MINE | SkillNode.Ownership.ALLY), ["ally", "mine"], "Friendly")
	assert_eq(_masked(star, SkillNode.Ownership.HOSTILE), ["foe"], "Hostile")
	assert_eq(_masked(star, SkillNode.Ownership.NEUTRAL), ["neutral"], "Neutral")


func test_masked_neighbours_is_seen_by_the_host_nodes_owner() -> void:
	var star := _star(_foe)
	assert_eq(_masked(star, SkillNode.Ownership.MINE), ["foe"], "the foe's own node is Mine to it")
	assert_eq(_masked(star, SkillNode.Ownership.HOSTILE), ["ally", "mine"], "ours are Hostile to it")


func test_masked_neighbours_of_an_unowned_host() -> void:
	var star := _star(null)
	assert_eq(_masked(star, SkillNode.Ownership.MINE | SkillNode.Ownership.ALLY), [], "no one to be Mine or Ally to")
	assert_eq(_masked(star, SkillNode.Ownership.NEUTRAL), ["neutral"], "Neutral")
	assert_eq(_masked(star, SkillNode.Ownership.HOSTILE), ["ally", "foe", "mine"], "every owned node reads Hostile")


func test_field_stacks_read_the_raw_row() -> void:
	var d := _def()
	var n := _node(_me)
	n.apply_status(d, 7.0)
	var field := StackField.new(d, SkillNode.Ownership.MINE, {n: []})
	assert_eq(field.stacks(n), 7.0, "raw stacks")


# ── the slot ────────────────────────────────────────────────────────────────

func test_spread_slot_defaults_to_null_and_signature_to_no_transfers() -> void:
	assert_null(StatusDef.new().spread, "null slot: never spreads")
	var s := InertSpread.new()
	assert_eq(s.ownership_mask, SkillNode.Ownership.MINE, "mask defaults to Mine")
	var field := StackField.new(_def(), s.ownership_mask, {})
	assert_eq(s.on_tick(field).size(), 0, "on_tick: no transfers")
	assert_eq(s.on_removed(field, [_node(_me)] as Array[NodeCombat], StatusSpread.CAUSE_DEATH).size(), 0, "on_removed: no transfers")

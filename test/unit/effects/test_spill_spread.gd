extends GutTest

## [SpillSpread] (#1261): a removed node spills its raw stacks onto its own
## direct masked neighbours that survive the beat (outside the removed
## union, judged pre-removal); no survivor burns the lot. Share =
## `floor(floor(S * spread_fraction) / k)` per survivor, the remainder voided.
## Fields here are built straight from a dictionary adjacency (unit-tier, no
## [CombatWorld]).

var _me: Entity
var _ally: Entity
var _foe: Entity


func before_each() -> void:
	_me = autofree(Entity.new())
	_ally = autofree(Entity.new())
	_foe = autofree(Entity.new())
	var rogue := Faction.new()
	rogue.id = &"rogue"
	_foe.faction = rogue


func _node(owner: Entity) -> NodeCombat:
	var sn: SkillNode = autofree(SkillNode.new())
	sn.owned_by = owner
	return sn.get_combat()


func _def() -> StatusDef:
	var d := StatusDef.new()
	d.id = &"spilly"
	d.power_max = 0.0  # uncapped
	d.reapply = StatusDef.Reapply.ACCUMULATE
	return d


func _field(def: StatusDef, adjacency: Dictionary, mask: int = SkillNode.Ownership.MINE) -> StackField:
	return StackField.new(def, mask, adjacency)


func _find(transfers: Array[StackTransfer], from: NodeCombat, to) -> StackTransfer:
	for t in transfers:
		if t.from == from and t.to == to:
			return t
	return null


# ── the chain: 1C–2–3X–4–5–6#–7, removing {3,4,5,6,7} ───────────────────────

func test_chain_curse_on_6_vanishes_curse_on_3_goes_to_2_only() -> void:
	var d := _def()
	var n1 := _node(_me)
	var n2 := _node(_me)
	var n3 := _node(_me)
	var n4 := _node(_me)
	var n5 := _node(_me)
	var n6 := _node(_me)
	var n7 := _node(_me)
	var adjacency := {
		n1: [n2], n2: [n1, n3], n3: [n2, n4], n4: [n3, n5],
		n5: [n4, n6], n6: [n5, n7], n7: [n6],
	}
	n3.apply_status(d, 4.0)
	n6.apply_status(d, 5.0)
	var field := _field(d, adjacency)
	var rule := SpillSpread.new()
	rule.spread_fraction = 1.0
	var removed: Array[NodeCombat] = [n3, n4, n5, n6, n7]
	var transfers := rule.on_removed(field, removed, StatusSpread.CAUSE_DEATH)

	var from6 := _find(transfers, n6, null)
	assert_not_null(from6, "6 has no survivor: burns")
	assert_eq(from6.amount, 5.0, "6's whole row vanishes")
	assert_null(_find(transfers, n6, n5), "5 is removed: no transfer to it")
	assert_null(_find(transfers, n6, n7), "7 is removed: no transfer to it")

	var from3to2 := _find(transfers, n3, n2)
	assert_not_null(from3to2, "3's curse goes to 2")
	assert_eq(from3to2.amount, 4.0, "all of 3's stacks, k=1")
	assert_null(_find(transfers, n3, n4), "4 is removed: no transfer to it")
	assert_null(_find(transfers, n3, null), "3 has a survivor: nothing burned")


# ── share arithmetic ─────────────────────────────────────────────────────────

func test_share_splits_evenly_and_voids_the_remainder() -> void:
	var d := _def()
	var r := _node(_me)
	var s1 := _node(_me)
	var s2 := _node(_me)
	var s3 := _node(_me)
	r.apply_status(d, 5.0)
	var field := _field(d, {r: [s1, s2, s3]})
	var rule := SpillSpread.new()
	rule.spread_fraction = 1.0
	var transfers := rule.on_removed(field, [r] as Array[NodeCombat], StatusSpread.CAUSE_DEATH)
	for s in [s1, s2, s3]:
		var t := _find(transfers, r, s)
		assert_not_null(t, "each of the 3 survivors receives")
		assert_eq(t.amount, 1.0, "floor(5/3) = 1 each")
	var burned := _find(transfers, r, null)
	assert_not_null(burned, "remainder voided")
	assert_eq(burned.amount, 2.0, "5 - 1*3 = 2")


func test_share_below_one_per_survivor_voids_everything() -> void:
	var d := _def()
	var r := _node(_me)
	var s1 := _node(_me)
	var s2 := _node(_me)
	var s3 := _node(_me)
	r.apply_status(d, 2.0)
	var field := _field(d, {r: [s1, s2, s3]})
	var rule := SpillSpread.new()
	rule.spread_fraction = 1.0
	var transfers := rule.on_removed(field, [r] as Array[NodeCombat], StatusSpread.CAUSE_DEATH)
	for s in [s1, s2, s3]:
		assert_null(_find(transfers, r, s), "nothing received, floor(2/3) = 0")
	var burned := _find(transfers, r, null)
	assert_not_null(burned, "all voided")
	assert_eq(burned.amount, 2.0, "the whole row")


func test_spread_fraction_applies_before_the_split() -> void:
	var d := _def()
	var r := _node(_me)
	var s := _node(_me)
	r.apply_status(d, 7.0)
	var field := _field(d, {r: [s]})
	var rule := SpillSpread.new()
	rule.spread_fraction = 0.5
	var transfers := rule.on_removed(field, [r] as Array[NodeCombat], StatusSpread.CAUSE_DEATH)
	var t := _find(transfers, r, s)
	assert_not_null(t, "the one survivor receives")
	assert_eq(t.amount, 3.0, "floor(floor(7*0.5)/1) = floor(3/1) = 3")
	var burned := _find(transfers, r, null)
	assert_not_null(burned, "remainder voided")
	assert_eq(burned.amount, 4.0, "7 - 3 = 4")


# ── total received never exceeds S ──────────────────────────────────────────

func test_total_received_never_exceeds_s_across_a_sweep() -> void:
	var d := _def()
	for s_val in range(0, 51, 5):
		for k in range(0, 7):
			for frac in [0.0, 0.25, 0.5, 0.75, 1.0]:
				var r := _node(_me)
				var survivors: Array[NodeCombat] = []
				for i in range(k):
					survivors.append(_node(_me))
				if s_val > 0:
					r.apply_status(d, float(s_val))
				var field := _field(d, {r: survivors})
				var rule := SpillSpread.new()
				rule.spread_fraction = frac
				var transfers := rule.on_removed(field, [r] as Array[NodeCombat], StatusSpread.CAUSE_DEATH)
				var received := 0.0
				for t in transfers:
					if t.to != null:
						received += t.amount
				assert_true(received <= float(s_val), "S=%d k=%d frac=%s: received %s <= %s" % [s_val, k, frac, received, s_val])


# ── order-free ───────────────────────────────────────────────────────────────

func test_shuffling_removed_gives_an_identical_transfer_multiset() -> void:
	var d := _def()
	var a := _node(_me)
	var b := _node(_me)
	var c := _node(_me)
	var sa := _node(_me)
	var sb := _node(_me)
	a.apply_status(d, 3.0)
	b.apply_status(d, 6.0)
	c.apply_status(d, 9.0)
	var adjacency := {a: [sa], b: [sb, a], c: [sa, sb]}
	var field := _field(d, adjacency)

	var rule1 := SpillSpread.new()
	var ordered: Array[NodeCombat] = [a, b, c]
	var t1 := rule1.on_removed(field, ordered, StatusSpread.CAUSE_DEATH)

	var rule2 := SpillSpread.new()
	var shuffled: Array[NodeCombat] = [c, a, b]
	var t2 := rule2.on_removed(field, shuffled, StatusSpread.CAUSE_DEATH)

	assert_eq(t1.size(), t2.size(), "same number of transfers")
	for t in t1:
		var found = null
		for u in t2:
			if u.from == t.from and u.to == t.to and u.amount == t.amount:
				found = u
				break
		assert_not_null(found, "transfer %s -> %s amount %s present after shuffle" % [t.from, t.to, t.amount])


# ── mask honoured ─────────────────────────────────────────────────────────────

func test_mask_is_honoured() -> void:
	var d := _def()
	var r := _node(_me)
	var enemy_border := _node(_foe)
	var mine_border := _node(_me)
	r.apply_status(d, 4.0)
	var adjacency := {r: [enemy_border, mine_border]}

	var hostile_field := _field(d, adjacency, SkillNode.Ownership.HOSTILE)
	var hostile_rule := SpillSpread.new()
	var hostile_transfers := hostile_rule.on_removed(hostile_field, [r] as Array[NodeCombat], StatusSpread.CAUSE_DEATH)
	assert_not_null(_find(hostile_transfers, r, enemy_border), "Hostile mask: the enemy border receives")
	assert_null(_find(hostile_transfers, r, mine_border), "Hostile mask: our own node does not")

	var mine_field := _field(d, adjacency, SkillNode.Ownership.MINE)
	var mine_rule := SpillSpread.new()
	var mine_transfers := mine_rule.on_removed(mine_field, [r] as Array[NodeCombat], StatusSpread.CAUSE_DEATH)
	assert_null(_find(mine_transfers, r, enemy_border), "Mine mask: the enemy border does not receive")
	assert_not_null(_find(mine_transfers, r, mine_border), "Mine mask: our own node does")


# ── cause gate ─────────────────────────────────────────────────────────────

func test_dealloc_only_spill_returns_empty_for_death_cause() -> void:
	var d := _def()
	var r := _node(_me)
	var s := _node(_me)
	r.apply_status(d, 4.0)
	var field := _field(d, {r: [s]})
	var rule := SpillSpread.new()
	rule.triggers = StatusSpread.CAUSE_DEALLOC
	var transfers := rule.on_removed(field, [r] as Array[NodeCombat], StatusSpread.CAUSE_DEATH)
	assert_eq(transfers.size(), 0, "gated out: Dealloc-only rule ignores a Death cause")

	var ok_transfers := rule.on_removed(field, [r] as Array[NodeCombat], StatusSpread.CAUSE_DEALLOC)
	assert_gt(ok_transfers.size(), 0, "Dealloc cause passes the gate")


# ── sink neighbours + death share (#1453) ────────────────────────────────────

## X(owned, 7 stacks) beside one owned receiver, two neutral sinks, one hostile.
func _sink_setup(stacks: float = 7.0) -> Dictionary:
	var d := _def()
	var x := _node(_me)
	var recv := _node(_me)
	var s1 := _node(null)
	var s2 := _node(null)
	var foe := _node(_foe)
	x.apply_status(d, stacks)
	var removed: Array[NodeCombat] = [x]
	return {"field": _field(d, {x: [recv, s1, s2, foe]}), "x": x, "recv": recv, "removed": removed}


func _sink_rule(death_fraction: float = 1.0) -> SpillSpread:
	var rule := SpillSpread.new()
	rule.sink_mask = SkillNode.Ownership.NEUTRAL
	rule.death_fraction = death_fraction
	return rule


func test_sinks_dilute_dealloc_share() -> void:
	var s := _sink_setup()
	var out := _sink_rule().on_removed(s.field, s.removed, StatusSpread.CAUSE_DEALLOC)
	var t := _find(out, s.x, s.recv)
	assert_not_null(t)
	assert_eq(t.amount, 2.0, "floor(7 / (1 + 2))")
	var landed := 0.0
	for tr in out:
		if tr.to != null:
			landed += tr.amount
	assert_eq(landed, 2.0, "nothing reaches a sink or the hostile")


func test_wound_smaller_than_divisor_vanishes() -> void:
	var s := _sink_setup(2.0)
	var out := _sink_rule().on_removed(s.field, s.removed, StatusSpread.CAUSE_DEALLOC)
	for tr in out:
		assert_null(tr.to, "S=2, divisor 3: all burns")


func test_death_fraction_scales_kill_share() -> void:
	var s := _sink_setup()
	var out := _sink_rule(0.5).on_removed(s.field, s.removed, StatusSpread.CAUSE_DEATH)
	var t := _find(out, s.x, s.recv)
	assert_not_null(t)
	assert_eq(t.amount, 1.0, "floor(7 * 0.5 / 3)")
	var d_out := _sink_rule(0.5).on_removed(s.field, s.removed, StatusSpread.CAUSE_DEALLOC)
	assert_eq(_find(d_out, s.x, s.recv).amount, 2.0, "dealloc keeps spread_fraction")

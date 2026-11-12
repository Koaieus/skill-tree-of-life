extends GutTest

## #1800 (U4, acceptance 5): dual reach. A node C holding Explosive charges and
## Burning sets off both discs in one hit, both read at C's one read. Burning's
## disc is Fire's (never mutated); the Explosive disc is this test's own
## [DiscGoOff] on the Explosive [Aspect], restored in after_each. The hit
## carries damage, Poison and a Heat rider (no Explosive row). Entry counts
## only: the own damage rides every entry, so amounts are not asserted.

const _RAW := 4.0
const _POISON := 3.0
const _FAR := 20000.0

var _w: TestWorld
var _red: Entity
var _blue: Entity
var _aspect: Aspect
var _was: GoOff
var _explosive: DiscGoOff
var _was_tunables: HitGatherTunables


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_red = _w.add_entity("Red")
	_blue = _w.add_entity("Blue")
	await get_tree().process_frame
	_aspect = AspectRoster.shared().by_id(&"explosive")
	_was = _aspect.go_off
	_explosive = DiscGoOff.new()
	_aspect.go_off = _explosive
	_was_tunables = HitGather.tunables


func after_each() -> void:
	_aspect.go_off = _was
	HitGather.tunables = _was_tunables
	CombatWorld.reset_live()


func _fire() -> Element:
	return ElementRoster.shared().by_id(&"fire")


func _at(id: StringName, pos: Vector2) -> SkillNode:
	var n := _w.add_node(id)
	n.global_position = pos
	var anchor := _w.add_node(StringName("%s_anchor" % id))
	anchor.global_position = pos + Vector2(0.0, _FAR)
	_w.link(n, anchor)
	return n


func _hit(at: SkillNode, heat: int) -> Array[HitInstance]:
	var d := DamageInstance.new()
	d.amount = _RAW
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	var poison := StatusInstance.new()
	poison.def = preload("res://effects/status/poison.tres")
	poison.power = _POISON
	poison.raw = true
	var h := StatusInstance.new()
	h.def = _fire().terrain
	h.power = float(heat)
	h.raw = true
	var span: Array[HitInstance] = [d, poison, h]
	for hit in span:
		hit.target = at
		hit.attacker = _blue
		hit.schedule_index = 0
	return span


func _land(span: Array[HitInstance]) -> Array[HitInstance]:
	var all: Array[HitInstance] = span.duplicate()
	HitGather.stage_one(span.duplicate(), CombatWorld.live(), HitQueue.over(all))
	return all


func _on(hits: Array, n: SkillNode) -> Array:
	return hits.filter(func(h: HitInstance) -> bool: return h.target == n)


func _damage_entries(hits: Array) -> int:
	return hits.filter(func(h: HitInstance) -> bool: return h is DamageInstance).size()


func _heat_riders(hits: Array) -> int:
	return hits.filter(func(h: HitInstance) -> bool: return h is StatusInstance and h.def == _fire().terrain).size()


## Entries on [param n] whose mark is Burning's (a mark naming a go-off that is
## not the Explosive aspect's).
func _burning_marked(hits: Array, n: SkillNode) -> int:
	var xp := _aspect.identity
	return _on(hits, n).filter(func(h: HitInstance) -> bool:
		return h is DamageInstance and h.blast_mark != null and h.blast_mark.go_off != xp).size()


## C (Heat T + 1, two Explosive charges) and N close east inside both discs, N
## unprimed after its copies. `[C, N, all]` after one hit with Heat rider 1.
func _fixture(own_node: bool, dedupe := false) -> Array:
	_explosive.lands_on_own_node = own_node
	var tun := HitGatherTunables.new()
	tun.dedupe_dual_reach = dedupe
	HitGather.tunables = tun
	var c := _at(&"C", Vector2.ZERO)
	var n := _at(&"N", Vector2(c.radius * 3.0, 0.0))
	_w.allocate(_red, [c, n])
	await get_tree().process_frame
	var combat := c.get_combat()
	combat.add_terrain(_fire(), _t(c) + 1 - c.get_combat().terrain_t())
	combat.apply_status(StatusRoster.shared().by_concept(&"explosive"), 2.0)
	assert_lt(2, c.get_combat().terrain_threshold() + 1 + 1, "fixture sanity: C primed past T")
	assert_lt(1, n.get_combat().terrain_threshold() + 1, "fixture: N stays unprimed after both copies")
	return [c, n, _land(_hit(c, 1))]


func _t(n: SkillNode) -> int:
	return n.get_combat().terrain_threshold()


func test_both_discs_reach_n_and_its_heat_lands_once() -> void:
	var got: Array = await _fixture(false)
	var n: SkillNode = got[1]
	var on_n := _on(got[2], n)
	assert_eq(_damage_entries(on_n), 2, "N takes one entry per disc")
	assert_eq(on_n.filter(func(h: HitInstance) -> bool: return h is StatusInstance and h.def.id == &"poison").size(), 2,
			"each with Poison")
	assert_eq(n.get_combat().terrain_t(), 1, "Heat lands once: one copy's ceil(h × s), not the sum")


func test_burning_adds_one_centre_entry_and_the_exempt_explosive_disc_none() -> void:
	var got: Array = await _fixture(false)
	var on_c := _on(got[2], got[0])
	assert_eq(_damage_entries(on_c), 2, "C takes its hit and Burning's centre entry")
	assert_eq(_burning_marked(got[2], got[0]), 1, "exactly one entry on C carries Burning's mark")
	assert_eq(_heat_riders(on_c), 1, "no terrain rider on the centre entry")


func test_with_the_explosive_flag_true_c_takes_three_and_burnings_count_holds() -> void:
	var got: Array = await _fixture(true)
	assert_eq(_damage_entries(_on(got[2], got[0])), 3, "C takes its hit and one centre entry per disc")
	assert_eq(_burning_marked(got[2], got[0]), 1, "Burning's centre entry is still one")


func test_dedupe_off_keeps_both_entries_on_n_and_on_folds_them_c_unchanged() -> void:
	var off: Array = await _fixture(false, false)
	assert_eq(_damage_entries(_on(off[2], off[1])), 2, "off: N keeps both entries")
	assert_eq(_damage_entries(_on(off[2], off[0])), 2, "off: C takes 2")
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_red = _w.add_entity("Red")
	_blue = _w.add_entity("Blue")
	await get_tree().process_frame
	var on: Array = await _fixture(false, true)
	assert_eq(_damage_entries(_on(on[2], on[1])), 1, "on: N takes one landing at its summed multipliers")
	assert_eq(_damage_entries(_on(on[2], on[0])), 2, "on: C's count does not change")

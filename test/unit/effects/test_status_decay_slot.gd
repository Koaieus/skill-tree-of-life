extends GutTest

## The decay slot (#1258): every authored family carries a [StatusDecay] on
## [member StatusDef.decay], and the two members reproduce the arithmetic the
## retired FLAT / FRACTION enum did — FLAT floors at 0 — over a sweep of
## powers; FRACTION keeps the floor `⌊S · (1 − f)⌋` on the int row (ADR 0032).
## Corruption authors NO slot (owner, 2026-10-01: no decay for now).

const _DIR := "res://effects/status/"

## Each authored family's tooltip text, pinned before the slot replaced the
## two decay exports.
const _DESCRIPTIONS := {
	&"armor_break": "The node's armor is chipped away: -1 per stack, and one stack fades each turn.",
	&"blindness": "The node sees and senses less; the deeper the blindness, the slower its recovery starts.",
	&"corruption": "Every stack eats 2% of the node's max health each turn, unmitigated; the stacks never fade and never cap.",
	&"curse": "Every stack raises the least damage a hit can deal to this node by 1; stacks fall by 1 each turn and never cap.",
	&"poison": "Every stack deals 1 unmitigated damage each turn; one stack fades each turn and they never cap.",
	&"scout": "Scout arrows lit up this node's surroundings for their camp: the disc grows with the root of the stacks, only your own camp's stacks count, and one stack fades each turn.",
	&"wither": "Every stack cuts healing on this node by 10%; past 10 stacks healing becomes damage that never closes the regen gate. A quarter of the stacks fade each turn and they never cap.",
}


func _authored() -> Dictionary:
	var out := {}
	for f in ResourceLoader.list_directory(_DIR):
		if f.ends_with(".tres"):
			var def := load(_DIR + f) as StatusDef
			if def != null:
				out[def.id] = def
	return out


func _old_flat(power: float, rate: float) -> float:
	return maxf(power - rate, 0.0)


func _floor_kept(power: float, rate: float) -> float:
	var after := power * (1.0 - rate)
	return floorf(after + 0.000001)


func test_every_authored_family_has_a_decay_slot() -> void:
	var defs := _authored()
	assert_eq(defs.size(), _DESCRIPTIONS.size(), "every family is pinned")
	for id in defs:
		if id == &"corruption":
			assert_null(defs[id].get("decay"), "corruption does not decay")
			continue
		assert_true(defs[id].get("decay") is StatusDecay, "%s.decay is a StatusDecay" % id)


func test_descriptions_are_unchanged() -> void:
	var defs := _authored()
	for id in _DESCRIPTIONS:
		assert_true(defs.has(id), "%s authored" % id)
		if defs.has(id):
			assert_eq(defs[id].get_description(), _DESCRIPTIONS[id], "%s text" % id)


func test_flat_decay_matches_the_old_flat_mode() -> void:
	for rate in [0.0, 0.25, 1.0, 2.5]:
		var d := FlatDecay.new(rate)
		for p in range(0, 51):
			assert_almost_eq(d.decayed(float(p)), _old_flat(float(p), rate), 0.00001,
				"flat %s at %d" % [rate, p])
			assert_almost_eq(d.decayed(p + 0.5), _old_flat(p + 0.5, rate), 0.00001)


func test_fraction_decay_keeps_the_floor() -> void:
	for rate in [0.2, 0.25, 0.5, 0.7]:
		var d := FractionDecay.new(rate)
		for p in range(0, 51):
			assert_almost_eq(d.decayed(float(p)), _floor_kept(float(p), rate), 0.00001,
				"fraction %s at %d" % [rate, p])


func test_status_def_delegates_to_its_slot() -> void:
	var def := StatusDef.new()
	def.set("decay", FractionDecay.new(0.5))
	assert_eq(def.decayed(10.0), 5.0)
	assert_eq(def.decayed(1.5), 0.0, "tail cut below 1")
	def.set("decay", null)
	assert_eq(def.decayed(3.0), 3.0, "a null slot never decays")


func test_derived_description_reads_the_slot() -> void:
	var def := StatusDef.new()
	def.display_name = "Poison"
	def.power_max = 5.0
	assert_eq(def.get_description(), "Poison (max 5, -1 per turn)", "default flat 1")
	def.set("decay", FractionDecay.new(0.5))
	assert_eq(def.get_description(), "Poison (max 5, -0.5 per turn)")

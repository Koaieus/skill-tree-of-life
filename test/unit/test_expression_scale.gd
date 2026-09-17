extends GutTest

## ExpressionScale + AuraEffect.discard (#900).
##
## The scale now returns the VALUE to grant, not a multiplier, over three float
## inputs: `d` (distance), `max` (the reach bound, -1.0 unbounded) and `v` (the
## leaf modifier's authored value). `5 - d` is the absolute per-hop ladder that
## the closed-form library could never say; `v * (1 - d / max)` is `LinearScale`.
##
## Reach is membership, the formula is the value, and `AuraEffect.discard` — not
## a hidden `is_zero_approx` — decides what is worth granting.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _chain: Array[SkillNode] = []


## One straight line N0—N1—…—N7, so hop distance from N0 IS the index.
func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_chain = []
	for i in 8:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 100.0, 0.0)
		_graph.add_skill_node(sn)
		_chain.append(sn)
	for i in 7:
		_graph.add_edge(_chain[i], _chain[i + 1])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)


func _spawn_owning_whole_chain() -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "E"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# entities_container, not the Graph itself: NodeEffectReadout.gather walks
	# that container, so an entity parented elsewhere reports zero grant rows.
	_graph.entities_container.add_child(ent)
	await get_tree().process_frame
	for n in _chain:
		_alloc.force_allocate(ent, n)
	ent.core_location = _chain[0]
	ent.stat_board.armor.base_value = 0.0
	return ent


## `armor` is an INT-typed stat, so it reports a whole number however the
## modifier pipeline got there. Fine for the integer ladders below; the
## fractional LinearScale case uses [method _crit_mod] instead.
func _armor_mod(value: float, op: int = StatModifier.Operation.ADD_BONUS) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = op
	m.value = value
	return m


## A FLOAT-typed stat (`value_type = 1`), for the assertions that care about
## 6.67 rather than 6.
func _crit_mod(value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"crit_chance"
	m.operation = StatModifier.Operation.ADD_BONUS
	m.value = value
	return m


func _crit(n: SkillNode) -> float:
	return float(n.get_local_value(&"crit_chance"))


func _expr(formula: String) -> ExpressionScale:
	var s := ExpressionScale.new()
	s.formula = formula
	return s


func _aura(formula: String, hops: int, mods: Array[StatModifier],
		discard: int = AuraEffect.Discard.NON_POSITIVE) -> AuraEffect:
	var aura := AuraEffect.new()
	if hops >= 0:
		var reach := HopRangeFinder.new()
		reach.max_hops = hops
		aura.reach = reach
	aura.distance_scale = _expr(formula)
	aura.discard = discard
	aura.modifiers = mods
	return aura


func _armor(n: SkillNode) -> float:
	return float(n.get_local_value(&"armor"))


## How many modifier rows any aura has actually put on this node — the only way
## to tell "granted 0" from "not granted", which is the whole point of `discard`.
func _grant_rows(n: SkillNode) -> int:
	return NodeEffectReadout.gather(n, _graph).size()


# ── Acceptance 1: the absolute per-hop ladder ───────────────────────────────

## `5 - d` ignores `v` entirely: 5 at the core, 4 one hop out, 3, 2, 1 — the
## shape `LinearScale` structurally cannot produce, because it ties the decay
## rate to the reach and so always zeroes the rim ring.
func test_absolute_ladder_grants_five_four_three_two_one() -> void:
	var ent: Entity = await _spawn_owning_whole_chain()
	ent.grant_effect(_aura("5 - d", 5, [_armor_mod(999.0)]))

	for hop in 5:
		assert_almost_eq(_armor(_chain[hop]), 5.0 - hop, 0.001,
				"hop %d gets 5 - d, not a multiple of the authored value" % hop)
	assert_eq(_grant_rows(_chain[5]), 0,
			"hop 5 computes 0 and the default NON_POSITIVE discards it")


## "…2, 1, 0" — the author wants the zero ring to exist.
func test_discard_negative_lands_the_zero_ring() -> void:
	var ent: Entity = await _spawn_owning_whole_chain()
	ent.grant_effect(_aura("5 - d", 5, [_armor_mod(999.0)], AuraEffect.Discard.NEGATIVE))

	assert_eq(_grant_rows(_chain[5]), 1, "hop 5 is granted at 0, visibly")
	assert_almost_eq(_armor(_chain[5]), 0.0, 0.001)


## "…1, 0, -1" — discard NONE lets the ladder go through zero.
func test_discard_none_lets_the_ladder_go_negative() -> void:
	var ent: Entity = await _spawn_owning_whole_chain()
	ent.grant_effect(_aura("5 - d", 6, [_armor_mod(999.0)], AuraEffect.Discard.NONE))

	assert_almost_eq(_armor(_chain[6]), -1.0, 0.001, "hop 6 lands -1")
	assert_eq(_grant_rows(_chain[7]), 0, "hop 7 is past reach — membership, not policy")


# ── Acceptance 2: the library scales are formula spellings ──────────────────

## Pins the migration: every closed-form scale is now `value * <multiplier>`,
## and an ExpressionScale spelling of it must agree node for node.
func test_library_scales_equal_their_formula_spellings(params = use_parameters([
		[FlatScale.new(), "v", 3],
		[LinearScale.new(), "v * (1 - d / max)", 3],
		[ProportionalScale.new(), "v * d", 3],
])) -> void:
	var library: DistanceScale = params[0]
	var formula: String = params[1]
	var hops: int = params[2]
	var spelled := _expr(formula)
	var bound := float(hops)
	for d in hops + 1:
		assert_almost_eq(spelled.scale(float(d), bound, 10.0),
				library.scale(float(d), bound, 10.0), 0.001,
				"%s disagrees with '%s' at d=%d" % [library.get_class(), formula, d])


## The LinearScale numbers spelled out, so a regression names itself.
func test_linear_spelling_reproduces_ten_six_point_seven_three_point_three() -> void:
	var ent: Entity = await _spawn_owning_whole_chain()
	# crit_chance carries a non-zero board baseline, so assert the DELTA the
	# aura contributed rather than the absolute stat.
	var base := _crit(_chain[0])
	ent.grant_effect(_aura("v * (1 - d / max)", 3, [_crit_mod(10.0)]))

	assert_almost_eq(_crit(_chain[0]) - base, 10.0, 0.001)
	assert_almost_eq(_crit(_chain[1]) - base, 6.667, 0.01)
	assert_almost_eq(_crit(_chain[2]) - base, 3.333, 0.01)
	assert_eq(_grant_rows(_chain[3]), 0, "the rim ring computes 0 and is discarded")


# ── Acceptance 3: `v` is per LEAF ──────────────────────────────────────────

## A composite is granted as ONE handle, but each of its leaves is shaped from
## its OWN authored value — which is why `grant_at` takes a value per leaf
## rather than a single number for the whole modifier.
func test_composite_leaves_each_get_their_own_value() -> void:
	var ent: Entity = await _spawn_owning_whole_chain()
	var comp := CompositeStatModifier.new()
	comp.children = [_armor_mod(10.0), _armor_mod(4.0), _armor_mod(-2.0)]
	ent.grant_effect(_aura("v * 0.5", 1, [comp], AuraEffect.Discard.NONE))

	# 5 + 2 + (-1) — three different results from one formula at one node.
	assert_almost_eq(_armor(_chain[0]), 6.0, 0.001,
			"each leaf is halved from its own v, not all from the first")
	assert_eq(_grant_rows(_chain[0]), 1, "still a single composite grant")


# ── Acceptance 4: the discard policy sweep ─────────────────────────────────

## `d - 2` over hops 0..4 gives -2, -1, 0, 1, 2 — one value of every sign class,
## so each policy picks out a different, unambiguous set of hops. (The issue's
## prose for this case is self-contradictory; the full sweep settles it.)
func test_discard_policies_over_a_sign_crossing_formula(params = use_parameters([
		[AuraEffect.Discard.NONE, [0, 1, 2, 3, 4]],
		[AuraEffect.Discard.ZERO, [0, 1, 3, 4]],
		[AuraEffect.Discard.NEGATIVE, [2, 3, 4]],
		[AuraEffect.Discard.NON_POSITIVE, [3, 4]],
		[AuraEffect.Discard.POSITIVE, [0, 1, 2]],
		[AuraEffect.Discard.NON_NEGATIVE, [0, 1]],
])) -> void:
	var policy: int = params[0]
	var expected: Array = params[1]
	var ent: Entity = await _spawn_owning_whole_chain()
	ent.grant_effect(_aura("d - 2", 4, [_armor_mod(1.0)], policy))

	for hop in 5:
		assert_eq(_grant_rows(_chain[hop]), 1 if expected.has(hop) else 0,
				"policy %d at hop %d" % [policy, hop])


# ── Acceptance 5: uses_bound ───────────────────────────────────────────────

func test_uses_bound_tracks_whether_the_formula_mentions_max() -> void:
	assert_true(_expr("v * (1 - d / max)").uses_bound(), "'max' appears → bound-dependent")
	assert_false(_expr("5 - d").uses_bound(), "no 'max' → the bound is irrelevant")
	assert_false(_expr("v * maxi(d, 1)").uses_bound(),
			"'maxi' is a different token — word boundaries, not substrings")
	assert_almost_eq(_expr("v * maxf(d, 1.0)").scale(0.0, -1.0, 10.0), 10.0, 0.001,
			"and maxf still resolves as the built-in function it is")


# ── Acceptance 6: parse errors and hot-editing ─────────────────────────────

## A broken formula must not take the game down, and must not silently grant
## garbage: the aura simply lands nothing.
func test_parse_error_pushes_exactly_one_error_however_often_it_is_asked() -> void:
	var scale := _expr("5 - (((")
	for i in 5:
		assert_almost_eq(scale.scale(float(i), 5.0, 1.0), 0.0, 0.001, "an unparseable formula is inert")
	assert_push_error_count(1,
			"the failure is latched — one error per edit, not one per node per recompute")


func test_parse_error_grants_nothing_and_does_not_crash() -> void:
	var ent: Entity = await _spawn_owning_whole_chain()
	ent.grant_effect(_aura("5 - (((", 3, [_armor_mod(10.0)], AuraEffect.Discard.NONE))
	assert_almost_eq(_armor(_chain[0]), 0.0, 0.001, "a broken aura lands nothing, and does not crash")
	assert_push_error_count(1)


## The setter invalidates the cached Expression — an inspector hot-edit in the
## sandbox host must take effect without reconstructing the resource.
func test_editing_the_formula_reparses() -> void:
	var scale := _expr("5 - d")
	assert_almost_eq(scale.scale(1.0, -1.0, 99.0), 4.0, 0.001)
	scale.formula = "100 - d"
	assert_almost_eq(scale.scale(1.0, -1.0, 99.0), 99.0, 0.001, "the new formula is in force")


## Integer division is Expression's classic trap: `1 - d / max` with ints would
## floor. Everything goes in as a float.
func test_inputs_are_floats_not_ints() -> void:
	assert_almost_eq(_expr("d / max").scale(1.0, 2.0, 0.0), 0.5, 0.001,
			"1 / 2 must be 0.5, not an integer-divided 0")


# ── Acceptance 7: MULTIPLY means the factor, as documented ─────────────────

## Quoted from `EffectContext.grant_at`'s docstring: for a MULTIPLY leaf the
## formula's result IS the factor. `1 - d/5` at hop 1 is ×0.8 — it does not
## mean "80% of the authored ×1.5". Asserted as-is: this is the chosen,
## documented behaviour, not an accident.
func test_multiply_leaf_lands_the_formula_result_as_the_factor() -> void:
	var scale := _expr("1 - d / 5")
	assert_almost_eq(scale.scale(1.0, 5.0, 1.5), 0.8, 0.001,
			"the authored 1.5 is ignored — the formula's result is the factor")


# ── #943: hops / euclid / relation as formula inputs ────────────────────────
#
# `d` stays the metric's own distance; `h` (hop depth over the aura's mirror),
# `e` (pixels from the source) and `rel` (the node's ownership bit as the aura's
# owner sees it) are ADDITIONAL inputs, walked only when the formula names them.

## Like [method _spawn_owning_whole_chain] but for any subset — the second
## entity of the relation fixture owns the far end of the chain.
func _spawn_owning(core: SkillNode, owned: Array[SkillNode], display: String = "E") -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = display
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(ent)
	await get_tree().process_frame
	for n in owned:
		_alloc.force_allocate(ent, n)
	ent.core_location = core
	ent.stat_board.armor.base_value = 0.0
	return ent


## Scramble the chain's pixel layout so Euclidean distance from N0 is NOT
## monotone in hop count: N1 sits far away, N3 sits right next to the core.
func _scramble_positions() -> void:
	_chain[1].position = Vector2(700.0, 0.0)
	_chain[3].position = Vector2(50.0, 0.0)
	_chain[5].position = Vector2(20.0, 0.0)


## Acceptance 1a: a Euclidean METRIC feeds `d` in pixels, yet `10 - h` still
## follows hop depth — the formula reached past its own metric.
func test_h_follows_hop_depth_when_the_metric_is_euclidean() -> void:
	_scramble_positions()
	var ent: Entity = await _spawn_owning_whole_chain()
	var aura := _aura("10 - h", -1, [_armor_mod(1.0)])
	aura.metric = EuclideanMetric.new()
	ent.grant_effect(aura)
	for i in 8:
		assert_almost_eq(_armor(_chain[i]), 10.0 - i, 0.001,
			"N%d is %d hops out whatever its pixel distance" % [i, i])
	# Sanity: the scramble really made d disagree with h (else the test proves nothing).
	assert_lt(_chain[3].position.distance_to(_chain[0].position),
		_chain[1].position.distance_to(_chain[0].position),
		"fixture: N3 must be nearer in pixels than N1")


## `e` is pixels from the source no matter what the metric measures — a hop
## metric aura can still fall off spatially through it.
func test_e_is_pixel_distance_under_a_hop_metric() -> void:
	_scramble_positions()
	var ent: Entity = await _spawn_owning_whole_chain()
	var aura := _aura("e", -1, [_armor_mod(1.0)], AuraEffect.Discard.NONE)
	aura.metric = HopMetric.new()
	ent.grant_effect(aura)
	assert_almost_eq(_armor(_chain[1]), 700.0, 0.5)
	assert_almost_eq(_armor(_chain[3]), 50.0, 0.5)
	assert_almost_eq(_armor(_chain[5]), 20.0, 0.5)


## Acceptance 1b: `v * (1 + int(rel == 8))` doubles on HOSTILE only. A owns
## N0..N3, B owns N5..N7, N4 is nobody's; A's GLOBAL aura sees its own nodes as
## MINE (2), the gap as NEUTRAL (1) and B's as HOSTILE (8). Every Entity
## defaults to the same npc faction (allies), so B gets a faction of its own.
func test_rel_doubles_on_hostile_nodes_only() -> void:
	var a: Entity = await _spawn_owning(_chain[0], [_chain[0], _chain[1], _chain[2], _chain[3]], "A")
	var b: Entity = await _spawn_owning(_chain[7], [_chain[5], _chain[6], _chain[7]], "B")
	var rival := Faction.new()
	rival.id = &"rival"
	b.faction = rival
	var aura := _aura("v * (1 + int(rel == 8))", -1, [_armor_mod(5.0)])
	aura.scope = AuraEffect.Scope.GLOBAL
	var inst := a.grant_effect(aura)
	assert_almost_eq(_armor(_chain[0]), 5.0, 0.001, "MINE: unchanged")
	assert_almost_eq(_armor(_chain[3]), 5.0, 0.001, "MINE: unchanged")
	assert_almost_eq(_armor(_chain[4]), 5.0, 0.001, "NEUTRAL: unchanged")
	assert_almost_eq(_armor(_chain[5]), 10.0, 0.001, "HOSTILE: doubled")
	assert_almost_eq(_armor(_chain[7]), 10.0, 0.001, "HOSTILE: doubled")
	# Same faction again → ALLY (4), not HOSTILE: the bit really is the relation.
	a.revoke_effect(inst)
	b.faction = a.faction
	aura.distance_scale = _expr("v * (1 + int(rel == 4))")
	a.grant_effect(aura)
	assert_almost_eq(_armor(_chain[0]), 5.0, 0.001, "MINE is not ALLY")
	assert_almost_eq(_armor(_chain[5]), 10.0, 0.001, "ALLY: doubled now")


## Acceptance 1c: a formula naming neither `h` nor `e` reports neither want,
## and the aura never opens the hop door for it.
func test_a_formula_naming_neither_h_nor_e_never_walks_hops() -> void:
	var ent: Entity = await _spawn_owning_whole_chain()
	var scale := _expr("v * (1 - d / max)")
	assert_false(scale.wants_hops(), "no `h` in the formula")
	assert_false(scale.wants_euclid(), "no `e` in the formula")
	var aura := _aura("v * (1 - d / max)", 4, [_armor_mod(4.0)])
	aura.metric = EuclideanMetric.new()
	var before := HopMetric.depths_call_count
	ent.grant_effect(aura)
	assert_eq(HopMetric.depths_call_count - before, 0,
		"HopMetric.depths must not be called for a formula that never names h")


## The wants are word-boundary matched on the authored text, like `uses_bound`.
func test_wants_hops_and_wants_euclid_track_the_formula(params = use_parameters([
		["v * h", true, false],
		["e / 2", false, true],
		["h + e", true, true],
		["5 - d", false, false],
		["maxf(e, 1.0) * h", true, true],
		["hypot(d, 1.0)", false, false],   # `h` inside an identifier is not the input
		["10 - d / max", false, false],
	])) -> void:
	var scale := _expr(params[0])
	assert_eq(scale.wants_hops(), params[1], "%s wants_hops" % params[0])
	assert_eq(scale.wants_euclid(), params[2], "%s wants_euclid" % params[0])


## The 3-arg `scale` keeps working by passing the sentinels `h = -1, e = -1,
## rel = 0` — a formula that never names them evaluates exactly as before.
func test_three_arg_scale_passes_the_sentinels() -> void:
	assert_almost_eq(_expr("h + e + rel").scale(0.0, -1.0, 0.0), -2.0, 0.001)
	assert_almost_eq(_expr("5 - d").scale(2.0, -1.0, 9.0), 3.0, 0.001,
		"a formula blind to the new inputs is unchanged")
	assert_almost_eq(_expr("v * (1 - h / max)").scale_at(1.0, 4.0, 8.0, 2.0, 300.0, 2), 4.0, 0.001,
		"scale_at hands the formula h")

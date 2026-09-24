extends GutTest

## [BlindnessStatus] (#873, hub #868; depth #1090): a ×factor on the
## node-local `vision_range` / `sensor_range`, one saturating curve on the
## TOTAL power — `max(floor, k / (power + k))` — so reapplies ACCUMULATE
## commutatively and a FRACTION fade recovers slowly first, then faster. The
## curve knobs under test are set on a hand-built def; the authored
## `blindness.tres` is pinned only for its shape (uncapped, accumulating,
## fractional), never its magnitudes.
##
## The vision half drives [VisionSystem] through its stat bindings rather than
## `_recompute()` by hand: the fog must re-evaluate on the modifier change
## with no allocation event in between (the "poke" the issue asks to verify).

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

const _STATS: Array[StringName] = [&"vision_range", &"sensor_range"]

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _nodes: Array[SkillNode]
var _def: BlindnessStatus
var _shadows: Array[EntityCombat] = []


func before_each() -> void:
	_shadows = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Blinkered"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)

	# Path graph N0 – N1 – N2, 600px apart.
	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 600.0, 0.0)
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	for i in 2:
		var e := _EDGE_SCENE.instantiate() as Edge
		e.from = _nodes[i]
		e.to = _nodes[i + 1]
		_graph.edges_container.add_child(e)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _nodes[0])
	_entity.core_location = _nodes[0]

	_def = BlindnessStatus.new()
	_def.id = &"blindness"
	_def.power_max = 0.0
	_def.display_max = 3.0
	_def.decay_mode = StatusDef.DecayMode.FRACTION
	# decay_per_tick is the fraction REMOVED; the owner's table f is the
	# fraction RETAINED ("FRACTION 0.7" → 0.3 removed).
	_def.decay_per_tick = 0.3
	_def.reapply = StatusDef.Reapply.ACCUMULATE
	_def.depth_k = 3.0
	_def.floor_factor = 0.1


## Both stats are derived (a PER-scaled term and an INCREASE ride on
## `base_value`), so solve the affine map base → effective for the entity base
## that lands the node-local EFFECTIVE value on `target`.
func _set_local(stat_id: StringName, target: float) -> void:
	var s: Stat = _entity.stat_board.get_stat(stat_id)
	s.base_value = 0.0
	var at_zero: float = float(_nodes[0].get_local_value(stat_id))
	s.base_value = 1000.0
	var slope: float = (float(_nodes[0].get_local_value(stat_id)) - at_zero) / 1000.0
	s.base_value = (target - at_zero) / slope
	assert_almost_eq(float(_nodes[0].get_local_value(stat_id)), target, 0.001,
		"fixture: effective local %s should be %s" % [stat_id, target])


func _local(stat_id: StringName) -> float:
	return float(_nodes[0].get_local_value(stat_id))


func _combat() -> NodeCombat:
	return _nodes[0].get_combat()


## The blind multipliers currently on [param node]'s local `stat_id`.
func _blind_modifiers(stat_id: StringName, node: SkillNode = null) -> Array[StatModifier]:
	if node == null:
		node = _nodes[0]
	var out: Array[StatModifier] = []
	var s: Stat = node.node_board.get_stat(stat_id) if node.node_board != null else null
	if s == null:
		return out
	for m in s.bins.multipliers:
		if m is BlindnessStatus.BlindModifier:
			out.append(m)
	return out


func _has_blind_modifier(stat_id: StringName) -> bool:
	return not _blind_modifiers(stat_id).is_empty()


## Both the exact factor on the one modifier and the merged local read
## (`get_local_value` composes entity + node bins, then floors once — both
## ranges are INT, so 10 × ⅔ reads 6, not 6.67; #890/#895).
func _assert_factor(stat_id: StringName, factor: float, why: String) -> void:
	var mods := _blind_modifiers(stat_id)
	assert_eq(mods.size(), 1, "%s: exactly one blind multiplier (%s)" % [stat_id, why])
	if mods.size() == 1:
		assert_almost_eq(mods[0].value, factor, 0.001, "%s: factor (%s)" % [stat_id, why])
	assert_almost_eq(_local(stat_id), floorf(10.0 * factor), 0.01, "%s: local read (%s)" % [stat_id, why])


func after_each() -> void:
	for sh in _shadows:
		sh.free_shadow()


# ── Numbers ──────────────────────────────────────────────────────────────────

func test_power_3_halves_then_recovers_until_the_tail_is_cut() -> void:
	for stat_id in _STATS:
		_set_local(stat_id, 10.0)
	_combat().apply_status(_def, 3.0)
	for stat_id in _STATS:
		_assert_factor(stat_id, 0.5, "power 3 at k 3")
	# 30 % removed per tick: 3 → 2.1 → the curve follows the decayed power.
	_combat().tick_statuses()
	for stat_id in _STATS:
		_assert_factor(stat_id, 3.0 / 5.1, "power 2.1 at k 3")
	# 2.1 → 1.47 → 1.029 → 0.72 < 1: the FRACTION tail is cut on the 4th tick.
	for _i in 3:
		_combat().tick_statuses()
	for stat_id in _STATS:
		assert_almost_eq(_local(stat_id), 10.0, 0.001, "%s: recovered" % stat_id)
		assert_false(_has_blind_modifier(stat_id), "%s: no blind modifier remains" % stat_id)
	assert_eq(_combat().get_status_power(&"blindness"), 0.0, "status gone once the tail drops below 1")


func test_reapply_accumulates_into_one_modifier() -> void:
	_set_local(&"vision_range", 10.0)
	_combat().apply_status(_def, 2.0)
	_combat().apply_status(_def, 2.0)
	assert_almost_eq(_combat().get_status_power(&"blindness"), 4.0, 0.001, "2 then 2 = 4")
	_assert_factor(&"vision_range", 3.0 / 7.0, "one curve on the total, replaced never stacked")


## The curve (owner's numbers, 2026-09-23): 1 at zero, ½ at k, saturating
## to the floor — power 27 at k 3 is exactly the 10 % floor.
func test_curve_is_one_at_zero_half_at_k_monotone_and_floored() -> void:
	assert_almost_eq(_def.factor_for(0.0), 1.0, 0.0001, "unblinded at zero")
	assert_almost_eq(_def.factor_for(3.0), 0.5, 0.0001, "power k → ½ (today's full dazzle)")
	assert_almost_eq(_def.factor_for(6.0), 1.0 / 3.0, 0.0001, "power 2k → ⅓")
	assert_almost_eq(_def.factor_for(27.0), 0.1, 0.0001, "power 9k → the floor")
	var prev := _def.factor_for(0.0)
	var p := 0.25
	while p <= 200.0:
		var f := _def.factor_for(p)
		assert_true(f <= prev + 0.000001, "monotone non-increasing at power %s" % p)
		assert_true(f >= _def.floor_factor - 0.000001, "never below the floor at power %s" % p)
		prev = f
		p += 0.25


## From deep (power 30) the first tick's power drop barely moves vision — the
## curve is flat there — and recovery accelerates on the later ticks.
func test_deep_blind_recovers_slowly_first_then_faster() -> void:
	_set_local(&"vision_range", 10.0)
	_combat().apply_status(_def, 30.0)
	var factors: Array[float] = [_blind_modifiers(&"vision_range")[0].value]
	for _i in 30:
		_combat().tick_statuses()
		var mods := _blind_modifiers(&"vision_range")
		factors.append(mods[0].value if not mods.is_empty() else 1.0)
		if mods.is_empty():
			break
	assert_gt(factors.size(), 3, "a deep blind lasts more than two ticks")
	var first := factors[1] - factors[0]
	var largest_later := 0.0
	for i in range(2, factors.size()):
		largest_later = maxf(largest_later, factors[i] - factors[i - 1])
	assert_lt(first, largest_later, "the first tick's recovery is the smallest step: %s" % [factors])


## Commutativity on the AUTHORED def (owner asked for it): the knobs that
## make it so — ACCUMULATE, uncapped — live in blindness.tres.
func test_authored_reapply_is_commutative() -> void:
	var blind := load("res://effects/status/blindness.tres") as BlindnessStatus
	_alloc.force_allocate(_entity, _nodes[1])
	_alloc.force_allocate(_entity, _nodes[2])
	var a := _nodes[1].get_combat()
	var b := _nodes[2].get_combat()
	a.apply_status(blind, 1.0)
	a.apply_status(blind, 5.0)
	b.apply_status(blind, 5.0)
	b.apply_status(blind, 1.0)
	assert_almost_eq(a.get_status_power(&"blindness"), b.get_status_power(&"blindness"), 0.0001,
		"1 then 5 == 5 then 1 (power)")
	var ma := _blind_modifiers(&"vision_range", _nodes[1])
	var mb := _blind_modifiers(&"vision_range", _nodes[2])
	assert_eq(ma.size(), 1)
	assert_eq(mb.size(), 1)
	if ma.size() == 1 and mb.size() == 1:
		assert_almost_eq(ma[0].value, mb[0].value, 0.0001, "1 then 5 == 5 then 1 (vision multiplier)")
		assert_almost_eq(ma[0].value, blind.factor_for(6.0), 0.0001, "one curve on the sum")

	_combat().apply_status(blind, 2.0)
	_combat().apply_status(blind, 2.0)
	assert_almost_eq(_combat().get_status_power(&"blindness"), 4.0, 0.0001,
		"2 then 2 = 4 — accumulated, uncapped")


func test_blind_factor_is_invariant_across_allocation_level() -> void:
	_set_local(&"vision_range", 10.0)
	_combat().apply_status(_def, 3.0)
	var mods := _blind_modifiers(&"vision_range")
	assert_eq(mods.size(), 1)
	if mods.is_empty():
		return
	assert_eq(mods[0]._local_scale_override(1, 3), StatModifier.UNSCALED,
		"a blinded node is not more or less blind for being allocated deeper")


func test_remove_status_strips_both_modifiers() -> void:
	for stat_id in _STATS:
		_set_local(stat_id, 10.0)
	_combat().apply_status(_def, 3.0)
	_combat().remove_status(&"blindness")
	for stat_id in _STATS:
		assert_almost_eq(_local(stat_id), 10.0, 0.001, "%s: back to baseline" % stat_id)
		assert_false(_has_blind_modifier(stat_id), "%s: modifier stripped" % stat_id)


# ── Shadow isolation ─────────────────────────────────────────────────────────

## A static (formula-less) modifier is SHARED between a live board and its
## clone (`StatBoard._localize`), so a shadow resolve must never edit a found
## modifier in place — that would write the live world before any
## AttackRecord replays (attack-timeline rule). Replace, never mutate.
func test_shadow_apply_never_writes_the_live_modifier() -> void:
	_set_local(&"vision_range", 10.0)
	_combat().apply_status(_def, 1.0)
	var live_mods := _blind_modifiers(&"vision_range")
	assert_eq(live_mods.size(), 1)
	if live_mods.is_empty():
		return
	var live_value: float = live_mods[0].value

	var shadow_world := _entity.get_combat().snapshot()
	_shadows.append(shadow_world)
	var shadow := shadow_world.shadow_for(_nodes[0])
	shadow.apply_status(_def, 3.0)

	assert_almost_eq(float(shadow.get_local_value(&"vision_range")), floorf(10.0 * _def.factor_for(4.0)), 0.01,
		"the shadow reads the accumulated power's factor")
	assert_almost_eq(live_mods[0].value, live_value, 0.001,
		"the live modifier instance is untouched by the shadow resolve")
	_assert_factor(&"vision_range", _def.factor_for(1.0), "live world unchanged")


# ── VisionSystem behaviour ───────────────────────────────────────────────────

func test_vision_shrinks_while_blinded_and_grows_back_at_expiry() -> void:
	var vision := VisionSystem.new()
	vision.graph = _graph
	add_child_autofree(vision)
	await get_tree().process_frame
	# Radius 1000 from N0 reaches N1 (600) but not N2 (1200); halved to 500 it
	# reaches neither. Sensing is switched off so only the radius decides.
	_set_local(&"vision_range", 1000.0)
	_set_local(&"sensor_range", 0.0)
	vision.viewers = [_entity]
	vision._recompute()
	assert_true(vision.is_visible(_nodes[1]), "baseline: N1 inside the radius")
	assert_false(vision.is_visible(_nodes[2]), "baseline: N2 outside the radius")

	_combat().apply_status(_def, 3.0)
	await get_tree().process_frame  # the debounced recompute, driven by the stat change alone
	assert_false(vision.is_visible(_nodes[1]), "blinded: N1 falls out of the halved radius")
	assert_true(vision.is_visible(_nodes[0]), "blinded: the owned node itself stays visible")

	for _i in 4:
		_combat().tick_statuses()
	await get_tree().process_frame
	assert_true(vision.is_visible(_nodes[1]), "expired: N1 is back inside the radius")


# ── Authored content loads and is wired (values are the owner's knobs) ───────

func test_authored_blindness_and_dazzle_load_and_are_in_the_debug_book() -> void:
	var blind := load("res://effects/status/blindness.tres") as BlindnessStatus
	assert_not_null(blind, "blindness.tres is a BlindnessStatus")
	if blind == null:
		return
	assert_eq(blind.id, &"blindness")
	assert_true(&"debuff" in blind.tags, "tagged as a debuff")
	assert_true(blind.power_max <= 0.0, "uncapped — depth is the curve's job, not a clamp")
	assert_eq(blind.reapply, StatusDef.Reapply.ACCUMULATE, "accumulating, so reapply commutes")
	assert_eq(blind.decay_mode, StatusDef.DecayMode.FRACTION, "a fractional fade")
	assert_gt(blind.floor_factor, 0.0)
	assert_lt(blind.floor_factor, 1.0, "a floor below 1 — blindness shrinks, never grows")
	assert_gt(blind.depth_k, 0.0)
	# display_max keeps the bar / tint on a 0..1 scale for an uncapped def.
	assert_gt(blind.display_max, 0.0, "an uncapped def authors a display anchor")
	assert_almost_eq(NodeStatus.new(blind, blind.display_max * 0.5).normalised(), 0.5, 0.0001)
	assert_almost_eq(NodeStatus.new(blind, blind.display_max * 10.0).normalised(), 1.0, 0.0001,
		"depth past the anchor saturates the bar")

	var dazzle := load("res://attack/spell/defs/dazzle.tres") as SpellDef
	assert_not_null(dazzle, "dazzle.tres is a SpellDef")
	if dazzle == null:
		return
	var applier: ApplyStatusEffect = null
	var has_damage := false
	for fx in dazzle.on_hit_effects:
		if fx is ApplyStatusEffect:
			applier = fx
		elif fx is DamageEffect:
			has_damage = true
	assert_true(has_damage, "dazzle also deals (a little) damage")
	assert_not_null(applier, "dazzle composes an ApplyStatusEffect")
	if applier != null:
		assert_eq(applier.def, blind, "…that applies the authored Blindness def")
		assert_gt(applier.power, 0.0)

	var book := load("res://entity/spellbook_debug.tres") as SpellBook
	assert_true(dazzle in book.spells, "dazzle is in the debug spellbook")

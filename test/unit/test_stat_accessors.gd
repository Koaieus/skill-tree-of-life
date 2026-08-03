extends GutTest

## #333 — StatFormula can read a pool's `current` (and other named stat bins)
## through `<stat_id>__<accessor>` tokens. The formula layer owns the token
## SYNTAX (split + base/accessor); the Stat owns the SEMANTICS (a per-subclass
## `accessors()` map). `get_input_ids()` strips back to base ids so a cycle
## through a pool read via `__current` is still caught by `StatBoard.cycle_from`.
## An unknown accessor warns and falls through — never silently wrong, never
## a hard crash mid-pipeline.
##
## Acceptance tests, in the issue author's order:
##   1. LinearFormula reads `health__current` (curr) vs `health` (cap), distinctly.
##   2. RatioFormula + ExpressionFormula likewise.
##   3. get_input_ids() returns the BASE id for a decorated token.
##   4. A cycle running through a pool read via `__current` is still caught.
##   5. read_accessor(&"nope") warns and returns get_value.
##   6. read_accessor(&"current") on a non-pool ScalarStat warns and falls through.
##   7. SkillPointStat resolves wounded/staked/used; SurplusPoolStat resolves
##      surplus/available.
##   8. Guard: every concrete Stat subclass's accessors() entry resolves non-null
##      against a fresh default instance — catches a renamed property before
##      the test passes, instead of letting a stale closure degrade silently.

const BOARD := preload("res://entity/default_entity_board.tres")
const SKILL_POINTS_DEF := preload("res://stats_system/defs/skill_points.tres")
const DEALLOC_DEF := preload("res://stats_system/defs/deallocation_points.tres")
const STRENGTH_DEF := preload("res://stats_system/defs/strength.tres")
const HEALTH_DEF := preload("res://stats_system/defs/health.tres")

var _board: StatBoard = null


func before_each() -> void:
	_board = BOARD.duplicate(true)
	# Deliberately NOT calling apply_intrinsics() in the shared setup: the
	# read-shape tests (1, 2) want `health.base_value` to *be* the cap, plain,
	# so they read cap == set value. The cycle test (case 4) opts IN to a
	# live intrinsics-bearing board via its own local apply call.


# --- helpers ----------------------------------------------------------------

func _linear(source: StringName) -> LinearFormula:
	var f := LinearFormula.new()
	f.source_stat_id = source
	return f


func _ratio(source: StringName, divisor: float) -> RatioFormula:
	var f := RatioFormula.new()
	f.source_stat_id = source
	f.divisor = divisor
	return f


func _expr(text: String, inputs: Array) -> ExpressionFormula:
	var f := ExpressionFormula.new()
	f.formula = text
	# StringName-array coercion in caller; we accept either shape here.
	if inputs.size() > 0 and inputs[0] is StringName:
		var typed: Array[StringName] = []
		for id in inputs:
			typed.append(id)
		f.inputs = typed
	else:
		f.inputs = inputs
	return f


## Stand a `health` pool to (cap, current) so the two halves read different
## values. `base_value` is the RAW cap door (it bypasses `_apply_max_change`),
## so writing it then `set_current` lands cleanly without heal-on-max increase
## firing on the test fixture.
func _set_health(cap: float, current: float) -> void:
	_board.health.base_value = cap
	_board.health.set_current(current)


# --- 1. LinearFormula reads current vs cap distinctly ------------------------

func test_linear_reads_pool_current_and_cap_distinctly() -> void:
	_set_health(10.0, 2.0)
	var f_cap := _linear(&"health")
	var f_cur := _linear(&"health__current")
	assert_eq(f_cap.compute(_board), 10.0, "bare token reads the cap")
	assert_eq(f_cur.compute(_board), 2.0, "decorated token reads current")


# --- 2. RatioFormula + ExpressionFormula likewise ---------------------------

func test_ratio_reads_pool_current_via_decorated_token() -> void:
	_set_health(10.0, 7.0)
	# divisor 1 collapses `floor(curr/1)` to `curr`, so curr vs cap read
	# distinctly even at the uninteresting divisor.
	assert_eq(_ratio(&"health", 1.0).compute(_board), 10.0, "bare reads cap")
	assert_eq(_ratio(&"health__current", 1.0).compute(_board), 7.0, "decorated reads current")
	# And at a non-trivial divisor so the floor() path is also exercised.
	assert_eq(_ratio(&"health__current", 3.0).compute(_board), 2.0, "floor(7/3) = 2")


func test_expression_reads_pool_current_via_decorated_token() -> void:
	_set_health(10.0, 7.0)
	# The variable name in the expression text IS the decorated token —
	# confirmed empirically parse+execute works (see #333 → Decisions).
	var f := _expr("health__current + 1", [&"health__current"])
	assert_eq(f.compute(_board), 8.0, "expression binds health__current to current")
	# Bare token in the same class reads the cap — distinctly different.
	var f_bare := _expr("health * 2", [&"health"])
	assert_eq(f_bare.compute(_board), 20.0, "bare token reads cap")


# --- 3. get_input_ids() returns BASE ids only -------------------------------

func test_linear_get_input_ids_strips_accessor() -> void:
	assert_eq(
		_linear(&"health__current").get_input_ids(), [&"health"] as Array[StringName],
		"decorated source contributes a base-id edge only"
	)
	assert_eq(
		_linear(&"health").get_input_ids(), [&"health"] as Array[StringName],
		"bare token is its own base"
	)


func test_ratio_get_input_ids_strips_accessor() -> void:
	assert_eq(
		_ratio(&"health__current", 5.0).get_input_ids(), [&"health"] as Array[StringName]
	)


func test_expression_get_input_ids_strips_each_input() -> void:
	var f := _expr("mana__current + strength", [&"mana__current", &"strength"])
	assert_eq(f.get_input_ids(), [&"mana", &"strength"] as Array[StringName])


func test_split_helpers_round_trip() -> void:
	# Direct trust in the syntactic seam the other cases ride on. Underscore-
	# bearing ids stay whole — `min_damage_taken` is ONE stat, not
	# `min_damage_taken` + an empty accessor.
	assert_eq(StatFormula.base_of(&"health"), &"health")
	assert_eq(StatFormula.accessor_of(&"health"), &"")
	assert_eq(StatFormula.base_of(&"health__current"), &"health")
	assert_eq(StatFormula.accessor_of(&"health__current"), &"current")
	assert_eq(StatFormula.base_of(&"min_damage_taken"), &"min_damage_taken")
	assert_eq(StatFormula.accessor_of(&"min_damage_taken"), &"")
	assert_eq(StatFormula.base_of(&"deallocation_points__available"), &"deallocation_points")
	assert_eq(StatFormula.accessor_of(&"deallocation_points__available"), &"available")
	assert_true(StatFormula.is_accessor_token(&"health__current"))
	assert_false(StatFormula.is_accessor_token(&"health"))


# --- 4. A cycle through a pool read via `__current` is still caught ----------

func test_cycle_through_pool_current_accessor_is_caught() -> void:
	# Intrinsics live for this test only — the planted modifier needs the
	# board's pipeline reachable from `cycle_from`. Pre-built WIP chain that
	# would feed through `armor` is not over-relied on; this test plants its
	# own chain start so it stays robust to changes elsewhere.
	_board.apply_intrinsics()

	# Plant a LIVE edge: armor depends on health (read via __current). The
	# accessor token resolves to base id `health` in get_input_ids(), so the
	# dependency edge `armor -> health` exists exactly as if the formula used
	# the bare `health` token. If `__current` had created a SEPARATE graph
	# vertex (`health__current`), the search rooted at the candidate's targets
	# would never see the planted edge and miss the cycle.
	var planted := StatModifier.new()
	planted.stat_id = &"armor"
	planted.formula = _linear(&"health__current")
	_board.add_modifier(planted)

	# Sanity: the live edge really reads health's current through __current
	# (not its cap) — the test would be tautological against a regressed
	# read_accessor that silently returned get_value() for the decorated
	# token. Compute via the formula directly because we added the modifier
	# via Stat.add_modifier (direct), which bypasses `bind` on the leaf — so
	# `planted._board` is null and `get_effective_value` would short-circuit.
	_set_health(10.0, 3.0)
	assert_eq(planted.formula.compute(_board), 3.0,
		"planted modifier reads health's current through __current")

	# Candidate: an edge back the other way — health <- armor. Together with
	# the planted file this closes `armor -> health -> armor`.
	var candidate := StatModifier.new()
	candidate.stat_id = &"health"
	candidate.formula = _linear(&"armor")
	var cycle := _board.cycle_from(candidate)
	assert_string_contains(cycle, "armor")
	assert_string_contains(cycle, "health")


# --- 5. read_accessor on an unknown name warns and falls through -------------

func test_unknown_accessor_warns_and_returns_get_value() -> void:
	var s := ScalarStat.new()
	s.definition = STRENGTH_DEF
	s.base_value = 5.0
	# Strength's value_type is INT, so get_value() coerces to int — the
	# unknown-accessor fall-through returns get_value() == 5 (int), not 5.0.
	var v: Variant = s.read_accessor(&"nope")
	assert_push_warning("no accessor 'nope'")
	assert_eq(v, 5, "unknown accessor degrades to get_value()")


# --- 6. read_accessor(&"current") on a non-pool warns ------------------------

func test_current_accessor_on_scalar_warns_and_falls_through() -> void:
	var s := ScalarStat.new()
	s.definition = STRENGTH_DEF
	s.base_value = 8.0
	var v: Variant = s.read_accessor(&"current")
	assert_push_warning("no accessor 'current'")
	assert_eq(v, 8, "non-Pool scalar degrades to get_value() for `current`")


# --- 7. SkillPointStat + SurplusPoolStat accessors resolve -------------------

func test_skill_point_stat_accessors_resolve() -> void:
	var sp := SkillPointStat.new()
	sp.definition = SKILL_POINTS_DEF
	# Build deterministic state: max 5, current 1, wounded 1, staked 1
	# → used = 5 - 1 - 1 - 1 = 2.
	sp.base_value = 5.0
	sp.current = 1.0
	sp.wounded = 1
	sp.staked = 1
	assert_eq(sp.used, 2, "fixture sanity")

	assert_eq(sp.read_accessor(&""), 5, "bare reads cap / max")
	assert_eq(sp.read_accessor(&"current"), 1.0, "current accessor")
	assert_eq(sp.read_accessor(&"wounded"), 1, "wounded accessor")
	assert_eq(sp.read_accessor(&"staked"), 1, "staked accessor")
	assert_eq(sp.read_accessor(&"used"), 2, "used accessor (derived)")


func test_surplus_pool_stat_accessors_resolve() -> void:
	var sp := SurplusPoolStat.new()
	sp.definition = DEALLOC_DEF
	sp.base_value = 3.0
	sp.current = 3.0
	sp.set_surplus(4)
	# available() == roundi(current) + surplus == 3 + 4 == 7
	assert_eq(sp.read_accessor(&""), 3, "bare reads cap")
	assert_eq(sp.read_accessor(&"current"), 3.0, "current accessor")
	assert_eq(sp.read_accessor(&"surplus"), 4, "surplus accessor")
	assert_eq(sp.read_accessor(&"available"), 7, "available accessor (derived)")


# --- 8. Guard: every concrete Stat subclass's accessors() resolves ----------

func test_every_stat_subclass_accessors_resolve_non_null() -> void:
	# Same posture as test_effect.gd's subclass walk (ProjectSettings
	# .get_global_class_list), not a hand-maintained preload list: a new Stat
	# subclass enrols itself here automatically. Two failure classes:
	#   - Renamed property (`wounded` -> `wound_count`): the typed-lambda
	#     member access `s.wounded` fails the script to parse at LOAD, the
	#     test fails loudly. (The static check is what we want; happens before
	#     the test even runs.)
	#   - Accessor that compiles but returns null against a fresh, unseeded
	#     instance (e.g. reads state not present without setup): the non-null
	#     assert here catches it.
	var scanned := 0
	for entry in ProjectSettings.get_global_class_list():
		var cls: String = entry.get("class", "")
		if cls == "Stat":
			continue  # @abstract — .new() would fail; not a concrete subclass
		if not _extends_stat(entry):
			continue
		var script: Script = load(entry["path"])
		var stat := script.new() as Stat
		assert_not_null(stat, "%s.new() produced a non-Stat" % cls)
		if stat == null:
			continue
		scanned += 1
		var accessors := stat.accessors()
		for accessor_name in accessors:
			var callable: Callable = accessors[accessor_name]
			var v = callable.call(stat)
			assert_not_null(
				v, "%s.accessors()[%s] returned null against a fresh instance" % [cls, accessor_name]
			)
	# Guard against the walk passing silently vacuously.
	assert_gt(scanned, 0, "found no concrete Stat subclasses — the walk is broken")


func _extends_stat(entry: Dictionary) -> bool:
	var base: String = entry.get("base", "")
	var guard := 0
	while base != "" and guard < 16:
		if base == "Stat":
			return true
		var found := false
		for e in ProjectSettings.get_global_class_list():
			if e["class"] == base:
				base = e.get("base", "")
				found = true
				break
		if not found:
			return false
		guard += 1
	return false


# --- Refusal: a decorated token is rejected as a registerable stat id --------

func test_ensure_stat_rejects_a_decorated_token() -> void:
	var sparse := StatBoard.new()
	var s := sparse._ensure_stat(&"health__current")
	assert_null(s, "decorated token must not mint a phantom stat")
	assert_push_warning("accessor token")


func test_add_modifier_rejects_a_decorated_target_stat_id() -> void:
	# An accessor token is a formula-read handle, not a stat id, so a modifier
	# whose `stat_id` is one is rejected at the add_modifier gate.
	var m := StatModifier.new()
	m.stat_id = &"health__current"
	m.value = 3.0
	_board.add_modifier(m)
	# Board untouched + a push_warning naming the rejection reason. (get_stat
	# returns null for `health__current` already, so the leaf is never applied.)
	assert_null(_board.get_stat(&"health__current"), "no phantom stat was minted")
	assert_push_warning("formula accessor token")
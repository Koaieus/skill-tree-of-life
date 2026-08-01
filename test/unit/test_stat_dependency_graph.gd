extends GutTest

## The formula dependency graph must be a DAG.
##
## A formula-bound modifier makes its `stat_id` depend on every id in
## `formula.get_input_ids()` — "mana depends on intelligence". Those edges form
## a graph, and that graph MUST be acyclic. Nothing enforced it before this file.
##
## `StatModifier._propagating` looks like it does, but it doesn't: it's a
## re-entrancy guard on ONE modifier's `_on_source_changed`, so a genuine A→B→A
## cycle doesn't error or hang — propagation just stops partway and the stats
## settle on a **silently wrong, evaluation-order-dependent** value. There is no
## symptom to notice. Hence a static check over the shipped content.
##
## Scope: the board's own `intrinsic_modifiers`, plus each core class's
## `modifiers` layered on top (a class's entries are applied to the same board,
## so they extend the same graph and can close a loop the board alone can't).
## Node-local modifiers are out of scope — they live on per-node boards.
##
## Runtime additions (looted modifiers) are covered by StatBoard.would_cycle
## (#322), a precondition on `add_modifier` — see the "runtime rejection"
## section below. The traversal itself (`adjacency_from` / `find_cycle`) has
## one home, `StatBoard`; this file only wraps it for the synthetic-cycle
## detector cases and the shipped-content DAG check.

const BOARD := preload("res://entity/default_entity_board.tres")

## How many CoreClass resources the check expects to find at minimum — a
## vacuity guard, not a count. A directory scan that matches nothing passes
## every assertion below in silence, so the scan has to prove it found content
## the same way `test_board_intrinsics_actually_form_a_graph` does. There were
## 5 authored classes when this was written; the floor sits below that so
## deleting one isn't a false alarm, but emptying the directory is.
const MIN_CORE_CLASSES := 3


## Thin wrappers over the shared StatBoard traversal (#322) — kept as
## `_adjacency` / `_find_cycle` so the detector + shipped-content tests below
## didn't need renaming at the call site.
func _adjacency(mods: Array) -> Dictionary:
	return StatBoard.adjacency_from(mods)


func _find_cycle(adjacency: Dictionary) -> String:
	return StatBoard.find_cycle(adjacency)


# --- The detector itself ------------------------------------------------------
# A "no cycle found" result is only worth something if the search can find one.

func _mod(stat_id: StringName, source_id: StringName) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	var f := LinearFormula.new()
	f.source_stat_id = source_id
	m.formula = f
	return m


func test_detector_catches_a_two_stat_cycle() -> void:
	var cycle := _find_cycle(_adjacency([_mod(&"a", &"b"), _mod(&"b", &"a")]))
	assert_string_contains(cycle, "a")
	assert_string_contains(cycle, "b")


func test_detector_catches_a_self_reference() -> void:
	assert_eq(_find_cycle(_adjacency([_mod(&"a", &"a")])), "a -> a")


func test_detector_catches_a_longer_loop() -> void:
	var mods := [_mod(&"a", &"b"), _mod(&"b", &"c"), _mod(&"c", &"a")]
	assert_ne(_find_cycle(_adjacency(mods)), "", "a -> b -> c -> a is a cycle")


func test_detector_passes_a_diamond() -> void:
	# Shared dependencies are not cycles — d is reached twice, legally.
	var mods := [_mod(&"a", &"b"), _mod(&"a", &"c"), _mod(&"b", &"d"), _mod(&"c", &"d")]
	assert_eq(_find_cycle(_adjacency(mods)), "", "a diamond is still a DAG")


# --- The shipped content ------------------------------------------------------

func test_board_intrinsics_are_acyclic() -> void:
	assert_eq(
		_find_cycle(_adjacency(BOARD.intrinsic_modifiers)), "",
		"default_entity_board's intrinsic formulas form a cycle"
	)


func test_board_intrinsics_actually_form_a_graph() -> void:
	# Guards against the whole suite passing vacuously if the intrinsics ever
	# stop being discoverable (a renamed field, an emptied array).
	assert_gt(
		_adjacency(BOARD.intrinsic_modifiers).size(), 5,
		"the board carries formula-bound intrinsics to check"
	)


func test_every_authored_core_class_is_acyclic_on_top_of_the_board() -> void:
	# Discovered from disk via CoreClass.load_all(), not a hand-maintained
	# preload list — authoring a new class enrols it here automatically. This is
	# the early warning that a class's modifiers conflict with a board intrinsic,
	# and it has to fire BEFORE anything is applied: at runtime, add_modifier
	# rejects whichever side arrives second, and it has no notion of who should
	# win (see the apply-order note in .claude/rules/stats-system.md).
	var classes := CoreClass.load_all()
	assert_gte(
		classes.size(), MIN_CORE_CLASSES,
		"found %d CoreClass resources in %s — did they move?" % [classes.size(), CoreClass.DIR]
	)
	for core in classes:
		var combined: Array = []
		combined.append_array(BOARD.intrinsic_modifiers)
		combined.append_array(core.modifiers)
		assert_eq(
			_find_cycle(_adjacency(combined)), "",
			"%s closes a dependency cycle against the board's intrinsics" % core.resource_path.get_file()
		)


# --- Runtime rejection (StatBoard.would_cycle / add_modifier, #322) -----------
# The static checks above cover shipped content; this is the case they can't —
# a modifier added at runtime (the #323 loot path) whose formula, once bound to
# THIS board, closes a loop against something already live. The board's own
# `mana` intrinsic (mana depends on intelligence, see default_entity_board.tres)
# is the real edge every case below closes a loop against.

## would_cycle reads what's actually APPLIED (Stat._modifiers via
## StatBoard.collect_formula_edges), not the authored `intrinsic_modifiers`
## array — so the
## fixture must apply_intrinsics() the same way Entity._ready() does, or the
## board carries the authored edges nowhere would_cycle can see them.
func _board() -> StatBoard:
	var board := BOARD.duplicate(true) as StatBoard
	board.apply_intrinsics()
	return board


## A candidate whose formula reads `mana` and targets `intelligence` closes
## intelligence -> mana -> intelligence against the board's shipped
## `mana` intrinsic (mana -> intelligence).
func _cycle_closing_candidate() -> StatModifier:
	var lin := LinearFormula.new()
	lin.source_stat_id = &"mana"
	var m := StatModifier.new()
	m.stat_id = &"intelligence"
	m.formula = lin
	return m


func test_would_cycle_true_for_a_candidate_that_closes_a_loop_against_the_board() -> void:
	var board := _board()
	assert_true(
		board.would_cycle(_cycle_closing_candidate()),
		"intelligence <- mana closes a loop against the board's mana <- intelligence intrinsic"
	)


func test_would_cycle_true_for_a_composite_bundle_whose_child_closes_the_loop() -> void:
	# A bundle can close a loop no single leaf does — cover it via a harmless
	# static sibling leaf alongside the one that actually cycles.
	var harmless := StatModifier.new()
	harmless.stat_id = &"strength"
	harmless.value = 3.0
	var bundle := CompositeStatModifier.new()
	bundle.children = [harmless, _cycle_closing_candidate()]
	var board := _board()
	assert_true(board.would_cycle(bundle), "a composite is checked leaf-by-leaf via flatten()")


func test_add_modifier_rejects_a_cycling_bundle_as_all_or_nothing() -> void:
	# Rejection must be atomic across the bundle: the innocent `harmless` leaf
	# must NOT slip through while only the cycling leaf is dropped.
	var harmless := StatModifier.new()
	harmless.stat_id = &"strength"
	harmless.value = 3.0
	var bundle := CompositeStatModifier.new()
	bundle.children = [harmless, _cycle_closing_candidate()]
	var board := _board()
	var strength_before: float = board.strength.value

	board.add_modifier(bundle)

	assert_eq(board.strength.value, strength_before, "the bundle's harmless leaf must not apply either")


func test_would_cycle_false_for_a_static_modifier() -> void:
	var board := _board()
	var m := StatModifier.new()
	m.stat_id = &"strength"
	m.value = 5.0
	assert_false(board.would_cycle(m), "a null-formula modifier can never cycle")


func test_would_cycle_false_for_a_formula_with_no_declared_inputs() -> void:
	# An ExpressionFormula authored with no inputs (a bare constant) has a
	# non-null formula but an empty get_input_ids() — the short-circuit must
	# catch this shape too, not just the null-formula case.
	var board := _board()
	var m := StatModifier.new()
	m.stat_id = &"strength"
	var f := ExpressionFormula.new()
	f.formula = "5"
	m.formula = f
	assert_false(board.would_cycle(m))


func test_add_modifier_rejects_a_cycle_closing_modifier_and_leaves_the_board_unchanged() -> void:
	var board := _board()
	var mana_before: float = board.mana.value
	var intelligence_before: float = board.intelligence.value
	var candidate := _cycle_closing_candidate()

	board.add_modifier(candidate)

	assert_eq(board.mana.value, mana_before, "rejected modifier must not perturb mana")
	assert_eq(board.intelligence.value, intelligence_before, "rejected modifier must not perturb intelligence")
	assert_false(
		board.get_stat(&"intelligence").has_modifier(candidate),
		"rejected modifier must never be attached to its target stat"
	)


func test_cycle_from_names_the_offending_path() -> void:
	# The path is what add_modifier reports — m.stat_id can't do the job (it is
	# empty on a composite, the case most worth diagnosing).
	var cycle := _board().cycle_from(_cycle_closing_candidate())
	assert_string_contains(cycle, "intelligence")
	assert_string_contains(cycle, "mana")


func test_cycle_from_diagnoses_a_bundle_whose_stat_id_is_vestigial() -> void:
	var bundle := CompositeStatModifier.new()
	bundle.children = [_cycle_closing_candidate()]
	assert_eq(bundle.stat_id, &"", "a composite's stat_id is inert — nothing to report from")
	assert_string_contains(_board().cycle_from(bundle), "mana")


func test_a_pre_existing_cycle_elsewhere_does_not_condemn_an_unrelated_modifier() -> void:
	# The search runs from the candidate's own targets, not every vertex. Plant
	# a strength <-> dexterity cycle through the one seam that bypasses the gate
	# (Stat.add_modifier direct), then offer an unrelated armor <- constitution
	# candidate: a whole-graph search would find the planted cycle and reject it.
	var board := _board()
	board.get_stat(&"strength").add_modifier(_mod(&"strength", &"dexterity"))
	board.get_stat(&"dexterity").add_modifier(_mod(&"dexterity", &"strength"))

	# Non-vacuity: armor -> constitution must actually lead somewhere, or the
	# DFS proves nothing by finding no cycle. The board's level intrinsic gives
	# constitution -> level, so the walk has real ground to cover before it ends.
	var live := {}
	board.collect_formula_edges(live)
	assert_true(live.has(&"constitution"), "constitution must carry live edges for this to test anything")

	assert_false(
		board.would_cycle(_mod(&"armor", &"constitution")),
		"a cycle the candidate is not part of must not reject it"
	)


func test_a_candidate_that_closes_a_loop_is_caught() -> void:
	# Only ONE direction is planted, so the cycle exists *only* with the
	# candidate — the assert would still pass on a live graph that was already
	# cyclic, which is what makes the one-edge fixture the honest one.
	var board := _board()
	board.get_stat(&"strength").add_modifier(_mod(&"strength", &"dexterity"))

	assert_false(
		board.would_cycle(_mod(&"armor", &"dexterity")),
		"strength -> dexterity alone is not a cycle"
	)
	assert_true(
		board.would_cycle(_mod(&"dexterity", &"strength")),
		"the candidate closes dexterity -> strength -> dexterity"
	)

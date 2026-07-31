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
## Runtime additions (looted modifiers, #TBD) can't be covered by a static test;
## they need the same traversal as an `add_modifier` precondition. This file is
## the shipped-content half.

const BOARD := preload("res://entity/default_entity_board.tres")

const CORE_CLASSES := {
	"balanced_core": preload("res://entity/core/balanced_core.tres"),
	"basic_enemy_core": preload("res://entity/core/basic_enemy_core.tres"),
	"ninja_core": preload("res://entity/core/ninja_core.tres"),
	"pacifist_core": preload("res://entity/core/pacifist_core.tres"),
	"serpent_core": preload("res://entity/core/serpent_core.tres"),
}


## `{stat_id: [depends_on_id, ...]}` — one entry per formula-bound leaf.
func _adjacency(mods: Array) -> Dictionary:
	var out := {}
	for leaf in StatModifier.flatten_all(mods):
		if leaf.formula == null:
			continue
		var deps: Array = out.get(leaf.stat_id, [])
		for input_id in leaf.formula.get_input_ids():
			if not deps.has(input_id):
				deps.append(input_id)
		out[leaf.stat_id] = deps
	return out


## Depth-first three-colour search. Returns the offending path
## ("a -> b -> a") on the first cycle found, or "" when the graph is acyclic.
func _find_cycle(adjacency: Dictionary) -> String:
	var done := {}       # fully explored — can never be part of a new cycle
	var on_stack := {}   # in the current DFS path — a hit here IS the cycle
	var path: Array[StringName] = []
	for root in adjacency.keys():
		var found := _visit(root, adjacency, done, on_stack, path)
		if not found.is_empty():
			return found
	return ""


func _visit(
	id: StringName,
	adjacency: Dictionary,
	done: Dictionary,
	on_stack: Dictionary,
	path: Array[StringName]
) -> String:
	if done.has(id):
		return ""
	if on_stack.has(id):
		var from := path.find(id)
		var loop := path.slice(from) if from >= 0 else path.duplicate()
		loop.append(id)
		return " -> ".join(loop)
	on_stack[id] = true
	path.append(id)
	for dep in adjacency.get(id, []):
		var found := _visit(dep, adjacency, done, on_stack, path)
		if not found.is_empty():
			return found
	path.pop_back()
	on_stack.erase(id)
	done[id] = true
	return ""


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


func test_each_core_class_is_acyclic_on_top_of_the_board() -> void:
	for name in CORE_CLASSES:
		var core: CoreClass = CORE_CLASSES[name]
		var combined: Array = []
		combined.append_array(BOARD.intrinsic_modifiers)
		combined.append_array(core.modifiers)
		assert_eq(
			_find_cycle(_adjacency(combined)), "",
			"%s closes a dependency cycle against the board's intrinsics" % name
		)

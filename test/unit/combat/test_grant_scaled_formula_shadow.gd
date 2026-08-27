extends GutTest

## #635 — a symptom of the same defect #623 fixes: `EffectContext.grant_scaled`
## used to bind the duplicate via `grant()` and THEN write `handle.value = mod.value
## * scale` on the object it was holding. On a CLONE/shadow board,
## `StatBoard._localize` hands the binder a PRIVATE copy the moment the modifier
## carries a `formula` (`stats_system/stat_board.gd:401-408`) — so that post-bind
## write landed on an object nobody applied, and the plain modifier's scale was
## silently lost. No composite needed to see it; a lone formula-bearing leaf on
## a clone board is enough.
##
## #623's fix (scale the duplicate's leaves BEFORE handing it to `add_modifier` /
## `add_local_modifier`) closes this incidentally: whatever `_localize` does to
## the duplicate afterward, it copies a value that is already correct.
##
## Per the swarmify decision on #623 (absorbing #635): this is that issue's
## acceptance 5b, its own failing test, kept in its own file since it exercises
## `EffectContext` directly rather than through `AuraEffect`.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _entity: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_entity = autofree(Entity.new())
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)
	await get_tree().process_frame


func _linear(source_id: StringName) -> StatFormula:
	var f := LinearFormula.new()
	f.source_stat_id = source_id
	return f


## Must fail on master: the scaled value never reaches the shadow board's
## `strength` stat at all (the mutated handle is discarded), so the result
## comes back at the UNSCALED contribution instead of the scaled one.
func test_grant_scaled_applies_the_scaled_value_for_a_formula_modifier_on_a_shadow_board() -> void:
	var shadow := _entity.get_combat().snapshot()
	# constitution defaults to 0.0 (StatDef.default_value) — a formula reading
	# it as-is would multiply every scale by zero and pass vacuously whether
	# the bug is present or not. Give it a real value first.
	shadow.board().get_stat(&"constitution").base_value = 5.0
	var ctx := EffectContext.new(shadow, EffectInstance.new())

	var mod := StatModifier.new()
	mod.stat_id = &"strength"
	mod.operation = StatModifier.Operation.ADD_BASE
	mod.value = 1.0
	mod.formula = _linear(&"constitution")

	var con := float(shadow.board().get_stat(&"constitution").get_value())
	var str_before := float(shadow.board().get_stat(&"strength").get_value())

	ctx.grant_scaled(mod, 4.0)

	assert_almost_eq(float(shadow.board().get_stat(&"strength").get_value()),
			str_before + 4.0 * con, 0.001,
			"a scaled formula-bearing modifier must apply at its scaled value on a shadow board")
	shadow.free_shadow()


## The authored modifier itself must come out untouched — same discipline as
## #623 acceptance 4, for the plain-modifier path.
func test_grant_scaled_never_mutates_the_authored_formula_modifier() -> void:
	var shadow := _entity.get_combat().snapshot()
	var ctx := EffectContext.new(shadow, EffectInstance.new())

	var mod := StatModifier.new()
	mod.stat_id = &"strength"
	mod.operation = StatModifier.Operation.ADD_BASE
	mod.value = 1.0
	mod.formula = _linear(&"constitution")

	ctx.grant_scaled(mod, 4.0)

	assert_eq(mod.value, 1.0, "the authored/live handle's own value must be untouched")
	shadow.free_shadow()

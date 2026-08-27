@tool
class_name EffectReadoutPanel
extends FanPanel

## Tooltip V2 (#621) — the aura|effect readout: every currently-affecting
## aura/effect on the hovered node, one row per (effect, leaf modifier) pair
## from [method NodeEffectReadout.gather]. Rendered through [SlabRow] — #588's
## generic "tinted text" vocabulary, reused rather than inventing a new row
## component (the issue's own decision).
##
## [b]HIDING RULE (settled).[/b] A row hides when its EFFECTIVE value
## ([method StatModifier.get_effective_value] — never the raw `.value`; a
## formula-bearing modifier's coefficient is not what the node is actually
## getting) DISPLAYS as its operation's neutral element: 0 for
## ADD_BASE/ADD_BONUS/INCREASE, 1 for MULTIPLY. `SET` never hides — it has no
## neutral, per [method StatModifier.format]'s own pipeline doc. "Displays as"
## goes through [method StatDef.format_number] (#622, this issue's own
## dependency) — the SAME rounding the row itself would render with, so a
## value reading "+0" on screen hides even when its raw float is 0.004, and a
## value that reads real never hides just because it's a hair off its literal
## neutral. A `×0` MULTIPLY is annihilation, not the neutral (`×1` is) — it
## is never a hide candidate.
##
## [b]ROLLUP (owner comment, 2026-08-27).[/b] Individually-hidden rows are
## grouped by `(stat_id, operation)`. If the GROUP's own combined contribution
## — summed for ADD_BASE/ADD_BONUS/INCREASE, multiplied for MULTIPLY, the same
## composition each op uses in the live pipeline (see [method StatModifier]'s
## own pipeline doc) — displays as non-neutral, ONE rolled-up row replaces the
## whole group instead of it vanishing silently (ten `+0`s that sum to a real
## `+4`). A single hidden row is its own "group of one": its combined value
## equals its own already-neutral value, so it degrades back to a true hide,
## matching the issue's ten-row example rather than a one-row false positive.
##
## [b]"Does this affect me" (in scope, mechanism only — no acceptance test
## pins the visual).[/b] Per [method SkillNode.ownership_bit] — never
## `owned_by == entity` — a row whose [member NodeEffectReadout.source_entity]
## reads HOSTILE relative to the hovered node tints redder, so an intruding
## enemy aura reads differently from the territory's own. Kept minimal
## (retint an existing [SlabRow], no new chrome) since #621 leaves the exact
## rendering open.

const _SLAB_ROW_SCENE: PackedScene = preload("res://ui/tooltip_fan/slab_row.tscn")

const _ROW_STAGGER_STEP := 0.12
const _ROW_STAGGER_CAP := 0.85

## Rollup rows read as an aggregate, not an ordinary boon — same reasoning as
## GrantedModifiersRoot's muted empty-state tone, one tier brighter since this
## one is still a real (if summarized) number.
const _ROLLUP_TINT := Color(0.6, 0.62, 0.68)

## How far a HOSTILE-sourced row's tint shifts toward red (#621's "does this
## affect me"). 0 would be inert; kept modest so the row still reads as its
## stat's own colour first.
const _HOSTILE_MIX := 0.35
const _HOSTILE_TINT := Color(0.9, 0.25, 0.25)

var _bound_node: SkillNode = null
var _bound_graph: Graph = null
var _row_setters: Array[Callable] = []
var _has_rows := false


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_header.bind("Effects")


## Public entry point (#621).
func bind(node: SkillNode, graph: Graph) -> void:
	_bound_node = node
	_bound_graph = graph
	_rebuild_rows()


## False when nothing currently affects the node — no empty box, matching
## every other crown panel's [method FanPanel.has_content] contract (unlike
## [GrantedModifiersRoot], which is deliberately exempt).
func has_content() -> bool:
	return _has_rows


func _rebuild_rows() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_row_setters.clear()
	_has_rows = false
	if _bound_node == null or _bound_graph == null:
		return

	var shown: Array[Dictionary] = []
	var hidden_by_group: Dictionary = {}  # "<stat_id>|<op>" -> Array[NodeEffectReadout]

	for entry in NodeEffectReadout.gather(_bound_node, _bound_graph):
		var m := entry.modifier
		var def: StatDef = StatRegistry.get_def(m.stat_id)
		if def == null:
			continue  # no def, nothing honest to render (name, tint, type)
		var effective := m.get_effective_value(_bound_node.node_board)
		if m.operation != StatModifier.Operation.SET \
				and _displays_as_neutral(m.operation, effective, def.value_type):
			var key := _group_key(m.stat_id, m.operation)
			if not hidden_by_group.has(key):
				hidden_by_group[key] = []
			(hidden_by_group[key] as Array).append(entry)
			continue
		shown.append(_build_row(entry, def))

	for key in hidden_by_group:
		var group: Array = hidden_by_group[key]
		var first: NodeEffectReadout = group[0]
		var stat_id: StringName = first.modifier.stat_id
		var op: StatModifier.Operation = first.modifier.operation
		var def: StatDef = StatRegistry.get_def(stat_id)
		var combined := _combine(op, group)
		if _displays_as_neutral(op, combined, def.value_type):
			continue  # negligible in aggregate too — hide for real
		shown.append(_build_rollup_row(stat_id, op, combined, group.size(), def))

	for row_data in shown:
		var row := _SLAB_ROW_SCENE.instantiate() as SlabRow
		_rows.add_child(row)
		row.bind_text(row_data["text"], row_data["tint"])
		_row_setters.append(row.set_progress)
	_has_rows = not shown.is_empty()
	_apply_row_stagger()


func _group_key(stat_id: StringName, op: StatModifier.Operation) -> String:
	return "%s|%d" % [stat_id, op]


## Whether [param v] renders identically to the operation's neutral element
## through the stat's OWN declared type — the shared #622 rounding, so a value
## that reads "+0"/"×1" on screen hides even when its raw float is a hair off.
func _displays_as_neutral(op: StatModifier.Operation, v: float, value_type: StatDef.ValueType) -> bool:
	var neutral := 1.0 if op == StatModifier.Operation.MULTIPLY else 0.0
	return StatDef.format_number(value_type, v) == StatDef.format_number(value_type, neutral)


## The group's own combined contribution, composed the same way the live
## pipeline composes that operation (`Σ ADD_BASE`/`Σ INCREASE`/`Π MULTIPLY` —
## see [method StatModifier]'s class doc) — never a plain sum for MULTIPLY,
## which would answer a different question.
func _combine(op: StatModifier.Operation, group: Array) -> float:
	if op == StatModifier.Operation.MULTIPLY:
		var product := 1.0
		for entry in group:
			product *= (entry as NodeEffectReadout).modifier.get_effective_value(_bound_node.node_board)
		return product
	var total := 0.0
	for entry in group:
		total += (entry as NodeEffectReadout).modifier.get_effective_value(_bound_node.node_board)
	return total


func _build_row(entry: NodeEffectReadout, def: StatDef) -> Dictionary:
	var effect_name := "Effect"
	if entry.effect != null and not entry.effect.display_name.is_empty():
		effect_name = entry.effect.display_name
	var text := "%s: %s" % [effect_name, entry.modifier.format_effective(_bound_node.node_board)]
	return {"text": text, "tint": _row_tint(def.tint_color, _is_hostile(entry.source_entity))}


func _build_rollup_row(stat_id: StringName, op: StatModifier.Operation, combined: float, count: int, def: StatDef) -> Dictionary:
	# A bare (formula-less) synthetic modifier reuses format_effective()'s
	# grammar for free instead of re-deriving the op-text switch a third time
	# (StatModifier._format_value already has it; contribution_text() is the
	# other one) — get_effective_value(null) on a formula-less modifier is
	# just `value`, so `combined` renders exactly.
	var synthetic := StatModifier.new()
	synthetic.stat_id = stat_id
	synthetic.operation = op
	synthetic.value = combined
	var text := "%d minor sources: %s" % [count, synthetic.format_effective()]
	return {"text": text, "tint": _ROLLUP_TINT}


## #621's "does this affect me": HOSTILE per [method SkillNode.ownership_bit],
## relative to the hovered node — never `owned_by == entity`. Answers "is this
## effect's source at odds with whoever holds this territory", which stays
## meaningful even when the hovering player owns neither side (a
## third-party's node caught between two auras).
func _is_hostile(source_entity: Entity) -> bool:
	if _bound_node == null or source_entity == null:
		return false
	return (_bound_node.ownership_bit(source_entity) & SkillNode.Ownership.HOSTILE) != 0


func _row_tint(base: Color, hostile: bool) -> Color:
	return base.lerp(_HOSTILE_TINT, _HOSTILE_MIX) if hostile else base


func _apply_progress() -> void:
	super._apply_progress()
	_apply_row_stagger()


func _apply_row_stagger() -> void:
	for i in _row_setters.size():
		var delay := clampf(i * _ROW_STAGGER_STEP, 0.0, _ROW_STAGGER_CAP)
		var span := 1.0 - delay
		var row_t := clampf((progress - delay) / span, 0.0, 1.0) if span > 0.0 else progress
		_row_setters[i].call(row_t)

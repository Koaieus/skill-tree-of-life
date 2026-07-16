@tool
class_name StatModifier
extends Resource

## The designer-loop atom: pick a stat (by id), pick an op, enter a value,
## optionally attach a formula. Sits on a SkillNode's `modifiers` or on a
## StatBoard's `intrinsic_modifiers`. The runtime carrier for modifier state
## — *not* an immutable schema (those are StatDef / PoolStatDef under defs/).
##
## Effective value:
##   formula == null   → value                       (static modifier)
##   formula != null   → value * formula.compute()   (derived modifier)
##
## `value` defaults to 1.0 so it acts as the identity in both branches — a
## bare formula-only modifier reads its formula straight through, and a bare
## static modifier contributes at least something.
##
## A live `value` edit fires `Resource.changed`; Stat.add_modifier wires that
## into `_on_dependent_modifier_changed`. Formula-driven source updates flow
## through the same path via `_on_source_changed → emit_changed()`. No manual
## dirty-marking required.
##
## Pipeline (see Stat.get_value):
##   SET (if present) returns immediately — highest `priority` wins,
##   ties broken by insertion order (last-in wins).
##   Otherwise:
##     result = (base + Σ ADD_BASE)
##           × (1 + Σ INCREASE / 100)
##           × Π MULTIPLY
##           + Σ ADD_BONUS
##   Then coerced to definition.value_type (INT rounds once, here).
##
## Value scales:
##   ADD_BASE / ADD_BONUS : raw amount       (value =  4   →  +4)
##   INCREASE             : percent points   (value = 20   →  +20%; 5× gives ×2)
##   MULTIPLY             : raw multiplier   (value =  1.5 →  ×1.5; 0.5 acts as ÷2)
##   SET                  : the result       (value = 13   →  =13, pipeline bypassed)
##
## WARNING: modifiers with a non-null `formula` carry mutable binding state
## (_board, _bound_sources, _propagating) and MUST NOT be shared across
## entities. Call .duplicate(true) on assignment. apply_intrinsics() does this
## automatically; manual `add_modifier` callers must handle it themselves.

enum Operation {
	## +X to base, before multipliers. Scales with INCREASE and MULTIPLY.
	## The default — most permanent build sources (passives, allocated nodes) want this.
	ADD_BASE,
	## +X% additive percent (PoE "increased"). All INCREASE mods sum into one
	## (1 + Σ/100) multiplier — five +20% give +100% (×2), not (1.2)⁵ (≈×2.49).
	INCREASE,
	## ×X multiplicative (PoE "more"). Each MULTIPLY stacks independently with
	## every other MULTIPLY. value < 1 acts as a divide.
	MULTIPLY,
	## +X to result, after all multipliers. Use for flat sources that should
	## NOT scale with the build's % increases (loot trinkets, leech caps, etc.).
	ADD_BONUS,
	## =X override. Bypasses the pipeline entirely. Highest `priority` wins
	## among multiple SETs; ties broken by insertion order (last-in wins).
	SET,
}


@export var stat_id: StringName = &""
@export var operation: Operation = Operation.ADD_BASE
@export var value: float = 1.0:
	set(v):
		if v == value:
			return
		value = v
		emit_changed()
## Optional. When set, effective value becomes `value * formula.compute(board)`,
## so `value` reads as the coefficient and the formula contributes the variable
## part. When null, effective value is just `value` (plain static modifier).
@export var formula: StatFormula = null
## Tie-breaker — currently only consulted for SET (the only op where
## composition order matters). Higher wins.
@export var priority: int = 0


var _board: StatBoard = null
var _bound_sources: Array[Stat] = []
var _propagating: bool = false


## Returns the modifier's effective value. When a formula is bound, scales it
## by `value` so the same field serves both branches: bare-formula reads pass
## through (value=1), explicit coefficients show up as the modifier's `value`.
func get_effective_value() -> float:
	if formula != null and _board != null:
		return value * formula.compute(_board)
	return value


## The concrete leaf modifier(s) this stands for when it is APPLIED to a board
## or listed in a fully-expanded UI context. A plain modifier is its own
## singleton; [CompositeStatModifier] overrides this to expand its children
## (recursively). This is the seam the #183 bundle feature turns on:
## StatBoard.add_modifier / remove_modifier and the flattening display sites
## call it, while the STORAGE/authoring/loot arrays keep a composite whole (one
## entry, one lootable unit). A leaf pays nothing — one-element array, no state.
func flatten() -> Array[StatModifier]:
	return [self]


## List-level flatten: expand every [CompositeStatModifier] in `mods` into its
## leaves (recursively), leaving plain modifiers as-is and skipping nulls. For
## "touch every leaf" contexts that iterate a STORED `Array[StatModifier]` and
## apply/emit per entry (per-modifier floaters, node-local apply). `mods` is
## untyped so an `Array[StatModifier]` passes without a cast.
static func flatten_all(mods: Array) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for m in mods:
		if m != null:
			out.append_array(m.flatten())
	return out


## True when this modifier's value is derived from `source_id` through its
## formula — i.e. `source_id` is one of the stats the formula reads. Answers
## "which of these scale with X?" without a marker field: the formula's declared
## inputs already are the answer, and they survive `duplicate(true)`.
##
## Asks every leaf via flatten(), so a [CompositeStatModifier] reports true when
## ANY child scales — matching the way a bundle is applied and looted as a unit.
##
## The `level` case drives both sides of #194: the HUD lists level-scaled
## modifiers, LootSystem excludes them.
func scales_with(source_id: StringName) -> bool:
	for leaf in flatten():
		if leaf.formula != null and leaf.formula.get_input_ids().has(source_id):
			return true
	return false


## A short, op-aware string for THIS modifier's own contribution — "+10",
## "+20%", "×1.5", "=13". The stat label is NOT included (callers append the
## StatDef display name). Uses get_effective_value() so a formula-bound mod
## shows its real contribution rather than the bare coefficient. Drives the
## #70 floaters; see the "Value scales" table above for the op semantics.
func contribution_text() -> String:
	var v := get_effective_value()
	match operation:
		Operation.ADD_BASE, Operation.ADD_BONUS:
			return "%+d" % roundi(v)
		Operation.INCREASE:
			return "%+d%%" % roundi(v)
		Operation.MULTIPLY:
			return "×%s" % _trim(v)
		Operation.SET:
			return "=%s" % _trim(v)
	return ""


## Render a float without trailing ".00" — whole values print as ints.
static func _trim(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return "%d" % roundi(v)
	return ("%.2f" % v).trim_suffix("0")  # 1.50 → "1.5", 1.25 stays


## Subscribe to the formula's source stats so changes there propagate to this
## modifier (and onward to its target stat via emit_changed()). No-op when
## formula is null — static modifiers pay zero binding cost.
func bind(board: StatBoard) -> void:
	_board = board
	if formula == null:
		return
	for id in formula.get_input_ids():
		var s := board.get_stat(id)
		if s == null:
			push_warning("StatModifier: formula source stat '%s' not found in board" % id)
			continue
		if not s.value_changed.is_connected(_on_source_changed):
			s.value_changed.connect(_on_source_changed)
		_bound_sources.append(s)


func unbind() -> void:
	for s in _bound_sources:
		if s.value_changed.is_connected(_on_source_changed):
			s.value_changed.disconnect(_on_source_changed)
	_bound_sources.clear()
	_board = null


func _on_source_changed() -> void:
	if _propagating:
		return  # cycle guard: stops A→B→A from looping indefinitely
	_propagating = true
	emit_changed()
	_propagating = false

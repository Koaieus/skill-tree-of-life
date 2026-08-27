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
## A `StatModifier` instance can be applied to any number of `StatBoard`s at
## once (#377) — binding state lives on the board (`StatBoard.bind_modifier`/
## `unbind_modifier`), not here, so sharing across entities is safe.

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


## Re-entrancy guard on THIS instance's own [method _on_source_changed] — stops
## A→B→A from looping indefinitely within one propagation. Not board-scoped:
## the guard is about the call stack, not which board triggered it, so it
## doesn't move even though binding itself now lives on [StatBoard] (#377).
var _propagating: bool = false


## Opt-out / custom-scaling seam for SkillNode's local-scale mutator (#376).
## Default returns `null` = follow the universal per-operation law. Overrides
## return one of:
##   - a Float: the modifier's new `value`, outright;
##   - [constant UNSCALED]: invariant across allocation_level;
##   - an Array[StatModifier]: a composition mutation — the scaled leaf-set
##     that replaces this modifier's applied contribution on the board (the
##     CompositeStatModifier / Effect "1 effect becomes 2" case, decision 8).
## Any other return is rejected with a push_warning by the mutator, which
## falls through to the universal law.
const UNSCALED := &"unscaled"


func _local_scale_override(_old_al: int, _new_al: int) -> Variant:
	return null


## Returns the modifier's effective value. When a formula is present, scales
## it by `value` so the same field serves both branches: bare-formula reads
## pass through (value=1), explicit coefficients show up as the modifier's
## `value`. `board` is the board to read formula inputs from — callers that
## don't have one (a modifier not currently applied anywhere) get the static
## fallback, same as an unbound modifier always has.
func get_effective_value(board: StatBoard = null) -> float:
	if formula != null and board != null:
		return value * formula.compute(board)
	return value


## The concrete leaf modifier(s) this stands for when it is APPLIED to a board
## or listed in a fully-expanded UI context. A plain modifier is its own
## singleton; [CompositeStatModifier] overrides this to expand its children
## (recursively). This is the seam the #183 bundle feature turns on:
## StatBoard.add_modifier / remove_modifier and the flattening display sites
## call it, while the STORAGE/authoring/loot arrays keep a composite whole (one
## entry, one lootable unit). A leaf pays nothing — one-element array, no state.
## ── Wire form (#522) ─────────────────────────────────────────────────────────
## Loot travels BY VALUE. The owner call on #522 settled this against pointing
## at shared state with a locator: two of the three loot buckets read the
## VICTIM'S OWN board (`Entity.core_modifiers`, `StatBoard.intrinsic_modifiers`),
## which a peer holds only partially and possibly stale — so an index into it is
## a silent mis-grant rather than a loud failure. Sending the modifier itself is
## a few hundred bytes, and [method LootSystem._draw_payload] already mints
## detached copies (`duplicate(true)`), so this is that same operation with a
## different target.
##
## The `formula` is carried as its own tagged block, NOT dropped: #323 makes
## stealing a level-scaler the intended roguelite loop, so a wire format that
## cannot carry a [StatFormula] guts the feature rather than trimming an edge.
##
## Decoding lives on [StatModifierCodec] rather than here, for the same
## parse-time-cycle reason [CommandCodec] is separate from [Command]: a
## `StatModifier` naming `CompositeStatModifier` (which extends it) is a cycle.

## This modifier's wire form. [CompositeStatModifier] overrides and adds its
## children — the same `super()`-and-extend shape [Command.to_dict] uses.
func to_dict() -> Dictionary:
	return {
		"type": StatModifierCodec.TAG_MOD,
		"stat_id": String(stat_id),
		"operation": int(operation),
		"value": value,
		"priority": priority,
		"formula": formula.to_dict() if formula != null else null,
	}


## Read the fields this level owns off [param d]. Overridden by
## [CompositeStatModifier]; called by [StatModifierCodec] after it has minted
## the right concrete type.
func read_dict(d: Dictionary) -> void:
	stat_id = StringName(d.get("stat_id", &""))
	operation = int(d.get("operation", Operation.ADD_BASE)) as Operation
	value = float(d.get("value", 1.0))
	priority = int(d.get("priority", 0))
	formula = StatModifierCodec.formula_from_dict(d.get("formula"))


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


## Fold this modifier's dependency edges — `stat_id -> each formula input` —
## into a `{stat_id: [depends_on_id, ...]}` graph, IN PLACE (#322). The single
## definition of "what an edge is"; every consumer (the live board graph, the
## static shipped-content check, a candidate under test) folds through here.
##
## In-place and virtual rather than "return my edges": a plain modifier adds at
## most one entry and allocates nothing, and [CompositeStatModifier] overrides
## to recurse into its children — the same seam [method flatten] uses, without
## flatten's per-leaf array. A modifier with no formula, or a formula with no
## declared inputs (a bare constant), contributes NO edge and therefore no
## vertex: it cannot participate in a cycle.
func collect_formula_edges(out: Dictionary) -> void:
	if formula == null:
		return
	var inputs := formula.get_input_ids()
	if inputs.is_empty():
		return
	var deps: Array = out.get(stat_id, [])
	for input_id in inputs:
		if not deps.has(input_id):
			deps.append(input_id)
	out[stat_id] = deps


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
## "+20%", "×1.5", "=13". The stat label is NOT included — this is the value
## fragment only. Contrast with [method format], which returns the FULL
## sentence (stat name included) and is the single home for that grammar;
## this method's own op-formatting and tests are unchanged by that split.
## Uses get_effective_value() so a formula-bound mod shows its real
## contribution rather than the bare coefficient — pass [param board] for a
## live formula read; omit it for the same static-coefficient fallback an
## unbound modifier always had. See the "Value scales" table above for op
## semantics.
func contribution_text(board: StatBoard = null) -> String:
	var v := get_effective_value(board)
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


## The FULL sentence for this modifier — stat name included. The single home
## for modifier-to-words grammar (#305): every UI that used to hand-append a
## StatDef label to [method contribution_text] now calls this instead.
##
## Stat name comes from [member StatDef.modifier_name] (falls back to
## [member StatDef.display_name], then to the bare `stat_id` when the def
## can't be resolved — StatRegistry is @tool + autoload so this works
## in-editor too). [member StatDef.display_as_percent] scales the value ×100
## with a "%" suffix, but ONLY for ADD_BASE / ADD_BONUS / SET — INCREASE and
## MULTIPLY values are already percent-points / raw multipliers and must not
## be rescaled (see the field's own docstring).
##
## | Op | Renders as |
## |---|---|
## | ADD_BASE  | "+4 Intelligence" |
## | INCREASE  | "+18% increased Intelligence" |
## | MULTIPLY  | "×1.3 Magic Potency" |
## | ADD_BONUS | "+3 bonus Armor" |
## | SET       | "Armor is 3" |
##
## A formula-bound modifier appends the formula's own qualifier — "+1 Blade
## Size **per 20 STR**" (#289) — and renders `value` (the COEFFICIENT) rather
## than the effective value, because the clause now carries the variable part.
## Without the clause the coefficient was actively misleading: an unbound
## keystone modifier printed a bare "+1 Blade Size" that meant nothing, which
## is what #231's audit found. Use [method contribution_text] when you want
## the live computed number instead.
func format() -> String:
	var def: StatDef = StatRegistry.get_def(stat_id)
	var name: String = String(stat_id)
	var as_percent := false
	var value_type := StatDef.ValueType.INT
	if def != null:
		name = def.modifier_name if not def.modifier_name.is_empty() else def.display_name
		as_percent = def.display_as_percent
		value_type = def.value_type
	if formula != null:
		return _with_per_clause(_format_value(name, as_percent, value_type, value))
	return _format_value(name, as_percent, value_type, get_effective_value())


## The same full sentence as [method format], but ALWAYS through
## [method get_effective_value] — never the formula coefficient + "per"
## clause branch. [method format] intentionally shows the coefficient for a
## formula-bound modifier (a definition reads better next to its rate); a
## per-node effect readout (#621) wants the opposite: what this specific
## grant is contributing RIGHT NOW, coefficient or not. [param board] is
## passed straight to [method get_effective_value] — the board to read
## formula inputs from, same as that method's own parameter.
func format_effective(board: StatBoard = null) -> String:
	var def: StatDef = StatRegistry.get_def(stat_id)
	var name: String = String(stat_id)
	var as_percent := false
	var value_type := StatDef.ValueType.INT
	if def != null:
		name = def.modifier_name if not def.modifier_name.is_empty() else def.display_name
		as_percent = def.display_as_percent
		value_type = def.value_type
	return _format_value(name, as_percent, value_type, get_effective_value(board))


## Appends " per <phrase>" to `sentence` when the bound formula offers one.
## An empty phrase (an [ExpressionFormula] nobody authored yet) degrades to
## the bare sentence rather than to a dangling "per".
func _with_per_clause(sentence: String) -> String:
	var phrase := formula.describe_per()
	return sentence if phrase.is_empty() else "%s per %s" % [sentence, phrase]


## `value_type`-aware (#622) — ADD_BASE / INCREASE / ADD_BONUS route their
## non-percent value through [method StatDef.format_number] (via [method _signed])
## so a FLOAT stat's decimals survive instead of an unconditional `roundi()`.
## `display_as_percent` stays on its own `roundi(v * 100.0)` path, unchanged
## (#622 decision: it composes with the type rule rather than replacing it —
## a percent display is already whole-number-of-percent regardless of the
## underlying stat's type). MULTIPLY / SET keep `_trim(v)` untouched — neither
## is type-aware; see [StatDef.format_number]'s docstring for why.
func _format_value(name: String, as_percent: bool, value_type: StatDef.ValueType, v: float) -> String:
	match operation:
		Operation.ADD_BASE:
			if as_percent:
				return "%+d%% %s" % [roundi(v * 100.0), name]
			return "%s %s" % [_signed(value_type, v), name]
		Operation.INCREASE:
			return "%s%% increased %s" % [_signed(value_type, v), name]
		Operation.MULTIPLY:
			return "×%s %s" % [_trim(v), name]
		Operation.ADD_BONUS:
			if as_percent:
				return "%+d%% bonus %s" % [roundi(v * 100.0), name]
			return "%s bonus %s" % [_signed(value_type, v), name]
		Operation.SET:
			if as_percent:
				return "%s is %d%%" % [name, roundi(v * 100.0)]
			return "%s is %s" % [name, _trim(v)]
	return ""


## Signed, type-aware rendering of [param v] via [method StatDef.format_number]
## — the value-only half of ADD_BASE/INCREASE/ADD_BONUS's "+N Stat" grammar.
## `format_number` already carries the sign for a negative value (both its
## branches print through a signed numeric format); this only adds the "+" a
## non-negative value needs, matching the old unconditional `"%+d"`.
static func _signed(value_type: StatDef.ValueType, v: float) -> String:
	var body := StatDef.format_number(value_type, v)
	return body if v < 0.0 else "+" + body


## Render a float without trailing ".00" — whole values print as ints.
## NOT type-aware — MULTIPLY/SET keep this literal-trim behaviour regardless
## of the stat's [enum StatDef.ValueType] (#622 acceptance 3); the type-aware
## sibling is [method StatDef.format_number], used by the other three ops.
static func _trim(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return "%d" % roundi(v)
	return ("%.2f" % v).trim_suffix("0")  # 1.50 → "1.5", 1.25 stays


## Fired when a source stat this modifier's formula depends on changes, via a
## connection a [StatBoard] made in [method StatBoard.bind_modifier]. Re-emits
## `changed()` so the target stat recomputes. No board/source-list state here
## — a modifier bound to N boards gets N independent connections into this
## same handler, guarded by the single `_propagating` flag above.
func _on_source_changed() -> void:
	if _propagating:
		return  # cycle guard: stops A→B→A from looping indefinitely
	_propagating = true
	emit_changed()
	_propagating = false

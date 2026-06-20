## Form for appending a new intrinsic modifier to a StatBoard.
## UI lives in the sibling .tscn; this script just wires the form.
##
## API:
##   populate(stat_ids)          — fill the stat dropdowns + remember the
##                                 candidate list for expression validation
##                                 and input-detection
##   preset_linear(src, target)  — prefill Linear-mode with these two stats
##                                 (used by drag-to-connect)
##   modifier_confirmed(mod)     — emitted on OK with the built modifier
@tool
extends ConfirmationDialog

signal modifier_confirmed(modifier: StatModifier)

const _OP_TAGS := ["+base", "+%", "×", "+bonus", "=set"]
const _KIND_CONSTANT := 0
const _KIND_LINEAR := 1
const _KIND_EXPRESSION := 2

@onready var _target: OptionButton = %Target
@onready var _operation: OptionButton = %Operation
@onready var _kind: OptionButton = %Kind
@onready var _value: SpinBox = %Value
@onready var _linear_source: OptionButton = %LinearSource
@onready var _linear_scale: SpinBox = %LinearScale
@onready var _expr_formula: LineEdit = %ExprFormula
@onready var _expr_status: Label = %ExprStatus
@onready var _constant_row: Control = %ConstantRow
@onready var _linear_row: Control = %LinearRow
@onready var _expr_row: Control = %ExprRow

# Snapshot of the populating board's stat ids — used for expression
# validation (Expression.parse against the full set) and input-detection
# (word-boundary match for the actually-referenced subset).
var _stat_ids: Array = []


func _ready() -> void:
	_operation.clear()
	for i in _OP_TAGS.size():
		var op_name: String = StatModifier.Operation.keys()[i]
		_operation.add_item("%s  (%s)" % [_OP_TAGS[i], op_name], i)
	_kind.clear()
	_kind.add_item("Constant", _KIND_CONSTANT)
	_kind.add_item("Linear (source × scale)", _KIND_LINEAR)
	_kind.add_item("Expression", _KIND_EXPRESSION)
	_kind.item_selected.connect(_on_kind_changed)
	_expr_formula.text_changed.connect(_on_expr_changed)
	confirmed.connect(_on_confirmed)
	_on_kind_changed(_kind.selected)


## Refresh the target / linear-source dropdowns and remember the candidate
## list for expression-mode validation.
func populate(stat_ids: Array) -> void:
	_stat_ids = stat_ids.duplicate()
	_target.clear()
	_linear_source.clear()
	for id in stat_ids:
		var label: String = str(id)
		_target.add_item(label)
		_linear_source.add_item(label)
	_on_expr_changed(_expr_formula.text)


## Prefill the form for a drag-from-source-to-target gesture (Linear kind).
func preset_linear(source_id: StringName, target_id: StringName) -> void:
	_select_option(_target, str(target_id))
	_select_option(_linear_source, str(source_id))
	_kind.select(_KIND_LINEAR)
	_on_kind_changed(_KIND_LINEAR)


func _select_option(opt: OptionButton, text: String) -> void:
	for i in opt.item_count:
		if opt.get_item_text(i) == text:
			opt.select(i)
			return


func _on_kind_changed(idx: int) -> void:
	_constant_row.visible = idx == _KIND_CONSTANT
	_linear_row.visible = idx == _KIND_LINEAR
	_expr_row.visible = idx == _KIND_EXPRESSION
	_update_ok_enabled()


func _on_expr_changed(_text: String) -> void:
	if _stat_ids.is_empty():
		_expr_status.text = "type a formula…"
		_expr_status.add_theme_color_override(&"font_color", Color(0.7, 0.7, 0.7))
	else:
		var err := ExpressionFormula.validate(_expr_formula.text, _stat_ids)
		if err == "":
			var detected := ExpressionFormula.detect_inputs(_expr_formula.text, _stat_ids)
			var names: Array[String] = []
			for id in detected:
				names.append(str(id))
			var joined: String = ", ".join(names) if names.size() > 0 else "(none)"
			_expr_status.text = "✓ detected inputs: %s" % joined
			_expr_status.add_theme_color_override(&"font_color", Color(0.55, 0.85, 0.55))
		else:
			_expr_status.text = "✗ %s" % err
			_expr_status.add_theme_color_override(&"font_color", Color(0.95, 0.55, 0.55))
	_update_ok_enabled()


func _update_ok_enabled() -> void:
	var ok := true
	if _kind.selected == _KIND_EXPRESSION and not _stat_ids.is_empty():
		ok = ExpressionFormula.validate(_expr_formula.text, _stat_ids) == ""
	get_ok_button().disabled = not ok


func _on_confirmed() -> void:
	if _target.selected < 0:
		return
	var target_id := StringName(_target.get_item_text(_target.selected))
	var op: int = _operation.selected
	var kind: int = _kind.selected

	var mod: StatModifier
	match kind:
		_KIND_CONSTANT:
			mod = StatModifier.new()
			mod.value = float(_value.value)
		_KIND_LINEAR:
			if _linear_source.selected < 0:
				return
			var lf := LinearFormula.new()
			lf.source_stat_id = StringName(_linear_source.get_item_text(_linear_source.selected))
			lf.scale_per_point = float(_linear_scale.value)
			var dm := DerivedStatModifier.new()
			dm.formula = lf
			mod = dm
		_KIND_EXPRESSION:
			var ef := ExpressionFormula.new()
			ef.formula = _expr_formula.text
			ef.inputs = ExpressionFormula.detect_inputs(_expr_formula.text, _stat_ids)
			var dm2 := DerivedStatModifier.new()
			dm2.formula = ef
			mod = dm2
		_:
			return
	mod.stat_id = target_id
	mod.operation = op
	modifier_confirmed.emit(mod)

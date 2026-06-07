## Form for appending a new intrinsic modifier to a StatBoard.
## UI lives in the sibling .tscn; this script just wires the form.
##
## API:
##   populate(stat_ids: Array[StringName])  →  fill the stat dropdowns
##   modifier_confirmed(mod)                →  emitted on OK with built modifier
@tool
extends ConfirmationDialog

signal modifier_confirmed(modifier: StatModifierDef)

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
@onready var _expr_inputs: LineEdit = %ExprInputs
@onready var _constant_row: Control = %ConstantRow
@onready var _linear_row: Control = %LinearRow
@onready var _expr_row: Control = %ExprRow


func _ready() -> void:
	_operation.clear()
	for i in _OP_TAGS.size():
		var op_name: String = StatModifierDef.Operation.keys()[i]
		_operation.add_item("%s  (%s)" % [_OP_TAGS[i], op_name], i)
	_kind.clear()
	_kind.add_item("Constant", _KIND_CONSTANT)
	_kind.add_item("Linear (source × scale)", _KIND_LINEAR)
	_kind.add_item("Expression", _KIND_EXPRESSION)
	_kind.item_selected.connect(_on_kind_changed)
	confirmed.connect(_on_confirmed)
	_on_kind_changed(_kind.selected)


## Refresh the target / linear-source dropdowns from the current board.
func populate(stat_ids: Array) -> void:
	_target.clear()
	_linear_source.clear()
	for id in stat_ids:
		var label: String = str(id)
		_target.add_item(label)
		_linear_source.add_item(label)


func _on_kind_changed(idx: int) -> void:
	_constant_row.visible = idx == _KIND_CONSTANT
	_linear_row.visible = idx == _KIND_LINEAR
	_expr_row.visible = idx == _KIND_EXPRESSION


func _on_confirmed() -> void:
	if _target.selected < 0:
		return
	var target_id := StringName(_target.get_item_text(_target.selected))
	var op: int = _operation.selected
	var kind: int = _kind.selected

	var mod: StatModifierDef
	match kind:
		_KIND_CONSTANT:
			mod = StatModifierDef.new()
			mod.value = float(_value.value)
		_KIND_LINEAR:
			if _linear_source.selected < 0:
				return
			var lf := LinearFormula.new()
			lf.source_stat_id = StringName(_linear_source.get_item_text(_linear_source.selected))
			lf.scale_per_point = float(_linear_scale.value)
			var dm := DerivedModifierDef.new()
			dm.formula = lf
			mod = dm
		_KIND_EXPRESSION:
			var ef := ExpressionFormula.new()
			ef.formula = _expr_formula.text
			var inputs: Array[StringName] = []
			for tok in _expr_inputs.text.split(",", false):
				var s: String = tok.strip_edges()
				if s != "":
					inputs.append(StringName(s))
			ef.inputs = inputs
			var dm2 := DerivedModifierDef.new()
			dm2.formula = ef
			mod = dm2
		_:
			return
	mod.stat_id = target_id
	mod.operation = op
	modifier_confirmed.emit(mod)

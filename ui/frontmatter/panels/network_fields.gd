class_name NetworkFields
extends VBoxContainer

## The address and port a human types before a socket opens (#582).
##
## [b]One place the digits are entered, for both networked routes.[/b] A
## [MenuGraph.Route] names a ROLE and nothing else — that is [NetworkConfig]'s
## whole reason to exist as a per-machine thing — so HOST and JOIN each need a
## field, and they need the same one: identical parsing, identical fallbacks,
## identical defaults. Two copies of `_port()` would be two answers to "what
## does junk in the box mean". This is that answer, once ([JoinPanel] and
## [HostPanel] both instance it).
##
## [b]A host hides the address row[/b] ([member show_address]) — a listener
## binds every interface, it does not dial one, which is also why
## [member NetworkConfig.address] is documented as unread on a host. What a host
## shows INSTEAD is where it can be reached, and that is the lobby's readout
## ([method NetworkConfig.advertised_endpoint]), not a field.
##
## Rows come from `labelled_row.tscn` (#690) and their labels are authored in
## this scene; only the [LineEdit] swap happens in code, because
## [method LabelledRow.set_widget] is a code API by construction.
##
## [b]Not `@tool`, deliberately[/b] — and that is what makes the line above
## safe. [LabelledRow] is not `@tool` either, so under the editor it loads as a
## placeholder instance on which `set_widget` would throw
## (`.claude/rules/gdscript-pitfalls.md`). The panels that mount this ARE
## `@tool`, and reach it exactly the way [JoinPanel] reached #531's screen: an
## `@onready` typed at this class, behind an editor-hint guard. The cost is an
## editor preview of two text boxes; the alternative is a throw in the editor
## that no headless test can see.

@onready var _address_row: LabelledRow = %AddressRow
@onready var _port_row: LabelledRow = %PortRow

## Whether the address row is offered at all. False on the host panel, where
## there is nothing to dial.
@export var show_address: bool = true:
	set = _set_show_address

var _address_edit: LineEdit
var _port_edit: LineEdit


func _ready() -> void:
	_address_edit = _fill(_address_row, NetworkConfig.DEFAULT_ADDRESS)
	_port_edit = _fill(_port_row, str(NetworkConfig.DEFAULT_PORT))
	_apply_show_address()


## Blank falls back to the default rather than dialling "" — a typo'd address
## should fail at the socket with a message, not here with a silent no-op.
func address() -> String:
	var text := _address_edit.text.strip_edges() if _address_edit != null else ""
	return text if not text.is_empty() else NetworkConfig.DEFAULT_ADDRESS


func port() -> int:
	var text := _port_edit.text.strip_edges() if _port_edit != null else ""
	return text.to_int() if text.is_valid_int() else NetworkConfig.DEFAULT_PORT


func _fill(row: LabelledRow, initial: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = initial
	return row.set_widget(edit) as LineEdit


func _set_show_address(value: bool) -> void:
	show_address = value
	_apply_show_address()


func _apply_show_address() -> void:
	if is_node_ready():
		_address_row.visible = show_address

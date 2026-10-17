@tool
class_name RingBody
extends ModalBodyBase
## [RingModal]'s body: a [RingView] of the entity's inner ring plus a detail
## panel for the hovered (else selected) cell — its aspect's glyph and noun,
## the exact grant, the cost and, when it cannot be bought, why. Resolves to
## `[cell_name]`; the UI never mutates the ring — [HudRoot] submits the
## [SpendRingCellCommand].
##
## Request: `{entity: Entity, table: RingTable}`. Re-populates on the entity's
## `ring_changed`, which is also what clears a pending buy — in a peer game the
## bought cell stays pending (confirm dead, the marker on it) until the host's
## confirmed command lands.

## Glyph size in the detail panel. Tentative, easy to change.
@export_range(8, 64) var glyph_px: int = 28

@onready var _view: RingView = %View
@onready var _glyph: TextureRect = %Glyph
@onready var _noun: Label = %Noun
@onready var _grant: Label = %Grant
@onready var _cost: Label = %Cost
@onready var _why: Label = %Why

var _entity: Entity = null
var _table: RingTable = null
var _selected: StringName = &""
var _hovered: StringName = &""
var _pending: StringName = &""


func _ready() -> void:
	_view.cell_hovered.connect(_on_hovered)
	_view.cell_clicked.connect(select)


func populate(request: Variant) -> void:
	var req := request as Dictionary
	if _entity != null and _entity.ring_changed.is_connected(_on_ring_changed):
		_entity.ring_changed.disconnect(_on_ring_changed)
	_entity = req.get("entity") as Entity
	_table = req.get("table") as RingTable
	_selected = &""
	_pending = &""
	if _entity != null:
		_entity.ring_changed.connect(_on_ring_changed)
	_refresh()


## Select `cell` (`&""` clears) — what a click on the view does.
func select(cell: StringName) -> void:
	_selected = cell if _table != null and _table.cell(cell) != null else &""
	_refresh()
	selection_changed.emit()


## The cell just confirmed; held until `ring_changed` lands it.
func mark_pending(cell: StringName) -> void:
	_pending = cell
	_refresh()
	selection_changed.emit()


## The authority refused `entity_id`'s buy of `cell`: drop it if it is the one
## pending here, so confirm comes back without a reopen. Any other refusal —
## another entity's, an older cell's — leaves the marker alone.
func refuse(entity_id: int, cell: StringName) -> void:
	if _entity != null and _entity.entity_id == entity_id and _pending == cell:
		clear_pending()


## Drop a pending buy that will never land (the authority refused it).
func clear_pending() -> void:
	if _pending == &"":
		return
	_pending = &""
	_refresh()
	selection_changed.emit()


func is_selection_valid() -> bool:
	return _pending == &"" and _selected != &"" and _why_locked(_selected) == ""


func status_text() -> String:
	if _pending != &"":
		return "Buying %s…" % _pending
	var pts := _points()
	if _selected == &"":
		if pts <= 0:
			return "No ring points — review only"
		return "%d ring point%s — select a cell" % [pts, "" if pts == 1 else "s"]
	var why := _why_locked(_selected)
	if why != "":
		return why
	return "%s — costs %d of %d" % [_selected, _table.cell(_selected).cost, pts]


func confirm_text() -> String:
	return "BUY"


func resolve() -> Array:
	return [_selected]


## One sentence why `cell` cannot be bought now, or "" when it can.
func _why_locked(cell: StringName) -> String:
	if _entity == null or _table == null:
		return "No ring to buy from"
	var c := _table.cell(cell)
	if c == null:
		return ""
	if _entity.ring_spent.has(cell):
		return "Already bought"
	if not _table.can_buy(_entity.ring_spent, cell):
		return "Locked — not linked to a bought cell"
	var pts := _points()
	if pts < c.cost:
		return "Locked — needs %d ring point%s, have %d" % [c.cost, "" if c.cost == 1 else "s", pts]
	return ""


func _points() -> int:
	var pool: PoolStat = _entity.stat_board.ring_points if _entity != null and _entity.stat_board != null else null
	return pool.available() if pool != null else 0


func _on_ring_changed() -> void:
	if _pending != &"" and _entity.ring_spent.has(_pending):
		_pending = &""
	if _entity.ring_spent.has(_selected):
		_selected = &""
	_refresh()
	selection_changed.emit()


func _on_hovered(cell: StringName) -> void:
	_hovered = cell
	_show_detail()


func _refresh() -> void:
	if not is_node_ready():
		return
	var spent: Array[StringName] = []
	if _entity != null:
		spent = _entity.ring_spent
	var marked := _pending if _pending != &"" else _selected
	_view.show_state(_table, spent, marked)
	_show_detail()


func _show_detail() -> void:
	var name_ := _hovered if _hovered != &"" else (_pending if _pending != &"" else _selected)
	var c := _table.cell(name_) if _table != null else null
	if c == null:
		_glyph.texture = null
		_noun.text = "Select a cell"
		_noun.remove_theme_color_override(&"font_color")
		_grant.text = ""
		_cost.text = ""
		_why.text = ""
		return
	var aspect := c.aspect as Aspect
	var ident: Identity = aspect.identity if aspect != null else c.sector
	_glyph.texture = IdentityBadge.glyph(ident, glyph_px) if ident != null else null
	_glyph.self_modulate = ident.tint if ident != null else Color.WHITE
	_noun.text = "%s  (T%d)" % [ident.noun if ident != null else String(name_), c.tier]
	if ident != null:
		_noun.add_theme_color_override(&"font_color", ident.tint)
	var lines: Array[String] = []
	for m in c.grants:
		for leaf in m.flatten():
			lines.append(leaf.format())
	_grant.text = "\n".join(lines)
	_cost.text = "Cost: %d" % c.cost
	if name_ == _pending:
		_why.text = "Pending — waiting for the host"
	else:
		_why.text = _why_locked(name_)

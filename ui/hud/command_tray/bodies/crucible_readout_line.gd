class_name CrucibleReadoutLine
extends HBoxContainer

## One aspect line of the [CrucibleReadout]: a small aspect badge and the
## [method ReadoutLines.ReadoutLine.text] behaviour change. Highlighted while
## its socket is hovered (the `TierValue` text tier, `TierLabel` at rest);
## expanded, it adds the detail — the spell's [method SpellAffinity.get_description],
## the socket's [InfusionExchange] line and the status's own description.

const _REST_TIER := &"TierLabel"
const _LIT_TIER := &"TierValue"

@onready var _badge: IdentityBadge = %Badge
@onready var _main: Label = %Main
@onready var _detail: Label = %Detail

var _line: ReadoutLines.ReadoutLine = null
var _highlighted := false


## Show [param line] of [param spell]; [param board] is the caster's (the
## affinity description folds through it, as the landing does).
func bind(line: ReadoutLines.ReadoutLine, spell: SpellDef, board: StatBoard) -> void:
	_line = line
	var aspect := AspectRoster.shared().by_id(line.aspect_id) if line != null else null
	_badge.identity = aspect.identity if aspect != null else null
	_badge.visible = _badge.identity != null
	_main.text = line.text() if line != null else ""
	_detail.text = _detail_of(line, spell, board)
	set_highlighted(_highlighted)


## The line shown, null unbound.
func line() -> ReadoutLines.ReadoutLine:
	return _line


## The socket feeding this line, −1 innate-only.
func socket() -> int:
	return _line.socket if _line != null else -1


func set_highlighted(on: bool) -> void:
	_highlighted = on
	_main.theme_type_variation = _LIT_TIER if on else _REST_TIER


func is_highlighted() -> bool:
	return _highlighted


func set_expanded(on: bool) -> void:
	_detail.visible = on and not _detail.text.is_empty()


func is_expanded() -> bool:
	return _detail.visible


func main_text() -> String:
	return _main.text


func detail_text() -> String:
	return _detail.text


static func _detail_of(line: ReadoutLines.ReadoutLine, spell: SpellDef, board: StatBoard) -> String:
	if line == null:
		return ""
	var parts: PackedStringArray = []
	var affinity := line.affinity_of(spell)
	if affinity != null:
		parts.append(affinity.get_description(board))
	var exchange := line.exchange(spell)
	if not exchange.is_empty():
		parts.append("Socket: %s" % exchange)
	if line.status != null:
		var described := line.status.get_description()
		if not described.is_empty():
			parts.append(described)
	return "\n".join(parts)


## Height of the main text's first row — where a trace meets this line.
func first_row_height() -> float:
	if _main == null:
		return size.y
	return _main.get_line_height() if _main.get_line_count() > 0 else _main.size.y

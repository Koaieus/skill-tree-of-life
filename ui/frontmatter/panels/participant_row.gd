class_name ParticipantRow
extends HBoxContainer
## One participant row: swatch, hero-colour picker, name, seat description
## ("you", "AI", "peer N"). Configured with a [Participant] in
## [method configure].
##
## [b]Widget order is a shared contract — four issues land here.[/b] #613 made
## the row a scene; #616 added the colour picker; #617 adds a faction emblem and
## #615 a camp dropdown. The authored order is, left to right:
##
## [codeblock]
##   Emblem? | Swatch | ColorPick | Sigil? | CorePick? | Camp? | Name | Seat
## [/codeblock]
##
## Only the widgets whose issue has landed exist as nodes; the rest are named
## here so the next author inserts rather than reshuffles. Two layout rules keep
## that additive: the row carries [b]no fixed width[/b] (it sizes from its
## content — the panel's old `_CONTENT_MAX_WIDTH` cap was retired in #611), and
## [code]Name[/code] is the sole `SIZE_EXPAND_FILL` child, so every widget added
## takes its space from the name label rather than from its neighbours.

## A slot chose a hero colour. The lobby owns the roster, so the row asks
## rather than writes — it never mutates the [Participant] it was configured
## with (#616 D1: the roster is authoritative for hero colour).
signal color_picked(color: Color)

## Edge of the generated colour chips in the picker's dropdown.
const _CHIP_PX := 16

var _participant: Participant = null
var _palette: PlayerPalette = null


func configure(participant: Participant, local_peer_id: int) -> void:
	_participant = participant
	get_node("%Swatch").color = participant.color
	get_node("%Name").text = participant.display_name
	get_node("%Seat").text = _describe_seat(participant, local_peer_id)


## Fill the colour dropdown from [param palette], greying out every colour in
## [param taken] that isn't this slot's own (#616 D6 — colours are unique
## across slots, and a slot must still be able to see the one it holds).
##
## Called by [LobbyScreen] after [method configure], because "what is taken"
## is a fact about the whole roster and only the lobby can see it.
func set_color_choices(palette: PlayerPalette, taken: Array[Color]) -> void:
	_palette = palette
	var pick: OptionButton = get_node("%ColorPick")
	# Connected here rather than in `_ready` so the row works whether or not it
	# has entered the tree — a test may configure one standalone.
	if not pick.item_selected.is_connected(_on_color_item_selected):
		pick.item_selected.connect(_on_color_item_selected)
	pick.clear()
	if palette == null:
		return
	var mine: Color = _participant.color if _participant != null else Color.WHITE
	for i in palette.colors.size():
		var color: Color = palette.colors[i]
		pick.add_icon_item(_chip(color), "")
		pick.set_item_metadata(i, color)
		if color == mine:
			pick.select(i)
		elif taken.has(color):
			pick.set_item_disabled(i, true)


func _on_color_item_selected(index: int) -> void:
	var pick: OptionButton = get_node("%ColorPick")
	var color: Variant = pick.get_item_metadata(index)
	if color is Color:
		color_picked.emit(color)


## A flat square of [param color] to use as a dropdown item icon. Generated
## rather than authored: twenty swatch `.png`s that must stay in lockstep with
## `player_palette.tres` would be twenty chances for the two to drift.
static func _chip(color: Color) -> ImageTexture:
	var image := Image.create(_CHIP_PX, _CHIP_PX, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


static func _describe_seat(p: Participant, local_peer_id: int) -> String:
	if p.kind == Participant.Kind.AI:
		return "AI"
	if p.is_local(local_peer_id):
		return "you"
	if p.peer_id == LobbyScreen._PENDING_PEER_ID:
		return "waiting…"
	return "peer %d" % p.peer_id

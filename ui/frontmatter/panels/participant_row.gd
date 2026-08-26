class_name ParticipantRow
extends HBoxContainer
## One participant row: swatch, hero-colour picker, core-class picker with its
## sigil preview, name, seat description ("you", "AI", "peer N"). Configured
## with a [Participant] in [method configure].
##
## [b]The row asks; it never writes.[/b] Both pickers emit a signal and leave
## the [Participant] alone — [LobbyScreen] owns the roster, and a row that wrote
## into it would make "who decided this seat's colour" a two-answer question.
##
## [b]Widget order is a shared contract — four issues land here.[/b] #613 made
## the row a scene; #616 added the colour picker; #617 adds a faction emblem and
## #615 a camp dropdown. The authored order is, left to right:
##
## [codeblock]
##   Emblem? | Swatch | ColorPick | Sigil | CorePick | Camp? | Name | Seat
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

## A slot chose a core class (#618). Same ask-don't-write contract as
## [signal color_picked]; the sigil is not a separate pick, it rides along on
## [member CoreClass.sigil].
signal core_class_picked(core: CoreClass)

## Edge of the generated colour chips in the picker's dropdown.
const _CHIP_PX := 16

var _participant: Participant = null
var _palette: PlayerPalette = null


func configure(participant: Participant, local_peer_id: int) -> void:
	_participant = participant
	get_node("%Swatch").color = participant.color
	get_node("%Name").text = participant.display_name
	get_node("%Seat").text = _describe_seat(participant, local_peer_id)
	_show_sigil_of(participant.core_class)


## Paint the sigil preview for [param core]. Handles the null cases the content
## actually has (#618 D4): five [CoreClass] resources exist against three
## [Sigil] concretes, so `basic_enemy_core` and `pacifist_core` carry no glyph —
## and a slot may momentarily carry no class at all. [SigilGlyph] draws nothing
## for a null sigil, so the row just shows an empty box of the same size and
## nothing after it shifts.
func _show_sigil_of(core: CoreClass) -> void:
	var glyph: SigilGlyph = get_node("%Sigil")
	glyph.sigil = core.sigil if core != null else null
	glyph.entity_tint = _participant.color if _participant != null else Color(0, 0, 0, 0)


## Fill the core-class dropdown with [param cores] — the classes THIS slot's
## kind may choose, filtered by the caller through
## [method CoreClass.pickable_for], because "am I a human or an AI seat" is a
## roster fact the row is not the authority on.
func set_core_choices(cores: Array[CoreClass]) -> void:
	var pick: OptionButton = get_node("%CorePick")
	if not pick.item_selected.is_connected(_on_core_item_selected):
		pick.item_selected.connect(_on_core_item_selected)
	pick.clear()
	var mine: CoreClass = _participant.core_class if _participant != null else null
	for i in cores.size():
		var core: CoreClass = cores[i]
		pick.add_item(core.display_name if core.display_name != "" else core.resource_path.get_file())
		pick.set_item_metadata(i, core)
		if core == mine:
			pick.select(i)
	pick.disabled = cores.is_empty()


func _on_core_item_selected(index: int) -> void:
	var pick: OptionButton = get_node("%CorePick")
	var core: Variant = pick.get_item_metadata(index)
	if core is CoreClass:
		_show_sigil_of(core)
		core_class_picked.emit(core)


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

class_name ParticipantRow
extends HBoxContainer
## One participant row: faction emblem, swatch, hero-colour picker, core-class
## picker with its sigil preview, camp dropdown, name, seat description ("you",
## "AI", "peer N"). Configured with a [Participant] in [method configure].
##
## [b]Two marks, two questions.[/b] The emblem is the CAMP's, tinted with the
## camp's colour, and answers "which side is this slot on"; the sigil is the
## slot's own [CoreClass] glyph, tinted with the hero colour, and answers "what
## does it play as". They are separate fields on separate resources (#617 D1)
## and are deliberately not collapsed into one picture.
##
## [b]The row asks; it never writes.[/b] Both pickers emit a signal and leave
## the [Participant] alone — [LobbyScreen] owns the roster, and a row that wrote
## into it would make "who decided this seat's colour" a two-answer question.
##
## [b]Widget order is a shared contract — four issues land here.[/b] #613 made
## the row a scene; #616 added the colour picker; #618 the core picker; #615 the
## camp dropdown and #617 the faction emblem. The authored order is, left to
## right:
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

## A slot chose a camp (#615). Same ask-don't-write contract as the other two —
## the camp is roster shape, and [LobbyScreen] owns the roster.
signal camp_picked(camp: Faction)

## Edge of the generated colour chips in the picker's dropdown.
const _CHIP_PX := 16

var _participant: Participant = null
var _palette: PlayerPalette = null

## May the machine drawing this row change what it shows (#714)? True by
## default, which is every lobby that was ever shipped before a second machine
## could see one: offline, hot-seat and the host's own lobby all leave it alone.
## A client sets it false on every seat but its own — see
## [method LobbyScreen.may_edit], which owns the rule.
var _editable: bool = true
## What each picker would be disabled by REGARDLESS of locality: an empty core
## list, a camp the policy locked. Kept so [method set_editable] can be called in
## any order relative to the three `set_*_choices` calls without either of them
## clobbering the other's reason for a grey control.
var _cores_empty: bool = true
var _camp_enabled: bool = false


## Lock or unlock every picker on this row (#714 acceptance 6). Locality is the
## only thing this decides on; WHY a control was already disabled is remembered
## separately, so re-enabling a row never un-greys a camp its policy locked.
func set_editable(editable: bool) -> void:
	_editable = editable
	_apply_disabled()


func _apply_disabled() -> void:
	get_node("%ColorPick").disabled = not _editable
	get_node("%CorePick").disabled = _cores_empty or not _editable
	# Left strictly alone while hidden: a lobby with no [LobbyPolicy] never calls
	# [method set_camp_choices] at all, and #615's characterization contract is
	# that such a row is byte-for-byte the pre-#615 one.
	var camp: OptionButton = get_node("%Camp")
	if camp.visible:
		camp.disabled = not _camp_enabled or not _editable


func configure(participant: Participant, local_peer_id: int) -> void:
	_participant = participant
	get_node("%Swatch").color = participant.color
	get_node("%Name").text = participant.display_name
	get_node("%Seat").text = _describe_seat(participant, local_peer_id)
	_show_sigil_of(participant.core_class)
	_show_emblem_of(participant.camp)


## Paint the camp mark for [param camp] (#617 D4 — display, not selection: the
## row shows the emblem of the camp the slot is on, and choosing that camp is
## #615's dropdown). Tinted with the camp's own colour rather than the hero's:
## the emblem answers "which side", while the swatch beside it answers "which
## hero", and tinting both the same would collapse two questions into one look.
##
## A camp with no emblem, or no camp at all, leaves an empty box of the same
## size — nothing after it shifts, same contract as [method _show_sigil_of].
func _show_emblem_of(camp: Faction) -> void:
	var mark: TextureRect = get_node("%Emblem")
	mark.texture = camp.emblem if camp != null else null
	mark.modulate = camp.color if camp != null else Color.WHITE
	mark.tooltip_text = camp.display_name if camp != null else ""


## Paint the sigil preview for [param core]. Every authored [CoreClass] carries
## a sigil today, but a slot may momentarily carry no class at all, or a future
## core may leave [member CoreClass.sigil] unset — [SigilGlyph] draws nothing
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
	_cores_empty = cores.is_empty()
	_apply_disabled()


func _on_core_item_selected(index: int) -> void:
	var pick: OptionButton = get_node("%CorePick")
	var core: Variant = pick.get_item_metadata(index)
	if core is CoreClass:
		_show_sigil_of(core)
		core_class_picked.emit(core)


## Fill the camp dropdown with [param camps], enabled iff [param enabled]
## (#615). Called by [LobbyScreen] only when the route carried a [LobbyPolicy] —
## a lobby with no policy never calls this, so `%Camp` stays hidden and the row
## is byte-for-byte the pre-#615 row, which is the characterization contract.
##
## An empty [param camps] hides the control; a non-empty one with
## [param enabled] false SHOWS it disabled. That distinction is the hot-seat
## shape: both humans are locked to one camp and the player should be able to
## see that rule rather than wonder where the dropdown went.
func set_camp_choices(camps: Array[Faction], enabled: bool) -> void:
	var pick: OptionButton = get_node("%Camp")
	if camps.is_empty():
		pick.visible = false
		return
	pick.visible = true
	if not pick.item_selected.is_connected(_on_camp_item_selected):
		pick.item_selected.connect(_on_camp_item_selected)
	pick.clear()
	var mine: Faction = _participant.camp if _participant != null else null
	var holds_mine := false
	for i in camps.size():
		var camp: Faction = camps[i]
		pick.add_item(camp.display_name if camp.display_name != "" else String(camp.id))
		pick.set_item_metadata(i, camp)
		if camp == mine:
			pick.select(i)
			holds_mine = true
	if not holds_mine:
		# A locked slot may sit on a camp outside the pool — `player.tres` in the
		# single-player shape, `npc.tres` on an AI. Show what it holds rather
		# than lie by selecting the pool's first entry.
		pick.add_item(mine.display_name if mine != null else "—")
		pick.set_item_metadata(camps.size(), mine)
		pick.select(camps.size())
	_camp_enabled = enabled
	_apply_disabled()


func _on_camp_item_selected(index: int) -> void:
	var pick: OptionButton = get_node("%Camp")
	var camp: Variant = pick.get_item_metadata(index)
	if camp is Faction:
		# Repainted here as well as on the lobby's rebuild, so the row is honest
		# standalone — same contract the sigil keeps for the core picker.
		_show_emblem_of(camp)
		camp_picked.emit(camp)


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

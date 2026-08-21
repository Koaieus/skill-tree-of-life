class_name LobbyScreen
extends MenuScreen

## Lobby: one row per participant (name/color are static placeholders —
## editable name + color picking is future work) plus a seed field and a
## Start button. The seed field is NOT wired to procgen yet (deliberately —
## see meta_root.gd); it's a placeholder for the input, not a working knob.
##
## Two shapes today (#456 LAN milestone scaffolding):
## - Single player: 1 row, [constant RunConfig.Mode.SINGLE], camp
##   `player.tres`.
## - Multiplayer (hot-seat) scaffold: 2 rows, both
##   [constant Participant.Kind.LOCAL_HUMAN], [constant
##   RunConfig.Mode.COOP_HOTSEAT], and — this is the point — both on the
##   SAME camp ([code]camp_1.tres[/code]), because hot-seat coop is two
##   allied humans sharing territory. Networking (peer join/leave, ENet) is
##   #463, out of scope here.

signal start_pressed(run_config: RunConfig)

const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")

## Placeholder player colors — row 1 matches procgen's enemy_colors[0] red
## (procgen_play_sandbox.gd), since there's no per-player color picker yet.
const _PLACEHOLDER_COLORS := [
	Color(0.95, 0.4, 0.4, 1.0),
	Color(0.4, 0.8, 1.0, 1.0),
]

var _mode: RunConfig.Mode = RunConfig.Mode.SINGLE
var _seed_edit: LineEdit
var _participants: Array[Participant] = []


## Configures this lobby before it enters the tree (call right after
## [method LobbyScreen.new], before pushing onto [MenuStack]). Defaults to
## the single-player shape so an unconfigured instance still behaves as it
## always has.
func configure(mode: RunConfig.Mode) -> void:
	_mode = mode


func _ready() -> void:
	super._ready()
	set_title("Lobby")

	_participants = _build_participants(_mode)
	for p in _participants:
		_add_participant_row(p)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	content.add_child(seed_row)

	var seed_label := Label.new()
	seed_label.text = "Seed:"
	seed_row.add_child(seed_label)

	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "random"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_edit)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)

	add_option("Start Game").pressed.connect(func(): start_pressed.emit(_build_run_config()))


func _add_participant_row(participant: Participant) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)

	var swatch := ColorRect.new()
	swatch.color = participant.color
	swatch.custom_minimum_size = Vector2(20, 20)
	row.add_child(swatch)

	var name_label := Label.new()
	name_label.text = participant.display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)


static func _build_participants(mode: RunConfig.Mode) -> Array[Participant]:
	var result: Array[Participant] = []
	if mode == RunConfig.Mode.COOP_HOTSEAT:
		result.append(_make_participant(1, "Player 1", _CAMP_1))
		result.append(_make_participant(2, "Player 2", _CAMP_1))
	else:
		result.append(_make_participant(1, "Player 1", _PLAYER_FACTION))
	for i in result.size():
		result[i].color = _PLACEHOLDER_COLORS[i % _PLACEHOLDER_COLORS.size()]
	return result


static func _make_participant(id: int, display_name: String, camp: Faction) -> Participant:
	var p := Participant.new()
	p.id = id
	p.display_name = display_name
	p.kind = Participant.Kind.LOCAL_HUMAN
	p.camp = camp
	return p


func _build_run_config() -> RunConfig:
	var cfg := RunConfig.new()
	cfg.mode = _mode
	cfg.seed = _parse_seed(_seed_edit.text)
	cfg.participants = _participants
	return cfg


## Non-numeric/empty text means seed = 0 — [RunConfig]'s documented legal
## authoring value for "randomise me".
static func _parse_seed(text: String) -> int:
	if text.is_empty() or not text.is_valid_int():
		return 0
	return text.to_int()

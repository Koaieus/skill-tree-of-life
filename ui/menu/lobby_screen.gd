class_name LobbyScreen
extends MenuScreen

## Single-player lobby: one player row (name/color are static placeholders —
## editable name + color picking is future work) plus a seed field and a
## Start button. The seed field is NOT wired to procgen yet (deliberately —
## see meta_root.gd); it's a placeholder for the input, not a working knob.

signal start_pressed(seed_text: String)

## Placeholder player color — matches procgen's enemy_colors[0] red
## (procgen_play_sandbox.gd), since there's no per-player color picker yet.
const PLACEHOLDER_PLAYER_COLOR := Color(0.95, 0.4, 0.4, 1.0)

var _seed_edit: LineEdit


func _ready() -> void:
	super._ready()
	set_title("Lobby")

	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 8)
	content.add_child(player_row)

	var swatch := ColorRect.new()
	swatch.color = PLACEHOLDER_PLAYER_COLOR
	swatch.custom_minimum_size = Vector2(20, 20)
	player_row.add_child(swatch)

	var name_label := Label.new()
	name_label.text = "Player 1"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_row.add_child(name_label)

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

	add_option("Start Game").pressed.connect(func(): start_pressed.emit(_seed_edit.text))

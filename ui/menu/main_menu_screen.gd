class_name MainMenuScreen
extends MenuScreen

signal single_player_pressed
signal options_pressed
signal quit_pressed


func _ready() -> void:
	super._ready()
	set_title("Skill Tree of Life")
	add_option("Single Player").pressed.connect(func(): single_player_pressed.emit())
	add_option("Multiplayer", true)
	add_option("Options").pressed.connect(func(): options_pressed.emit())
	add_option("Quit").pressed.connect(func(): quit_pressed.emit())

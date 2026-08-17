class_name SingleplayerMenuScreen
extends MenuScreen

signal new_game_pressed


func _ready() -> void:
	super._ready()
	set_title("Single Player")
	add_option("New Game").pressed.connect(func(): new_game_pressed.emit())
	add_option("Load Game", true)

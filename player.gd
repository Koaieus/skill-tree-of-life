extends TreeEntity
class_name Player

signal level_up(new_level: int, difference: int)
signal level_down(new_level: int, difference: int)

@export var player_name: String = "Player"
@export var level: int = 1:
	get(): return level
	set(value):
		var difference: int = level - value
		if difference == 0:
			return
		if difference > 0:
			_on_level_up(value, difference)
		else:
			_on_level_down(value, difference)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print(stats.strength)
	pass # Replace with function body.

## Direct access to stats, but typed, via 
@onready var stats: EntityStats:
	get():
		return _stats.stats

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_level_up(new_level: int, difference: int) -> void:
	emit_signal("level_up", new_level, difference)

func _on_level_down(new_level: int, difference: int) -> void:
	emit_signal("level_down", new_level, difference)

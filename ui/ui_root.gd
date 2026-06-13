extends Control
class_name UIRoot

@onready var stats_panel: StatsPanel = %StatsVBox
@onready var stat_board_overlay: StatBoardOverlay = %StatBoardOverlay
@onready var attack_mode_bar: AttackModeBar = %AttackModeBar

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

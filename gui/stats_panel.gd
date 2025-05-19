extends Control
class_name StatsPanel

@export var player: Player

const STAT_ROW = preload("res://gui/stat_row.tscn")

@onready var stats: EntityStats:
	get():
		return player.stats if player else null
		
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Global.player_selected.connect(_on_player_selected)
	Global.player_stats_changed.connect(
		func():
			print('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')
	)
	compute()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func clear_rows() -> void:
	for c in %StatsList.get_children():
		remove_child(c)
		c.queue_free()

func compute():
	print_debug("computing stats panel")
	
	clear_rows()
	if player:
		%NameLabel.text = player.player_name
	else:
		%NameLabel.text = "No player selected"
		return
	
	if not stats:
		return
	
	var row: StatRow
	for stat in stats.get_stats():
		row = STAT_ROW.instantiate()
		row.stat = stat
		row.text_display = stat.name()
		row.value_display = "%s" % [stat.display_value()]
		%StatsList.add_child(row)
	
func _on_player_selected(player: Player): 
	self.player = player
	#player.stats.stats_changed.connect(compute)
	compute()

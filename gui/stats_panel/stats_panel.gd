extends Control
class_name StatsPanel

@export var player: Player

#@onready var stats: EntityStats:
	#get():
		#return player.stats if player else null
		
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	initialize()
	Global.player_selected.connect(_on_player_selected)
	#Global.player_stats_changed.connect(compute)

## Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass

func clear_rows() -> void:
	for c in %StatsList.get_children():
		c.queue_free()

func initialize():
	#print_debug("[STATS PANEL]: initializing")
	
	clear_rows()
	if player:
		%NameLabel.text = player.player_name
	else:
		%NameLabel.text = "No player selected"
		return
	
	if not player._stats:
		return
	var stat_manager: StatsManager = player._stats
	for stat in stat_manager.stats.get_stats():
		#print('Generating row for %s...' % stat.name())
		var row := stat._generate_row(stat_manager)
		%StatsList.add_child(row)

func _on_player_selected(player: Player): 
	self.player = player
	#player.stats.stats_changed.connect(compute)
	initialize()

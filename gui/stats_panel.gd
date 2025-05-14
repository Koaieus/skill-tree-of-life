extends Control
class_name StatsPanel

@export var stats: Stats

const STAT_ROW = preload("res://gui/stat_row.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Global.player_selected.connect(_on_player_selected)
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
	
	if Global.player:
		%NameLabel.text = Global.player.player_name
	
	stats = Global.entity_at_turn._stats.stats
	if not stats:
		return []
	
	clear_rows()
	
	var row: StatRow
	for stat in stats.get_stats():
		row = STAT_ROW.instantiate()
		row.stat = stat
		row.text_display = stat.name()
		row.value_display = "%s" % [stat.display_value()]
		%StatsList.add_child(row)
	
func _on_player_selected(player: Player): 
	player.stats.stats_changed.connect(compute)
	compute()
